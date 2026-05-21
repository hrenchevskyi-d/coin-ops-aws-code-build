# Headlamp via Port-Forward

This repository deploys Headlamp as an in-cluster application and exposes it to
operators through `kubectl port-forward`.

Current access model:
- Headlamp runs as a normal in-cluster workload
- operators access it from their own machine using `kubectl port-forward`
- no browser proxy, PAC file, or hosts-file override is required

This keeps the UI off the public internet while staying simple and predictable.

## What This Runbook Covers

This runbook explains:
- how Headlamp is deployed in the cluster
- which local artifacts are generated automatically
- how to open the UI from an operator machine
- how the SSH tunnel to the Kubernetes API works
- how to generate a login token
- common failure modes and what to check first

## Deployment flow

1. Reconcile the cluster:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
   ```

2. Install Headlamp:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
   ```

3. Or do both in one run:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-platform.yml
   ```

4. Review generated local access notes:

   - `ansible/artifacts/headlamp-access-summary.md`
   - `ansible/artifacts/k8s-api-tunnel.sh`
   - `ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml`
   - `ansible/artifacts/headlamp-port-forward.sh`
   - `ansible/artifacts/headlamp-start.sh`

## Generated Artifacts

After a successful run, the following local helper files are created:

- `ansible/artifacts/kubeconfig-gcp-k3s.yaml`
  Standard kubeconfig pointing at the preferred private Kubernetes API endpoint.
  When the GCP HA API load balancer is enabled, this points at the load
  balancer IP instead of a single control-plane node.
- `ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml`
  Operator kubeconfig intended for local use through the generated SSH tunnel.
- `ansible/artifacts/k8s-api-tunnel.sh`
  Opens a local tunnel from `127.0.0.1:6443` to the private Kubernetes API
  endpoint through the jump-host.
- `ansible/artifacts/headlamp-port-forward.sh`
  Uses the tunneled kubeconfig to port-forward local `127.0.0.1:8080` to the
  Headlamp service inside the cluster.
- `ansible/artifacts/headlamp-start.sh`
  Convenience wrapper that starts the API tunnel in the background if needed,
  then starts the Headlamp port-forward.
- `ansible/artifacts/headlamp-access-summary.md`
  Short generated operator notes.

These artifacts are operator-local and should not be committed to Git.

## Operator Access Runbook

### Preconditions

You need:
- `kubectl` installed on the machine where you will open the tunnel
- access to `terraform/config/ssh_config`
- generated artifacts under `ansible/artifacts/`
- network reachability to the jump-host from your operator machine

### Recommended Access Flow

1. Start the helper:

   ```bash
   /home/notebook/projects/coin-ops/ansible/artifacts/headlamp-start.sh
   ```

2. Keep that terminal open while using the UI.

3. Open Headlamp in a browser on the same machine:

   ```text
   http://127.0.0.1:8080/
   ```

4. Generate a login token in a separate terminal:

   ```bash
   KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
   kubectl create token headlamp-admin -n kube-system
   ```

5. Paste the token into the Headlamp login screen.

### Step-by-Step Manual Flow

If you do not want the combined helper, run the pieces manually.

1. Start the Kubernetes API tunnel:

   ```bash
   /home/notebook/projects/coin-ops/ansible/artifacts/k8s-api-tunnel.sh
   ```

2. In a second terminal, verify API access:

   ```bash
   KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
   kubectl get nodes
   ```

3. In a third terminal, start Headlamp port-forward:

   ```bash
   /home/notebook/projects/coin-ops/ansible/artifacts/headlamp-port-forward.sh
   ```

4. Open:

   ```text
   http://127.0.0.1:8080/
   ```

### WSL + Windows Browser

This setup works with:
- the tunnel and `kubectl port-forward` running inside WSL
- the browser running on Windows

In most modern WSL setups, Windows can open `http://127.0.0.1:8080/` while the
port-forward is running in WSL.

If the page does not open in Windows:
- confirm the port-forward process is still running in WSL
- check that Windows can reach the port:

  ```powershell
  Test-NetConnection 127.0.0.1 -Port 8080
  ```

### Stopping the Session

- `headlamp-port-forward.sh` runs in the foreground; stop it with `Ctrl+C`
- `headlamp-start.sh` leaves the API tunnel running in the background

To stop the background tunnel:

```bash
kill "$(cat /home/notebook/projects/coin-ops/ansible/artifacts/.k8s-api-tunnel.pid)"
rm -f /home/notebook/projects/coin-ops/ansible/artifacts/.k8s-api-tunnel.pid
```

## Operational Notes

- Headlamp itself runs as a Kubernetes workload with `replicaCount: 2`.
- Helm is only used as an installation/upgrade client on one control-plane node.
- Headlamp access is currently not exposed through Ingress; this runbook uses
  direct operator access via `kubectl port-forward`.
- Traefik may still exist in the cluster for future ingress-based workloads.
- If you enable or change the GCP HA API load balancer in Terraform, re-run
  `ansible/k3s-cluster.yml` afterwards so the `k3s` server certificates include
  the load balancer endpoint in `tls-san` and the local kubeconfig artifacts are
  regenerated accordingly.

## Security Notes

- Headlamp is not public by default.
- SSH access still goes through the jump-host.
- UI access still requires a Kubernetes token and RBAC authorization.
- The initial `headlamp-admin` binding uses `cluster-admin` for operator
  convenience and should be narrowed later if needed.
- `kubeconfig-gcp-k3s-tunneled.yaml` is sensitive because it grants cluster
  access when combined with network reachability.

## Troubleshooting

### `kubectl get nodes` fails with timeout or network unreachable

Most likely the API tunnel is not running.

Check:

```bash
ps -fp "$(cat /home/notebook/projects/coin-ops/ansible/artifacts/.k8s-api-tunnel.pid 2>/dev/null)" || true
ss -ltnp | grep 6443
```

Then restart:

```bash
/home/notebook/projects/coin-ops/ansible/artifacts/k8s-api-tunnel.sh
```

### Browser opens `127.0.0.1:8080` but Headlamp does not load

Check that the port-forward is alive:

```bash
ss -ltnp | grep 8080
```

Then restart:

```bash
/home/notebook/projects/coin-ops/ansible/artifacts/headlamp-port-forward.sh
```

### Token login fails

Generate a fresh token:

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
kubectl create token headlamp-admin -n kube-system
```

### Need to recreate the helper files

Re-run:

```bash
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
```
