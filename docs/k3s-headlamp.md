# Headlamp

Headlamp is an operator UI installed into k3s. Cloudflare Tunnel and Access remain supported for browser access, while local port-forward helpers remain available as fallback.

## Deploy

```bash
cd /home/notebook/projects/coin-ops
source local/generated-env.sh
make k3s-cluster
make k3s-headlamp
```

Terraform owns Cloudflare Tunnel, Access, and DNS inputs. Ansible installs the in-cluster workload and writes helper notes under `ansible/artifacts/`.

## Access

Primary path:

```text
https://headlamp.<app_domain>/
```

Fallback:

```bash
ansible/artifacts/headlamp-start.sh
```

Generate a login token:

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml kubectl create token headlamp-admin -n headlamp
```

## Notes

Cloudflare Access is an outer gate. Headlamp still requires Kubernetes authentication. Keep generated kubeconfigs and helper scripts out of commits.
