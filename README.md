# Coin-Ops Infrastructure

This repository contains the deployment infrastructure for Coin-Ops. Application images are pulled from GHCR; app source, local app builds, app tests, and smoke stacks are not kept here.

## What This Repo Owns

| Path | Purpose |
| --- | --- |
| `terraform/` | Cloud resources, remote-state bootstrap, multicloud networking, Cloudflare, secret-manager seeding, generated operator metadata |
| `ansible/` | Host provisioning, VM Compose deploys, k3s platform/app deploys, runtime config materialization |
| `deploy/compose/` | Jinja Docker Compose templates rendered by Ansible on VM targets |
| `deploy/sql/` | Retained PostgreSQL history/runtime bootstrap SQL used by infra deploys |
| `deploy/postgres-runtime/` | PostgreSQL 16 runtime image with `pg_cron` and `pgmq` |
| `packer/` | Optional golden-image build definitions for pre-baked app hosts |
| `docs/` | Operator runbooks |

## Deployment Model

Two deployment paths remain supported:

- VM Compose: `ansible/provision.yml` and `ansible/deploy.yml` render Compose stacks and pull GHCR images onto app hosts.
- k3s: `ansible/k3s-platform.yml`, `ansible/k3s-homepage.yml`, and `ansible/k3s-coinops.yml` install platform and application workloads into the cluster.

Both paths use the same image inputs resolved from `terraform/config/deploy.json`, generated metadata, cloud secrets, and optional environment overrides.

## Runtime Modes

- `RUNTIME_BACKEND=postgres`: normal mode. PostgreSQL runtime SQL enables `pgmq`, queue wrappers, cache/session tables, and `pg_cron` cleanup jobs.
- `RUNTIME_BACKEND=external`: rollback mode. RabbitMQ and Redis remain available in the VM Compose templates.

Runtime SQL lives under `deploy/sql/` because it is a database bootstrap asset required by infrastructure, not application source.

## Operator Quick Start

```bash
cd /home/notebook/projects/coin-ops
source local/generated-env.sh
make tf-check-backend
make runtime-config
```

Run static checks:

```bash
cd terraform
terraform fmt -check -recursive
terraform validate

cd /home/notebook/projects/coin-ops
make ansible-check
```

Apply infrastructure:

```bash
make tf-plan
make tf-apply
```

Deploy VM Compose path:

```bash
make provision
make deploy
```

Deploy k3s path:

```bash
make k3s-cluster
make k3s-platform
make k3s-homepage
make k3s-coinops
```

Build the PostgreSQL runtime image when its Dockerfile changes:

```bash
docker build -t coin-ops-postgres-runtime -f deploy/postgres-runtime/Dockerfile deploy/postgres-runtime
```

## Configuration

Canonical non-secret configuration is split across `terraform/config/*.json`:

- `clouds.json`: enabled clouds, control plane, secret backend, provider account metadata
- `general.json`: project name, region profile, username, SSH port, base image profile
- `instances.json`: VM layout and roles
- `networks.json`: VPC/VNet CIDRs, subnets, firewall rules, Tailscale route policy
- `deploy.json`: image registry/tag, TLS, runtime backend, k3s app settings
- `database.json`: database engine and cloud profiles
- `dns.json`: Cloudflare zone/account and DNS defaults
- `secrets.json`: secret manager object names

Terraform generates local operator metadata such as `terraform/config/hosts.json`, `terraform/config/ssh_config`, and `terraform/config/ansible-runtime.json`. Ansible `runtime_config` is the only supported merge point for config, generated metadata, environment overrides, and secrets.

## Generated Files and Secrets

Do not commit:

- `terraform/backend.active.tf`
- `terraform/local.generated.auto.tfvars.json`
- `terraform/config/hosts.json`
- `terraform/config/ssh_config`
- `terraform/config/ansible-runtime.json`
- `terraform/sa-key.json`
- `ansible/vars/local.generated.json`
- `ansible/artifacts/`
- `local/generated-*.sh`
- tfstate, kubeconfigs, private keys, and cloud credentials

## Notes

Multicloud, Tailscale, Cloudflare DNS/Access, Headlamp, Homepage, CNPG, VM Compose, and k3s stay supported. Do not add app source directories or direct browser calls to backend private IPs.
