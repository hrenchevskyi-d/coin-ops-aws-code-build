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

`k3s-cluster.yml` prepares the three server nodes, bootstraps the first server, joins the rest, configures packaged Traefik, and exports local operator artifacts.

## Operator Artifacts

Generated files are written under `ansible/artifacts/`, including kubeconfigs and tunnel helpers. They are local, sensitive, and ignored by git.

Use the tunneled kubeconfig for localhost-driven Kubernetes work:

```bash
make k8s-api-ready
export KUBECONFIG=/home/notebook/projects/coin-ops/ansible/artifacts/kubeconfig-gcp-k3s-tunneled.yaml
```

## Traefik Model

`ansible/roles/k3s_traefik` renders a `HelmChartConfig` that keeps Traefik as the cluster ingress entrypoint. Public load balancers should target node ports/host ports according to Terraform network config, not ad hoc app services.

## Reconcile Guidance

Re-run `make k3s-cluster` after host recreation, k3s config changes, or load-balancer endpoint changes. Re-run only the app/platform playbooks for Headlamp, Homepage, or Coin-Ops workload changes.
