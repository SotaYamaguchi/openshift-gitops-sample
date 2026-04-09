# Platform GitOps Repository

GitOps-managed platform configuration for OpenShift / ROSA clusters.

## Architecture

See [docs/architecture.md](docs/architecture.md) for full details.

## Repository layout

```
bootstrap/          # Installs ArgoCD on each cluster and applies its ApplicationSet
apps/               # Platform component definitions
  core/             #   Common infrastructure for all clusters
  hub/              #   IDP cluster only (Backstage, Keycloak, Quay, etc.)
  workload/         #   Workload clusters only (AMQ Streams, etc.)
clusters/           # Per-cluster ApplicationSets
components/         # Shared Kustomize Components
infrastructure/     # Terraform / Terragrunt (AWS, ROSA, VPC, etc.)
templates/          # Backstage software templates
docs/               # Documentation
```

## Cluster inventory

| Cluster | Role |
|---|---|
| internal-developer-portal | Hub — Backstage, Keycloak, Quay |
| dev-workload | Development workloads |
| stg-workload | Staging workloads |
| prod-workload | Production workloads |

## Key conventions

- Each component follows `base/ + components/ + overlays/` Kustomize pattern
- Overlay names control scope: `all`, `hub`/`workload`, `workload-dev`, or cluster name
- A component must not have more than one overlay matching the same cluster
- ArgoCD on each cluster targets only itself (`https://kubernetes.default.svc`)
- ApplicationSets use Git directory generator to auto-discover overlays

## Common tasks

- **Add a new component**: Create `apps/<tier>/<component>/base/` + `overlays/<target>/`
- **Bootstrap a cluster**: `oc apply -k bootstrap/overlays/<cluster-name>/`
- **Validate manifests**: `kustomize build apps/<tier>/<component>/overlays/<target>/`
