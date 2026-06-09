# Terraform Operations

This directory contains the multicloud infrastructure root module plus helper
scripts for bootstrapping, repair, and teardown.

## Normal Lifecycle

Initialize and inspect changes:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

When Azure is the control plane, remember that the backend Storage account name
must be globally unique across Azure. `bootstrap-azure.sh` now checks this and
fails early with a clear message if the configured name is already taken
outside the expected resource group. It also validates Azure naming rules:
3-24 characters, lowercase letters and numbers only.

When the secret backend has already been torn down or you are repairing drift,
disable secret-version reads during planning:

```bash
terraform plan -var='suppress_secret_manager_reads=true'
```

The same switch is safe for `apply`, `destroy`, and `refresh-only`.

Use `suppress_secret_manager_reads=true` only as a recovery / teardown switch.
It tells Terraform not to read secret **versions** from the configured cloud
secret backend while it reconciles the rest of the graph. This is useful when
the secret container still exists in configuration but the underlying secret
versions were already deleted, or when the secret backend is being
removed as part of the current teardown.

## Current Active Topology

The repository still keeps the multicloud design and related configuration, but
its current active access path no longer uses the old Tailscale subnet-router
gateway.

Current layout:
- `jump-host`: public bastion for operator SSH access into private nodes
- private workload nodes: reached through `ProxyJump` via `jump-host`
- cloud-native NAT: outbound internet access for private subnets without public
  IPs
- `Cloudflare Tunnel`: in-cluster path for private Headlamp browser access
- `full-destroy.sh`: pre-cleans Terraform-managed Cloudflare Tunnel, Access,
  and tunnel DNS resources before the final destroy when the Headlamp path is in scope

Important consequences:
- Tailscale configuration is still present in code for possible future reuse,
  but it is currently disabled in `terraform/config/networks.json`
- the old dedicated `gateway` instance has been removed from the active
  instance layout
- private nodes do **not** need public IPs for outbound access when the
  selected cloud's managed NAT path is enabled

## Post-Deploy Acceptance

After `terraform apply`, `ansible/provision.yml`, and the relevant Ansible
platform playbooks, verify the private-node access path in this order:

1. Confirm the jump host is reachable:

   ```bash
   ssh coinops-gcp-jump-host
   ```

2. Confirm a private k3s node is reachable through ProxyJump:

   ```bash
   ssh coinops-gcp-k3s-server-1
   ```

3. On a k3s node, confirm outbound internet works through Cloud NAT:

   ```bash
   curl -I https://github.com
   ```

4. Confirm the Headlamp tunnel rollout path:

   ```bash
   terraform apply
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
   ```

## Troubleshooting

If the jump host is reachable but a private `k3s-server` is not:
- verify the firewall rule allowing `jump-host -> k3s-server` on the SSH port
- verify the private node still has label/tag `k3s-server`
- confirm Ansible inventory is still using `ProxyJump=coinops-gcp-jump-host`

If a private `k3s-server` has no internet access:
- verify `cloud_nat.enabled=true` in `terraform/config/networks.json`
- verify the `internal` subnet is included in `cloud_nat.subnet_names`
- verify the GCP router NAT resources exist after `terraform apply`

If Headlamp tunnel apply fails with Cloudflare authentication errors:
- verify `dns.cloudflare.account_id` matches the Cloudflare account that owns
  Zero Trust
- verify the Cloudflare API token has Zero Trust Tunnel, Access Apps/Policies,
  Access Identity Providers, and DNS permissions

## Repairing Drift

If resources were partially deleted outside Terraform, prefer the repair helper
instead of immediately hand-editing state:

```bash
cd terraform
bash repair-refresh.sh --enabled gcp apply -var='suppress_secret_manager_reads=true'
```

Use `plan` instead of `apply` first if you want to inspect the refresh-only
delta before it is written back to state.

## Full Stateful Teardown

Stateful resources in this repository have `prevent_destroy` and
provider-side deletion protection enabled. To tear everything down on purpose,
use the dedicated helper:

```bash
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful --cloud all
```

Single-cloud teardown is also supported:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws
bash full-destroy.sh --yes-really-destroy-stateful --cloud azure
```

You can pass additional Terraform arguments through to the final destroy
command. The most useful one during recovery is:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp -var='suppress_secret_manager_reads=true'
```

`full-destroy.sh` works from an isolated temporary copy of the Terraform root
and keeps the checked-in files untouched. In that temporary copy it:

- removes `prevent_destroy` from database, secrets, and CNPG backup resources
- sets CNPG object-storage backup buckets to force-delete only in the temporary copy
- keeps CNPG backup resources instantiated in the temporary copy so destroy
  receives the force-delete bucket configuration
- includes AWS observability resources in AWS-only targeted teardown:
  CloudWatch alarms, dashboard, log metric filters, log group, SNS alerts,
  the CloudWatch Agent SSM parameter, and the EC2 observability IAM profile
- disables AWS RDS deletion protection before teardown
- disables and deletes GCP Cloud SQL instances found in state before teardown
- deletes GCP private service connections and reserved peering ranges that can
  otherwise outlive Cloud SQL and block VPC deletion
- retries GCP private service connection deletion while Google is still
  releasing producer services such as Cloud SQL from Service Networking
- treats the connection as already gone if Service Networking stops listing it
  even while delete calls still return stale cleanup errors
- falls back immediately to deleting or request-deleting any remaining Compute
  Engine peerings on the target VPC when Service Networking reports that a
  producer service is still blocking connection deletion
- then runs `terraform destroy` against the same backend state

If the secret backend or its versions were already removed, pass the recovery
switch through to the helper:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp -var='suppress_secret_manager_reads=true'
```

## Manual State Surgery

Use `terraform state rm ...` only after confirming the real cloud resource is
already gone. In most cases `repair-refresh.sh` or `full-destroy.sh` should be
enough, and state removal should be a last resort rather than the default flow.
