# Headlamp via Tailscale and Ingress

This repository deploys Headlamp as an in-cluster application and exposes it
through Traefik Ingress for private operator access.

Current access model:
- Headlamp runs as a normal Kubernetes workload
- Traefik routes `http://headlamp.<app_domain>/` inside the cluster
- a dedicated `gateway` VM advertises the GCP subnet into Tailscale
- operators reach the private GCP subnet from their own machine through
  Tailscale
- `kubectl port-forward` remains available as a fallback path

This keeps the UI off the public internet while making browser access much
easier than SSH proxying.

## What This Runbook Covers

This runbook explains:
- how Headlamp is deployed
- how the Tailscale gateway fits into the network path
- how to open the UI from a Windows browser
- when to use the port-forward fallback
- how to generate a login token

## Deployment Flow

1. Reconcile the cluster:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
   ```

2. Install or update Headlamp:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
   ```

3. Or do both in one run:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-platform.yml
   ```

4. Review generated operator notes:

   - `ansible/artifacts/headlamp-ingress-access.md`
   - `ansible/artifacts/headlamp-access-summary.md`
   - `ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml`
   - `ansible/artifacts/headlamp-start.sh`

## Generated Artifacts

After a successful run, the following local helper files are relevant:

- `ansible/artifacts/headlamp-ingress-access.md`
  Primary runbook for browser access through Tailscale and Ingress.
- `ansible/artifacts/headlamp-access-summary.md`
  Port-forward fallback summary.
- `ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml`
  Operator kubeconfig for token generation and CLI use through the API tunnel.
- `ansible/artifacts/headlamp-start.sh`
  Fallback helper that opens the SSH tunnel and starts `kubectl port-forward`.

These artifacts are operator-local and should not be committed.

## Primary Access Path

### Preconditions

You need:
- Tailscale installed on the machine where your browser runs
- the GCP subnet route `10.20.0.0/16` advertised by the gateway and accepted by
  the client
- generated artifacts under `ansible/artifacts/`
- a local hosts entry or private DNS record for `headlamp.<app_domain>`

### Recommended Browser Flow

1. Sign in to Tailscale on your **Windows host**.

2. Confirm the route to GCP is active. `autoApprovers.routes` in the Tailscale
   ACL only auto-approves the gateway's advertised route; it does **not**
   guarantee the Windows client has installed and accepted that route yet.

3. Add a hosts entry on the machine where the browser runs. The generated file
   `ansible/artifacts/headlamp-ingress-access.md` shows the current private IP
   to use.

   Example:

   ```text
   10.20.1.7 headlamp.coinops.test
   ```

4. Open:

   ```text
   http://headlamp.<app_domain>/
   ```

5. Generate a login token from WSL or any operator shell:

   ```bash
   KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
   kubectl create token headlamp-admin -n kube-system
   ```

6. Paste the token into the Headlamp login screen.

## WSL + Windows Browser

Recommended split:
- run Terraform, Ansible, and `kubectl` in WSL
- run Tailscale and the browser on Windows

Why:
- the browser gets direct tailnet reachability without WSL proxy/tunnel issues
- WSL remains the CLI workspace

## Fallback Access Path

If Tailscale access is not ready yet, you can still use port-forward:

```bash
/home/notebook/projects/coin-ops/ansible/artifacts/headlamp-start.sh
```

Then open:

```text
http://127.0.0.1:8080/
```

This is a fallback, not the preferred day-to-day access path.

## Operational Notes

- Headlamp itself runs with `replicaCount: 2`.
- Traefik is the current ingress controller.
- The ingress hostname is `headlamp.<app_domain>`.
- The preferred private ingress endpoint is a static internal GCP load balancer
  IP. For this environment it is intended to be `10.20.1.77`.
- If you change the GCP HA API load balancer in Terraform, re-run
  `ansible/k3s-cluster.yml` so `tls-san` and the local kubeconfig artifacts are
  regenerated.

## Security Notes

- Headlamp is still private; it is not published to the public internet.
- Kubernetes auth still matters even with Tailscale.
- The initial `headlamp-admin` binding uses `cluster-admin` for convenience and
  should be narrowed later if needed.
- `kubeconfig-gcp-k3s-tunneled.yaml` is sensitive because it grants cluster
  access when combined with network reachability.

## Troubleshooting

### The browser cannot open `headlamp.<app_domain>`

Check:
- Tailscale is connected on Windows
- the Windows client is set to accept subnet routes and actually has a route for
  `10.20.0.0/16`
- the Windows hosts entry points to the IP shown in
  `ansible/artifacts/headlamp-ingress-access.md`
- the Tailscale ACL allows your user or device to reach `10.20.0.0/16`, not
  just the `tag:coinops-gateway` router itself

### Headlamp opens but login fails

Generate a fresh token:

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
kubectl create token headlamp-admin -n kube-system
```

### Need to recreate helper files

Re-run:

```bash
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
```
