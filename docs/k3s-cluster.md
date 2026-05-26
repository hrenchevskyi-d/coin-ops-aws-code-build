# k3s Cluster Runbook

This runbook describes the standard command sequence for a clean `k3s`
infrastructure rollout in GCP and the shorter reconcile flows for an existing
cluster.

For the broader Ansible configuration model used by these playbooks, see:

- `/home/notebook/projects/coin-ops/docs/ansible-config-model.md`

## What Each Playbook Does

- `ansible/provision.yml`
  Prepares the VMs themselves: packages, firewall, common OS prerequisites, and
  host-level bootstrap requirements.
- `ansible/k3s-cluster.yml`
  Builds or reconciles the `k3s` control plane on the three `k3s-server` nodes.
  This includes bootstrap, join, post-checks, and local kubeconfig/helper
  artifact generation.
- `ansible/k3s-headlamp.yml`
  Installs or updates Headlamp in the cluster.
- `ansible/k3s-homepage.yml`
  Installs or updates Homepage on the existing ingress path.
- `ansible/k3s-platform.yml`
  Convenience entrypoint that runs `k3s-cluster.yml` and then
  `k3s-headlamp.yml`.

## Fresh Infrastructure Flow

Use this when the VMs are new or were just recreated by Terraform.

1. Create or update the infrastructure:

   ```bash
   cd /home/notebook/projects/coin-ops/terraform
   terraform plan
   terraform apply
   ```

2. Prepare the hosts:

   ```bash
   cd /home/notebook/projects/coin-ops
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/provision.yml
   ```

3. Bootstrap or reconcile the `k3s` cluster:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
   ```

4. Optionally install Headlamp:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
   ```

5. Or do steps 3 and 4 together:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-platform.yml
   ```

6. Optionally install Homepage:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-homepage.yml
   ```

## Existing Cluster Reconcile Flow

Use this when the VMs already exist and you only changed cluster-level
configuration.

### Reconcile just the cluster

```bash
cd /home/notebook/projects/coin-ops
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
```

### Reconcile just Headlamp

```bash
cd /home/notebook/projects/coin-ops
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
```

### Reconcile both

```bash
cd /home/notebook/projects/coin-ops
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-platform.yml
```

### Reconcile Homepage

```bash
cd /home/notebook/projects/coin-ops
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-homepage.yml
```

## When `provision.yml` Is Required Again

Re-run `ansible/provision.yml` if you:
- recreated the VMs
- changed base OS/firewall/package prerequisites
- changed jump-host reachability assumptions
- changed low-level networking or host bootstrap behavior

You usually do **not** need to re-run `provision.yml` for:
- Headlamp-only changes
- kubeconfig/helper artifact regeneration
- most `k3s` config changes that stay within the existing hosts

## HA API Load Balancer Note

If you change the GCP HA API load balancer in Terraform, re-run:

```bash
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
```

This is required so:
- the `k3s` server certificates include the HA API endpoint in `tls-san`
- local kubeconfig artifacts and tunnel helpers are regenerated with the new
  endpoint

## Generated Local Artifacts

After `ansible/k3s-cluster.yml`, expect operator-local artifacts under:

- `/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s.yaml`
- `/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml`
- `/home/notebook/projects/coin-ops/ansible/artifacts/k8s-api-tunnel.sh`
- `/home/notebook/projects/coin-ops/ansible/artifacts/k3s-bootstrap-summary.txt`

After `ansible/k3s-headlamp.yml`, expect additional artifacts such as:

- `/home/notebook/projects/coin-ops/ansible/artifacts/headlamp-access-summary.md`
- `/home/notebook/projects/coin-ops/ansible/artifacts/headlamp-port-forward.sh`
- `/home/notebook/projects/coin-ops/ansible/artifacts/headlamp-start.sh`

These files are local operator helpers and should not be committed.
