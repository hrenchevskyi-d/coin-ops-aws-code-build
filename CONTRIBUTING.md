# Contributing

This repository is infrastructure-only. The application is deployed from existing GHCR images; do not add app source, local app build steps, or smoke stacks back into this repo.

## Before Opening a PR

Run the checks that match your change:

```bash
cd terraform
terraform fmt -check -recursive
terraform validate

cd /home/notebook/projects/coin-ops
make ansible-check
```

If you changed `deploy/postgres-runtime/`, also run:

```bash
docker build -t coin-ops-postgres-runtime -f deploy/postgres-runtime/Dockerfile deploy/postgres-runtime
```

If you changed Compose templates, render them through the owning Ansible role or validate the rendered file on a target host with `docker compose config -q`.

## Infrastructure Areas

- `terraform/`: cloud resources, remote-state bootstrap scripts, generated local metadata, Cloudflare, and multicloud networking.
- `ansible/`: host provisioning, VM Compose deploys, k3s platform roles, runtime configuration, and operator artifacts.
- `deploy/compose/`: Jinja-rendered VM Compose templates. Do not run these raw.
- `deploy/sql/`: retained PostgreSQL schema/runtime bootstrap SQL used by VM Compose and k3s CNPG deployments.
- `deploy/postgres-runtime/`: PostgreSQL 16 image with `pg_cron` and `pgmq` support.
- `docs/`: admin documentation.

## PR Expectations

Use a Conventional Commit style PR title when the change may reach `main`. Keep PRs scoped. Include:

- summary of changed infrastructure behavior
- affected clouds/playbooks/roles
- verification commands and results
- whether the change affects fresh installs, upgrades, or both
- any manual live-environment validation still needed

## Notes

`RUNTIME_BACKEND=external` remains rollback support. The normal path is PostgreSQL runtime mode. Application images are deployment inputs, not build outputs of this repository.
