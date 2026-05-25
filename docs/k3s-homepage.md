# Homepage on k3s

This runbook describes the public Homepage deployment path for the `k3s`
platform.

## Architecture

- Homepage runs as a normal Kubernetes workload in its own namespace.
- A dedicated public Traefik ingress controller serves only public apps.
- Public HTTPS is terminated by a dedicated GCP public load balancer.
- Headlamp remains on the private ingress path and is not part of this public
  exposure model.

## Main Components

- `/home/notebook/projects/coin-ops/ansible/roles/k3s_public_ingress_controller`
- `/home/notebook/projects/coin-ops/ansible/roles/k3s_homepage_app`
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

3. Deploy Homepage and the public ingress controller:

   ```bash
   cd /home/notebook/projects/coin-ops
   ansible-playbook -i ansible/inventory/inventory.gcp_compute.yml ansible/k3s-homepage.yml
   ```

4. Open:

   ```text
   https://home.coinops-d.pp.ua/
   ```

## Validation

```bash
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml kubectl get pods -A
KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml kubectl get ingress -A
curl -vk https://home.coinops-d.pp.ua/
```

## Notes

- The current Homepage configuration ships with a minimal bookmark set.
- The public load balancer and DNS record are designed to be reusable for future
  public apps such as the main `coin-ops` service.
