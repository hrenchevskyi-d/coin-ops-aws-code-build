# Headlamp via Cloudflare Tunnel and Access

This repository deploys Headlamp as an in-cluster application and exposes it
through a remotely managed Cloudflare Tunnel protected by Cloudflare Access.

Current access model:
- Headlamp runs as a normal Kubernetes workload in `k3s`
- a `cloudflared` deployment runs in-cluster via the `cloudflare-tunnel-remote`
  Helm chart
- Cloudflare Tunnel publishes `https://headlamp.<app_domain>/`
- Cloudflare Access requires a GitHub login before the user can reach the
  Headlamp UI
- Headlamp itself still uses Kubernetes token login unless you later switch it
  to OIDC
- `kubectl port-forward` remains available as a fallback path

This keeps the UI off your private subnet routing model and removes the need for
Tailscale on the operator workstation for browser access.

## What This Runbook Covers

This runbook explains:
- how Headlamp is deployed
- how the Cloudflare Tunnel fits into the access path
- which Cloudflare and GitHub prerequisites are required
- how to open the UI from a browser
- when to use the port-forward fallback
- how to generate a login token

## Prerequisites

Before the tunnel can be created end-to-end, fill in the following inputs:
- `terraform/config/dns.json`
  - `dns.cloudflare.account_id`
- app secret backend payload (or the bootstrap tfvars used to seed it)
  - `CLOUDFLARE_API_TOKEN`
  - `GITHUB_OAUTH_CLIENT_ID`
  - `GITHUB_OAUTH_CLIENT_SECRET`

The Cloudflare API token needs permissions for:
- DNS edit on the target zone
- Zero Trust tunnel management
- Zero Trust Access applications and policies
- Zero Trust identity providers

The GitHub OAuth App should use the Cloudflare Access callback URL shown in the
Cloudflare Zero Trust GitHub login-method setup.

## Deployment Flow

1. Apply Terraform so Cloudflare resources and generated runtime metadata are up
   to date:

   ```bash
   cd terraform
   terraform apply
   ```

2. Reconcile the cluster:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
   ```

3. Install or update Headlamp and the in-cluster tunnel:

   ```bash
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-headlamp.yml
   ```

4. Review generated operator notes:

   - `ansible/artifacts/headlamp-access-summary.md`
   - `ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml`
   - `ansible/artifacts/headlamp-start.sh`

## Access Path

### Primary browser flow

1. Open:

   ```text
   https://headlamp.<app_domain>/
   ```

2. Cloudflare Access prompts for GitHub authentication.

3. After Access allows the session, Headlamp loads.

4. Generate a login token from WSL or any operator shell:

   ```bash
   KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
   kubectl create token headlamp-admin -n kube-system
   ```

5. Paste the token into the Headlamp login screen.

### Fallback path

If the tunnel is not ready yet or Cloudflare-side auth is still being wired,
use the local fallback helper:

```bash
/home/notebook/projects/coin-ops/ansible/artifacts/headlamp-start.sh
```

Then open:

```text
http://127.0.0.1:8080/
```

## Operational Notes

- `cloudflared` is deployed in Kubernetes, not on a VM.
- The tunnel is remotely managed from Cloudflare Zero Trust.
- Terraform now creates a proxied Cloudflare `CNAME` for
  `headlamp.<app_domain>` that points at the tunnel.
- The previous private `A` record to the internal ingress load balancer is no
  longer the intended steady-state path.
- Tailscale is preserved in code but disabled in the current config.
- The former dedicated gateway VM has been removed from the active topology.

## Security Notes

- Cloudflare Access is only the first gate; Headlamp still requires Kubernetes
  authentication.
- If `allowed_emails` is left empty in
  `terraform/config/deploy.json`, any GitHub-authenticated user can reach the
  Access prompt for this application. Restrict it before production use.
- `kubeconfig-gcp-k3s-tunneled.yaml` remains sensitive because it grants
  cluster access when combined with a valid token.

## Troubleshooting

### Cloudflare Access opens but Headlamp does not

Check:
- `terraform validate` and `terraform apply` succeeded
- `terraform/config/ansible-runtime.json` contains `headlamp_tunnel_token`
- `ansible/k3s-headlamp.yml` completed successfully
- the `cloudflare-tunnel-remote` release is running in the configured
  namespace

### GitHub login does not appear

Check:
- the Cloudflare Access GitHub identity provider was created successfully
- the GitHub OAuth client ID and secret are present in the app secret backend
- the OAuth callback URL configured in GitHub matches the one expected by
  Cloudflare Access

### Headlamp opens but login fails

Generate a fresh token:

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml \
kubectl create token headlamp-admin -n kube-system
```
