# k3s_homepage

Deploys Homepage into `k3s` with Kubernetes-native resources and wires its
public ingress endpoint.

The role now also provisions:

- a dedicated Homepage `ServiceAccount`
- a read-only cluster-scoped RBAC policy for Homepage's Kubernetes widget
- conservative CPU and memory requests/limits for the Homepage pods

The default widget configuration enables cluster and node CPU/memory summaries
through Homepage's built-in Kubernetes integration (`mode: cluster`).
