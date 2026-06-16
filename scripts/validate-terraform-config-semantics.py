#!/usr/bin/env python3
"""Validate cross-file references in terraform/config/*.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any
from ipaddress import ip_network


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = REPO_ROOT / "terraform" / "config"


def load_json(name: str) -> dict[str, Any]:
    with (CONFIG_DIR / name).open(encoding="utf-8") as handle:
        return json.load(handle)


def as_set(value: Any) -> set[str]:
    if isinstance(value, list):
        return {str(item) for item in value}
    return set()


def has_key(mapping: Any, key: str) -> bool:
    return isinstance(mapping, dict) and key in mapping


def main() -> int:
    clouds_cfg = load_json("clouds.json")["clouds"]
    general_cfg = load_json("general.json")["general"]
    instances_cfg = load_json("instances.json")["instances"]
    networks_cfg = load_json("networks.json")
    deploy_cfg = load_json("deploy.json")["deploy"]
    mappings_cfg = load_json("cloud_mappings.json")
    database_cfg = load_json("database.json")["database"]
    dns_cfg = load_json("dns.json")["dns"]

    errors: list[str] = []

    enabled_clouds = as_set(clouds_cfg.get("enabled"))
    default_instance_clouds = as_set(clouds_cfg.get("default_instance_clouds"))
    control_plane = clouds_cfg.get("control_plane")
    secret_backend = clouds_cfg.get("secret_backend")
    known_clouds = {"gcp", "aws", "azure"}

    if not enabled_clouds:
        errors.append("clouds.enabled must contain at least one cloud")

    unknown_enabled = enabled_clouds - known_clouds
    if unknown_enabled:
        errors.append(f"clouds.enabled contains unsupported clouds: {sorted(unknown_enabled)}")

    if control_plane not in enabled_clouds:
        errors.append(f"clouds.control_plane '{control_plane}' must be listed in clouds.enabled")

    if secret_backend not in enabled_clouds:
        errors.append(f"clouds.secret_backend '{secret_backend}' must be listed in clouds.enabled")

    missing_defaults = default_instance_clouds - enabled_clouds
    if missing_defaults:
        errors.append(
            "clouds.default_instance_clouds must be a subset of clouds.enabled; "
            f"unknown enabled targets: {sorted(missing_defaults)}"
        )

    region_profile = str(general_cfg.get("region_profile", ""))
    image_profile = str(general_cfg.get("image_profile", ""))
    default_instance_size = str(general_cfg.get("instance_size", ""))

    for cloud in enabled_clouds:
        if not has_key(mappings_cfg.get("regions", {}).get(cloud), region_profile):
            errors.append(f"general.region_profile '{region_profile}' is not defined for {cloud} in cloud_mappings.json")
        if not has_key(mappings_cfg.get("images", {}).get(cloud), image_profile):
            errors.append(f"general.image_profile '{image_profile}' is not defined for {cloud} in cloud_mappings.json")
        if not has_key(mappings_cfg.get("instance_sizes", {}).get(cloud), default_instance_size):
            errors.append(f"general.instance_size '{default_instance_size}' is not defined for {cloud} in cloud_mappings.json")
        if database_cfg.get("enabled") and not has_key(database_cfg.get("cloud_profiles"), cloud):
            errors.append(f"database.cloud_profiles is missing enabled cloud '{cloud}'")

    dns_primary_cloud = dns_cfg.get("primary_cloud")
    if dns_primary_cloud not in enabled_clouds:
        errors.append(f"dns.primary_cloud '{dns_primary_cloud}' must be listed in clouds.enabled")

    cloud_networks = networks_cfg.get("cloud_networks", {})
    kubernetes_runtime = str(deploy_cfg.get("kubernetes", {}).get("runtime", "k3s"))
    eks_cfg = deploy_cfg.get("eks", {})
    aws_eks_active = "aws" in enabled_clouds and kubernetes_runtime == "eks" and eks_cfg.get("enabled", True)
    instance_roles: set[str] = set()

    for instance_name, instance_cfg in instances_cfg.items():
        instance_role = str(instance_cfg.get("role", ""))
        instance_roles.add(instance_role)

        instance_clouds = as_set(instance_cfg.get("clouds")) or default_instance_clouds
        subnet_name = str(instance_cfg.get("subnet", ""))
        instance_size = str(instance_cfg.get("instance_size", default_instance_size))
        instance_image_profile = str(instance_cfg.get("image_profile", image_profile))

        for cloud in instance_clouds & enabled_clouds:
            if aws_eks_active and cloud == "aws" and instance_role == "k3s-server":
                continue
            cloud_network = cloud_networks.get(cloud, {})
            subnets = cloud_network.get("subnets", {}) if isinstance(cloud_network, dict) else {}
            if subnet_name not in subnets:
                errors.append(f"instances.{instance_name}.subnet '{subnet_name}' is not defined for {cloud}")
            if not has_key(mappings_cfg.get("instance_sizes", {}).get(cloud), instance_size):
                errors.append(f"instances.{instance_name}.instance_size '{instance_size}' is not defined for {cloud}")
            if not has_key(mappings_cfg.get("images", {}).get(cloud), instance_image_profile):
                errors.append(f"instances.{instance_name}.image_profile '{instance_image_profile}' is not defined for {cloud}")

    firewall_rules = networks_cfg.get("firewall_rules", {})
    for rule_name, rule_cfg in firewall_rules.items():
        target_role = rule_cfg.get("target_role")
        source_role = rule_cfg.get("source_role")

        if target_role not in instance_roles:
            errors.append(f"firewall_rules.{rule_name}.target_role '{target_role}' does not match any instance role")
        if source_role is not None and source_role not in instance_roles:
            errors.append(f"firewall_rules.{rule_name}.source_role '{source_role}' does not match any instance role")

    for cloud, cloud_network in cloud_networks.items():
        if cloud not in enabled_clouds:
            continue
        subnets = cloud_network.get("subnets", {}) if isinstance(cloud_network, dict) else {}
        for lb_key in ("k3s_api_load_balancer", "k3s_public_ingress_load_balancer"):
            lb_cfg = cloud_network.get(lb_key, {}) if isinstance(cloud_network, dict) else {}
            if not isinstance(lb_cfg, dict) or not lb_cfg.get("enabled", False):
                continue
            subnet_refs = []
            for key in ("internal_subnet", "internal_subnets", "public_subnets"):
                value = lb_cfg.get(key)
                if isinstance(value, str):
                    subnet_refs.append(value)
                elif isinstance(value, list):
                    subnet_refs.extend(str(item) for item in value)
            for subnet_ref in subnet_refs:
                if subnet_ref not in subnets:
                    errors.append(f"cloud_networks.{cloud}.{lb_key} references unknown subnet '{subnet_ref}'")

    if aws_eks_active:
        aws_network = cloud_networks.get("aws", {})
        aws_subnets = aws_network.get("subnets", {}) if isinstance(aws_network, dict) else {}
        nat_cfg = aws_network.get("managed_nat_gateway", {}) if isinstance(aws_network, dict) else {}
        node_group = eks_cfg.get("node_group", {}) if isinstance(eks_cfg, dict) else {}

        if not eks_cfg.get("endpoint_public", True) and not eks_cfg.get("endpoint_private", True):
            errors.append("deploy.eks must enable at least one of endpoint_public or endpoint_private")

        try:
            ip_network(str(eks_cfg.get("service_ipv4_cidr", "10.43.0.0/16")))
        except ValueError as exc:
            errors.append(f"deploy.eks.service_ipv4_cidr is not a valid CIDR: {exc}")

        if int(node_group.get("min_size", 0)) > int(node_group.get("desired_size", 0)):
            errors.append("deploy.eks.node_group.min_size cannot be greater than desired_size")
        if int(node_group.get("desired_size", 0)) > int(node_group.get("max_size", 0)):
            errors.append("deploy.eks.node_group.desired_size cannot be greater than max_size")

        if not isinstance(nat_cfg, dict) or not nat_cfg.get("enabled", False):
            errors.append("deploy.kubernetes.runtime 'eks' requires cloud_networks.aws.managed_nat_gateway.enabled=true")
        else:
            nat_public_subnet = str(nat_cfg.get("public_subnet", ""))
            if nat_public_subnet not in aws_subnets:
                errors.append(f"cloud_networks.aws.managed_nat_gateway.public_subnet '{nat_public_subnet}' is not defined")
            elif not aws_subnets.get(nat_public_subnet, {}).get("public", False):
                errors.append(f"cloud_networks.aws.managed_nat_gateway.public_subnet '{nat_public_subnet}' must reference a public subnet")

        for subnet_ref in eks_cfg.get("private_subnets", []):
            if subnet_ref not in aws_subnets:
                errors.append(f"deploy.eks.private_subnets references unknown AWS subnet '{subnet_ref}'")
            elif aws_subnets.get(subnet_ref, {}).get("public", False):
                errors.append(f"deploy.eks.private_subnets '{subnet_ref}' must reference a private subnet")

        for subnet_ref in eks_cfg.get("public_subnets", []):
            if subnet_ref not in aws_subnets:
                errors.append(f"deploy.eks.public_subnets references unknown AWS subnet '{subnet_ref}'")
            elif not aws_subnets.get(subnet_ref, {}).get("public", False):
                errors.append(f"deploy.eks.public_subnets '{subnet_ref}' must reference a public subnet")

        for lb_key in ("k3s_api_load_balancer", "k3s_public_ingress_load_balancer"):
            lb_cfg = aws_network.get(lb_key, {}) if isinstance(aws_network, dict) else {}
            if isinstance(lb_cfg, dict) and lb_cfg.get("enabled", False):
                errors.append(f"cloud_networks.aws.{lb_key}.enabled must be false when deploy.kubernetes.runtime is 'eks'")

        jenkins_cfg = deploy_cfg.get("jenkins", {})
        if isinstance(jenkins_cfg, dict) and jenkins_cfg.get("enabled", False):
            for key in ("repository_url", "branch", "job_name"):
                if not str(jenkins_cfg.get(key, "")).strip():
                    errors.append(f"deploy.jenkins.{key} is required when Jenkins is enabled")

    if errors:
        print("Terraform config semantic validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Terraform config semantic validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
