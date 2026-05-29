# Coin-Ops Infrastructure Context

This repository is the infrastructure control plane for Coin-Ops. Application source has been removed; deploys pull GHCR image tags configured through `terraform/config/deploy.json`, `IMAGE_REGISTRY`, and `IMAGE_TAG`.

## Ownership Map

| Path | Purpose |
| --- | --- |
| `terraform/` | Cloud resources, multicloud networking, secret-manager seeding, Cloudflare, generated operator metadata |
| `ansible/` | Host provisioning, VM Compose deploy, k3s platform/app install, runtime config materialization |
| `deploy/compose/` | Jinja Docker Compose templates rendered by Ansible for VM deploys |
| `deploy/sql/` | PostgreSQL history/runtime bootstrap SQL |
| `deploy/postgres-runtime/` | PostgreSQL runtime image with `pg_cron` and `pgmq` |
| `packer/` | Optional golden-image build definitions for pre-baked app hosts |
| `docs/` | Operator runbooks and architecture notes |

## Supported Deployment Paths

- VM Compose: `ansible/provision.yml` then `ansible/deploy.yml` for the app-1/app-2 style deployment.
- k3s: `ansible/k3s-platform.yml`, `ansible/k3s-homepage.yml`, and `ansible/k3s-coinops.yml` for the cluster path.

Both paths consume GHCR application images. Neither path builds app code locally.

## Runtime Modes

- `postgres`: normal mode. PostgreSQL plus `pgmq`/`pg_cron` handles queue and runtime state.
- `external`: rollback mode. RabbitMQ and Redis remain in the Compose templates.

## Networking

- Multicloud support remains part of the design.
- Tailscale subnet routing remains supported for gateway-based inter-cloud reachability.
- Cloudflare DNS, Tunnel, and Access remain supported for public and admin entrypoints.
- Frontend traffic stays same-origin through `/api` and `/history-api` reverse proxy paths.

## Configuration Flow

1. Terraform reads split JSON config from `terraform/config/*.json`.
2. Terraform writes generated operator metadata such as `terraform/config/ansible-runtime.json` and SSH config.
3. Ansible `runtime_config` merges JSON config, generated metadata, optional local overrides, environment overrides, and cloud secret payloads.
4. Roles consume the flattened variables and render Compose, nginx, Kubernetes, and SQL bootstrap resources.

## Safety Notes

Generated files such as `terraform/backend.active.tf`, `terraform/local.generated.auto.tfvars.json`, `terraform/config/hosts.json`, `terraform/config/ansible-runtime.json`, `ansible/vars/local.generated.json`, and `ansible/artifacts/` are local generated files and must stay out of commits.
