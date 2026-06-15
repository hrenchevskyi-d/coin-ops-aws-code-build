# GitHub Actions Validation

This repository uses GitHub Actions as the first validation gate before AWS
CodeBuild/CodePipeline runs Terraform plans.

## Validation Jobs

### Config validation

Workflow: `.github/workflows/config-validation.yml`

Runs when manual Terraform JSON configs or schemas change:

- `terraform/config/*.json`
- `schemas/terraform-config/**`
- `scripts/validate-json-configs.sh`

It validates the hand-written config files against JSON Schema:

- `clouds.json`
- `general.json`
- `deploy.json`
- `database.json`
- `dns.json`
- `secrets.json`
- `instances.json`
- `networks.json`
- `cloud_mappings.json`
- `observability.json`

After schema validation, the same command runs semantic cross-file checks with
`scripts/validate-terraform-config-semantics.py`. These checks catch references
that are structurally valid JSON but operationally wrong, for example:

- `clouds.control_plane`, `clouds.secret_backend`, and `dns.primary_cloud` must
  be enabled clouds.
- `general.region_profile`, `general.image_profile`, and
  `general.instance_size` must exist in `cloud_mappings.json` for enabled
  clouds.
- Instance subnets, image profiles, and size profiles must exist for the enabled
  clouds where that instance is active.
- Firewall `source_role` and `target_role` values must match roles declared in
  `instances.json`.
- Enabled k3s load balancers must reference existing subnets.

Generated/local files are intentionally excluded:

- `terraform/config/hosts.json`
- `terraform/config/ansible-runtime.json`
- `terraform/local.generated.auto.tfvars.json`
- `ansible/vars/local.generated.json`
- `terraform/sa-key.json`

Run locally:

```bash
make config-validate
```

The schemas also provide editor hover descriptions through `.vscode/settings.json`.

### Terraform validation

Workflow: `.github/workflows/terraform-validation.yml`

Runs when Terraform, AWS CI scripts, or the Makefile change.

Checks:

```bash
terraform fmt -check -recursive
terraform init -backend=false -reconfigure
terraform validate
```

Run locally:

```bash
make terraform-validate
```

The local wrapper temporarily hides ignored `terraform/backend.active.tf` and uses
an isolated `TF_DATA_DIR`, so validation does not depend on local remote-backend
credentials.

Use this to format locally before committing:

```bash
make terraform-fmt
```

### Ansible validation

Workflow: `.github/workflows/ansible-validation.yml`

Runs when Ansible files, Compose templates, or the Makefile change.

The workflow installs Ansible Galaxy collections from `ansible/requirements.yml`
before linting. Without that step, `ansible-lint` cannot load playbooks that use
modules from collections such as `kubernetes.core`, `community.docker`,
`community.general`, or cloud provider collections.

Run locally:

```bash
make ansible-install-requirements
make ansible-lint
```

The initial lint gate uses `.ansible-lint` with `profile: min` and excludes
generated `ansible/artifacts/`. A full strict lint profile currently reports
existing repository debt such as FQCN usage, role variable naming, truthy YAML
values, and idempotency hints. Tighten the profile only after that debt is fixed
or explicitly baselined.

## Full Local Validation

Run the local equivalent of all GitHub Actions validation jobs:

```bash
make ci-validate
```

## Relationship To AWS CodeBuild

GitHub Actions is the fast validation layer. It checks repo structure, config
contracts, Terraform syntax, and Ansible linting.

AWS CodeBuild remains the managed AWS runtime for infrastructure planning and,
later, apply/provisioning workflows.
