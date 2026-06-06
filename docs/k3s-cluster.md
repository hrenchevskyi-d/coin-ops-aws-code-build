# k3s Cluster Runbook

The k3s path is one of the supported deployment paths in the infra-only repository.

## Main Flow

```bash
cd /home/notebook/projects/coin-ops
source local/generated-env.sh
make k3s-cluster
make k3s-platform
make k3s-homepage
make k3s-coinops
```

`k3s-cluster.yml` prepares the three server nodes, bootstraps the first server, joins the rest, configures packaged Traefik, and writes local access files.

AWS k3s uses the same playbooks, but Terraform config must explicitly enable
AWS and allow the `k3s-server-*` instances on AWS in `terraform/config/instances.json`.
For AWS runs, use `K8S_CLOUD=aws` so Makefile targets select the AWS inventory
and the AWS-generated kubeconfig artifact names.

## Operator Artifacts

Generated kubeconfigs and tunnel scripts are written under `ansible/artifacts/`. They are local, sensitive, and ignored by git.

Use the tunneled kubeconfig for localhost-driven Kubernetes work:

```bash
source ansible/artifacts/k8s-operator-env.sh
kubectl get nodes
```

For one-off checks without changing the current shell environment:

```bash
make kubectl ARGS='get nodes'
```

## Traefik Model

`ansible/roles/k3s_traefik` renders the packaged Traefik `HelmChartConfig`. Public load balancers should target the Terraform-defined ingress ports, not ad hoc app services.

## Reconcile Guidance

Re-run `make k3s-cluster` after host recreation, k3s config changes, or load-balancer endpoint changes. Re-run only the app/platform playbooks for Headlamp, Homepage, or Coin-Ops workload changes.
