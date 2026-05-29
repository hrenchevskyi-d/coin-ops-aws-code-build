# Repository Guidelines

## Project Structure & Module Organization

This repository now contains infrastructure only. Terraform lives in `terraform/`, Ansible in `ansible/`, VM Compose templates in `deploy/compose/`, PostgreSQL bootstrap SQL in `deploy/sql/`, and the PostgreSQL runtime image in `deploy/postgres-runtime/`. Operator docs live in `docs/` plus the top-level runbook files.

Application source is absent. Deployments pull GHCR images through `IMAGE_REGISTRY`, `IMAGE_TAG`, and the image defaults resolved by Ansible.

## Build, Test, and Development Commands

Infrastructure checks:

```bash
cd terraform
terraform fmt -check -recursive
terraform validate

cd /home/notebook/projects/coin-ops
make ansible-check
```

Deployment:

```bash
source local/generated-env.sh
make tf-check-backend
make tf-plan
make tf-apply
make provision
make deploy
make k3s-platform
make k3s-coinops
```

PostgreSQL runtime image, when changed:

```bash
docker build -t coin-ops-postgres-runtime -f deploy/postgres-runtime/Dockerfile deploy/postgres-runtime
```

## Coding Style & Naming Conventions

Use Terraform `fmt` defaults. YAML files use two-space indentation. Ansible task names should describe the admin action. Keep comments short and practical. Do not add local application build or test paths.

## Testing Guidelines

Minimum verification for infrastructure changes is Terraform format/validate and Ansible syntax checks. For Compose template changes, render through Ansible or inspect the rendered YAML with `docker compose config -q` on a target host. For k3s changes, run the relevant playbook against a staging or lab cluster when static checks are not enough.

## Commit & Pull Request Guidelines

Use concise, imperative commit messages. Pull requests should include affected infrastructure areas, verification commands, and any required live-environment follow-up. Mention whether changes affect fresh installs, upgrades, or both.

## Security & Configuration Tips

Never commit real credentials, generated env files, kubeconfigs, tfstate, or local cloud keys. Use cloud secret managers, generated local env files, and ignored Terraform artifacts. Container images are pulled from GHCR; do not add app source or local image builds back into this repo.

## Architecture Notes

Terraform creates cloud resources and generated local metadata. Ansible configures hosts, deploys VM Compose stacks, and installs k3s workloads. PostgreSQL stores history and runtime state; `RUNTIME_BACKEND=external` is RabbitMQ/Redis rollback support only.

Frontend URLs stay same-origin (`/api` and `/history-api`) so nginx can reverse-proxy to backend services. Direct browser calls to private backend IPs are for CORS debugging only.

Multicloud, Tailscale subnet routing, Cloudflare DNS/Access, Headlamp, Homepage, CNPG, VM Compose, and k3s are all supported infrastructure concerns and should remain intact.
