# Homepage on k3s

This runbook describes the public Homepage deployment path for the `k3s`
platform.

## Architecture

- Homepage runs as a normal Kubernetes workload in its own namespace.
- Existing `k3s` Traefik serves Homepage using a dedicated host rule.
- Public HTTPS is exposed through a dedicated GCP public load balancer that
  targets the existing ingress path.
- Headlamp remains on its own host rule and DNS path.
- Homepage talks to the Kubernetes API from inside the cluster by using its own
  `ServiceAccount`, a read-only `ClusterRole`, and a `ClusterRoleBinding`.

## Main Components

- `/home/notebook/projects/coin-ops/ansible/roles/k3s_homepage`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_homepage/files/chart`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_ingress_endpoint`
- `/home/notebook/projects/coin-ops/ansible/k3s-homepage.yml`

## Deployment Flow

1. Ensure the cluster and host prerequisites are current:

   ```bash
   cd /home/notebook/projects/coin-ops
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/provision.yml
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-cluster.yml
   ```

2. Apply Terraform for the public load balancer and DNS:

   ```bash
   cd /home/notebook/projects/coin-ops/terraform
   terraform plan
   terraform apply
   ```

3. Deploy Homepage:

   ```bash
   cd /home/notebook/projects/coin-ops
   make k3s-homepage
   ```

4. Open:

   ```text
   https://home.coinops-d.pp.ua/
   ```

## Validation

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s.yaml kubectl get pods -n homepage
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s.yaml kubectl get serviceaccount,clusterrole,clusterrolebinding | grep homepage
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s.yaml kubectl get ingress -n homepage
curl -vk https://home.coinops-d.pp.ua/
```

## Notes

- The current Homepage configuration ships with a minimal bookmark set plus the
  built-in Kubernetes cluster widget.
- The Homepage workload is installed from a local Helm chart staged by the
  `k3s_homepage` role.
- The Homepage pod gets a dedicated in-cluster identity through a `ServiceAccount`;
  read-only access is granted separately via RBAC.
- The public load balancer and DNS record are designed to be reusable for future
  public apps such as the main `coin-ops` service.
