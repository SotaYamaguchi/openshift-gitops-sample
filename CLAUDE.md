# Platform GitOps Repository

GitOps-managed platform configuration for OpenShift / ROSA clusters.

## Architecture

See [docs/architecture.md](docs/architecture.md) for full details.

## Repository layout

```
bootstrap/          # Installs ArgoCD Operator + ArgoCD CR + ApplicationSet
apps/               # Platform component definitions
  core/             #   Common infrastructure for all clusters
  hub/              #   IDP cluster only (RHACS, Quay, RHDH, RHTAS, RHTPA)
  workload/         #   Workload clusters only (Service Mesh, sample-app)
clusters/           # Per-cluster ApplicationSets
components/         # Shared Kustomize Components
docs/               # Documentation
```

## Cluster inventory

| Cluster | Role |
|---|---|
| idp-cluster | Hub — Developer Hub, Quay, ACS, TAS, TPA |
| dev-cluster | Development workloads |
| stg-cluster | Staging workloads |
| prod-cluster | Production workloads |

## Key conventions

- Each component follows `base/ + components/ + overlays/` Kustomize pattern
- Overlay names control scope: `all`, `hub`, or cluster name (`dev-cluster`, etc.)
- A component must not have more than one overlay matching the same cluster
- ArgoCD on each cluster targets only itself (`https://kubernetes.default.svc`)
- ApplicationSets use Git directory generator to auto-discover overlays
- Operator CR uses sync-wave "1" + SkipDryRunOnMissingResource to wait for CRD registration
- Subscription health check ensures Operator is installed before CR sync

## Common tasks

- **Add a new component**: Create `apps/<tier>/<component>/base/` + `overlays/<target>/`
- **Bootstrap a cluster**: `oc apply -k bootstrap/overlays/<cluster-name>/`
- **Validate manifests**: `oc kustomize apps/<tier>/<component>/overlays/<target>/`
