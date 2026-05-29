# Multicloud Scope

Multicloud support remains in scope for the infra-only repository.

## Preserved Capabilities

- GCP, AWS, and Azure provider support in Terraform.
- Dynamic inventory for each enabled cloud.
- Shared instance policy through `terraform/config/instances.json` and `terraform/config/cloud_mappings.json`.
- Cross-cloud routing metadata in `terraform/config/networks.json`.
- Tailscale subnet-router support for gateway-based inter-cloud routes.
- VM Compose and k3s deployment paths consuming the same GHCR image inputs.

## Current Boundaries

- Application images are not built here.
- PostgreSQL runtime mode is the normal path.
- RabbitMQ/Redis external mode is retained only for rollback.
- Managed RabbitMQ/Redis equivalents remain future design work, not part of this cleanup.
- Cloud-specific managed PostgreSQL support stays guarded by existing Terraform and Ansible validation.

## Change Guidance

Keep cloud-specific behavior in provider modules, inventory plugins, or role defaults. Shared settings belong in `terraform/config/*.json` and flow through `ansible/roles/runtime_config` instead of being copied into inventories or playbooks.
