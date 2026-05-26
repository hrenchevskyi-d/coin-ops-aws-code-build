# Ansible Configuration Model

This document describes the current Ansible configuration model after the
`group_vars` removal and the refactor toward composable roles.

## Goals

The current Ansible layer is built around these rules:

- `ansible/inventory/group_vars/*` is not used.
- Infrastructure and platform policy live in `terraform/config/*.json`.
- Runtime and secret materialization happen only through the
  `runtime_config` role.
- Role-local behavior and technical defaults live in `roles/*/defaults/main.yml`.
- Roles should be narrow and composable where practical.
- `k3s` remains explicitly `k3s`-specific; we do not pretend it is generic
  upstream Kubernetes.

## Sources Of Truth

### 1. Terraform JSON configuration

The primary declarative configuration lives under:

- `/home/notebook/projects/coin-ops/terraform/config/clouds.json`
- `/home/notebook/projects/coin-ops/terraform/config/general.json`
- `/home/notebook/projects/coin-ops/terraform/config/deploy.json`
- `/home/notebook/projects/coin-ops/terraform/config/database.json`
- `/home/notebook/projects/coin-ops/terraform/config/dns.json`
- `/home/notebook/projects/coin-ops/terraform/config/secrets.json`
- `/home/notebook/projects/coin-ops/terraform/config/instances.json`
- `/home/notebook/projects/coin-ops/terraform/config/networks.json`
- `/home/notebook/projects/coin-ops/terraform/config/cloud_mappings.json`

These files define platform policy such as:

- control-plane cloud
- network topology
- instance layout
- TLS mode
- `k3s` settings
- Headlamp settings
- Tailscale settings
- image registry and tag defaults

### 2. Generated runtime metadata

Terraform also produces generated runtime metadata consumed by Ansible:

- `/home/notebook/projects/coin-ops/terraform/config/ansible-runtime.json`
- `/home/notebook/projects/coin-ops/ansible/vars/local.generated.json`

Typical values coming from generated metadata:

- private IPs
- HA API endpoint
- Headlamp ingress IP
- Homepage public IP / hostname
- managed database connection metadata
- secret backend selection overrides

### 3. Role defaults

Each role owns its technical defaults via:

- `roles/*/defaults/main.yml`

These defaults should contain role-local behavior such as:

- file paths
- chart names
- namespaces
- retry counts
- local helper filenames
- default ports for a role-specific service

They should not redefine global platform policy if that policy already exists in
Terraform JSON or `runtime_config`.

### 4. Runtime materialization

The role:

- `/home/notebook/projects/coin-ops/ansible/roles/runtime_config`

is the only supported place where:

- Terraform JSON
- generated runtime files
- environment overrides
- secret backends

are merged into the flat Ansible-friendly variables used by playbooks and
roles.

## How Runtime Resolution Works

The role:

- `/home/notebook/projects/coin-ops/ansible/roles/runtime_config/tasks/main.yml`

materializes values in this order:

1. Base configuration from `terraform/config/*.json`
2. Optional defaults from `/home/notebook/projects/coin-ops/ansible/vars/deploy-config.yml`
3. Generated local overrides from `local.generated.json`
4. Environment overrides such as:
   - `APP_DOMAIN`
   - `TLS_MODE`
   - `IMAGE_TAG`
   - `COINOPS_SECRET_BACKEND`
5. Secret payloads from the selected backend

This role exports values such as:

- `runtime_backend`
- `app_domain`
- `tls_mode`
- `certbot_staging`
- `image_registry`
- `image_tag`
- `cloudflare_api_token`
- `tailscale_auth_key`
- `k3s_api_endpoint`
- `headlamp_ingress_ip`
- `homepage_public_ip`
- `homepage_public_host`

## Playbook Pattern

Playbooks are expected to include `runtime_config` explicitly in `pre_tasks`.

Example pattern:

```yaml
pre_tasks:
  - name: Resolve runtime configuration
    include_role:
      name: runtime_config
      public: true
```

This is intentional. The project no longer relies on implicit inventory-side
variable injection.

The local inspection playbook is:

- `/home/notebook/projects/coin-ops/ansible/runtime-config.yml`

It is exposed via:

```bash
make runtime-config
```

## Inventory Model

Dynamic inventory is still used for actual hosts, but only for:

- host discovery
- grouping by role/cloud
- SSH connection details

It is no longer used as a configuration source of truth.

Important inventory files:

- `/home/notebook/projects/coin-ops/ansible/inventory/inventory.gcp_compute.yml`
- `/home/notebook/projects/coin-ops/ansible/inventory/inventory.aws_ec2.yml`
- `/home/notebook/projects/coin-ops/ansible/inventory/inventory.azure_rm.yml`

These inventory definitions now compute things like:

- `ansible_user`
- `ansible_port`
- `ansible_ssh_private_key_file`
- `ansible_ssh_common_args`

including `ProxyJump` where needed.

## Role Composition Pattern

The repository is moving toward composable roles with orchestration kept in
playbooks where possible.

### `k3s` example

The `k3s-headlamp.yml` playbook drives a functional Headlamp role that reuses
shared cluster roles where that is actually worthwhile:

- `/home/notebook/projects/coin-ops/ansible/roles/k3s_helm_client`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_cert_manager`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_acme_cloudflare`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_headlamp`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_ingress_endpoint`

The same pattern is now reused for public app exposure:

- `/home/notebook/projects/coin-ops/ansible/roles/k3s_homepage`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_ingress_endpoint`

The current Homepage role installs the workload from a local Helm chart and
keeps ingress/TLS as separate reusable cluster concerns.

This is the preferred direction for new work: one role should own one coherent
responsibility whenever that remains practical.

### Compose helper example

Legacy Compose-based roles now share helper/meta roles instead of duplicating
the same lifecycle tasks:

- `/home/notebook/projects/coin-ops/ansible/roles/compose_stack`
- `/home/notebook/projects/coin-ops/ansible/roles/ufw_managed_port`

These are used by roles such as:

- `ui`
- `proxy`
- `history`
- `backend_tls`

## Templates And Kubernetes Resources

Kubernetes resources should prefer one of these patterns:

1. `kubernetes.core.k8s` with:

```yaml
definition: "{{ lookup('template', 'resource.yaml.j2') | from_yaml }}"
```

2. `kubernetes.core.k8s` with `from_yaml_all` for multi-document manifests.

The project should avoid:

- inline `copy: content:` for manifests
- applying rendered manifests through unnecessary shell glue

This pattern is already used in the `k3s` Headlamp/TLS path.

## Shell And Command Exceptions

The project tries to minimize `shell` and `command`, but a few deliberate
exceptions remain.

### Accepted exceptions today

- `k3s` installer flow
- `tailscale up`
- some `iptables` inspection/manipulation
- some `openssl` certificate generation flows
- some `docker compose` lifecycle commands
- some database bootstrap/runtime commands in `history`

These are not preferred by default, but they remain where:

- Ansible has no equally good native module
- the native-module alternative would be more fragile
- the flow is strongly tool-specific rather than generic

When adding new automation, prefer native modules first and treat `shell` or
`command` as explicit exceptions rather than the baseline approach.

## Tags

Tags are supported to make orchestration more selective without reintroducing
config sprawl.

Common tags now include:

- `runtime_config`
- `k3s`
- `k3s_prereqs`
- `k3s_bootstrap`
- `k3s_join`
- `k3s_postcheck`
- `headlamp`
- `cert_manager`
- `tls`
- `tailscale`
- `artifacts`

Tags should control already-separated task or role boundaries. They should not
be used to hide complex branching logic inside a monolithic role.

## Current Deployment Direction

The actively validated path is now Kubernetes-first:

- `ansible/provision.yml`
- `ansible/k3s-cluster.yml`
- `ansible/k3s-headlamp.yml`
- `ansible/k3s-platform.yml`

The legacy Compose path:

- `/home/notebook/projects/coin-ops/ansible/deploy.yml`

still exists, but should be treated as transitional unless a specific runtime
component still depends on it.

## Practical Verification

Without running the legacy deploy path, the recommended Ansible checks are:

```bash
cd /home/notebook/projects/coin-ops
make runtime-config
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/provision.yml
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-platform.yml
```

Then verify:

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml kubectl get nodes
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml kubectl get pods -A
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml kubectl get clusterissuer,certificate -A
curl -vk https://headlamp.coinops-d.pp.ua/
curl -vk https://home.coinops-d.pp.ua/
```

For static checks:

```bash
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local ansible/runtime-config.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local ansible/provision.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local ansible/k3s-cluster.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local ansible/k3s-headlamp.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local ansible/k3s-homepage.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --syntax-check -i localhost, -c local ansible/k3s-platform.yml
```

## Rules For Future Changes

When adding or refactoring Ansible code in this repository:

1. Do not reintroduce `group_vars`.
2. Put platform policy in Terraform JSON when it is truly global.
3. Put role-local defaults in `roles/*/defaults/main.yml`.
4. Use `runtime_config` for all secret/backend/runtime materialization.
5. Prefer narrow roles and `include_role` over large monolithic roles.
6. Prefer templates and native modules over inline shell glue.
7. Keep `k3s`-specific assumptions explicit.
