# Platform GitOps Repository

GitOps-managed platform configuration for a fleet of OpenShift / ROSA clusters.

## Cluster inventory

| Cluster | Role |
|---|---|
| internal-developer-portal | Hub cluster. Hosts Backstage, Keycloak, Quay, and other management services |
| dev-workload | Development application workloads |
| stg-workload | Staging application workloads |
| prod-workload | Production application workloads |

ArgoCD is distributed across all clusters. Each cluster manages itself — no remote cluster references are used.

## Repository layout

```
.
├── bootstrap/          # Installs ArgoCD on each cluster and applies its ApplicationSet
├── apps/               # Platform component definitions
│   ├── core/           #   Common infrastructure for all clusters (ArgoCD, cert-manager, logging, etc.)
│   ├── hub/            #   IDP cluster only (Backstage, Keycloak, Quay, etc.)
│   └── workload/       #   Workload clusters only (AMQ Streams, etc.)
├── clusters/           # Per-cluster ApplicationSets
├── components/         # Shared Kustomize Components used across the repository
├── infrastructure/     # Terraform / Terragrunt (AWS, ROSA, VPC, etc.)
├── templates/          # Backstage software templates
└── docs/               # Documentation
```

## Distributed ArgoCD

```
┌─────────────────────┐  ┌─────────────────────┐
│ IDP                 │  │ dev-workload         │
│  ArgoCD ↻ self      │  │  ArgoCD ↻ self       │
│  core/ + hub/       │  │  core/ + workload/   │
│                     │  │  + github-token apps  │
└─────────────────────┘  └─────────────────────┘
┌─────────────────────┐  ┌─────────────────────┐
│ stg-workload        │  │ prod-workload        │
│  ArgoCD ↻ self      │  │  ArgoCD ↻ self       │
│  core/ + workload/  │  │  core/ + workload/   │
│  + github-token apps│  │  + github-token apps │
└─────────────────────┘  └─────────────────────┘
```

Every cluster's ArgoCD targets only itself via `destination.server: https://kubernetes.default.svc`. No ArgoCD cluster secrets are required.

Because ArgoCD is needed on every cluster, it lives in `apps/core/argocd/` rather than `apps/hub/`.

## apps/ design

### Tier classification

To decide which tier a component belongs to, ask: "If we added another cluster, would it need this component too?"

- **core/** — Infrastructure that every cluster needs. ArgoCD, cert-manager, external-secrets, openshift-logging, RBAC, monitoring, etc.
- **hub/** — Management services needed only on the IDP cluster. Backstage, Keycloak, Quay, Grafana, Tekton Pipelines, etc.
- **workload/** — Components needed only on workload clusters. AMQ Streams, internal-routes, etc.

### base / components / overlays pattern

Every component follows the same directory structure.

```
apps/<tier>/<component>/
├── base/               # Minimum resources required for the component to function
├── components/         # Optional feature modules (Kustomize Component)
└── overlays/           # Target-specific patches
```

**Role of each layer:**

- **base/** contains the minimum resources a component needs to run — Operator Subscription, CRD instances, namespace, etc.
- **components/** contains optional features defined as `kind: Component`. Overlays include them via the `components:` field. Example: ArgoCD's notifications, image-updater, and rollout-manager.
- **overlays/** contain target-specific patches. Each overlay references the base, composes the desired components, and overrides cluster-specific values such as domain names and AWS credentials.

### Overlay naming convention

The overlay directory name controls its scope. There are four levels of granularity.

| Overlay name | Granularity | Applied to |
|---|---|---|
| `all` | All clusters | IDP, dev, stg, prod |
| `hub` / `workload` | Type | hub → IDP only, workload → dev + stg + prod |
| `workload-dev` / `workload-prod` | Type-env | A specific environment within a type |
| `internal-developer-portal` / `dev-workload` | Cluster | That cluster only |

Examples:

```
apps/core/cluster-monitoring/overlays/all/             # Same config on all clusters
apps/core/external-secrets/overlays/hub/               # IDP-specific SecretStore
apps/core/external-secrets/overlays/workload/          # Workload-specific SecretStore
apps/core/cert-manager/overlays/workload-prod/         # Production-only domain
apps/core/rbac/overlays/internal-developer-portal/     # IDP-specific user bindings
```

**Critical rule: a component must not have more than one overlay that matches the same cluster.** For example, if cert-manager has both `overlays/all/` and `overlays/dev-workload/`, two Applications will be generated for dev-workload and they will conflict. Choose exactly one granularity level per component.

### When to split into a component

Ask: "Can the component function without this feature?"

- No → put it in **base/** (e.g. Quay's operator.yaml and quayregistry.yaml)
- Yes → extract it into **components/** (e.g. Quay's bridge-operator and team-sync)
- Value differs per cluster → put it in **overlays/** (e.g. S3 credential ExternalSecret)

## clusters/ design

Each cluster's ArgoCD reads its ApplicationSets from a corresponding directory.

```
clusters/
├── internal-developer-portal/
│   ├── kustomization.yaml
│   └── applicationset.yaml               # core + hub
├── dev-workload/
│   ├── kustomization.yaml
│   ├── applicationset.yaml               # core + workload
│   └── applicationset-github-token.yaml   # Developer team apps
├── stg-workload/
│   ├── kustomization.yaml
│   ├── applicationset.yaml
│   └── applicationset-github-token.yaml
└── prod-workload/
    ├── kustomization.yaml
    ├── applicationset.yaml
    └── applicationset-github-token.yaml
```

`applicationset-github-token.yaml` exists only on workload clusters. Each cluster's ArgoCD discovers its own apps via an SCM Provider × Git directory Matrix generator.

### ApplicationSet structure

Each `applicationset.yaml` uses a Git directory generator to discover overlays.

```yaml
# clusters/dev-workload/applicationset.yaml
generators:
  - git:
      repoURL: &repo https://github.com/your-org/platform-gitops.git
      revision: &rev main
      directories:
        - path: apps/*/*/overlays/all            # L1: all clusters
        - path: apps/*/*/overlays/workload       # L2: type
        - path: apps/*/*/overlays/workload-dev   # L3: type-env
        - path: apps/*/*/overlays/dev-workload   # L4: cluster

template:
  metadata:
    name: '{{path[1]}}-{{path[2]}}'
  spec:
    source:
      path: '{{path}}'
    destination:
      server: https://kubernetes.default.svc    # Always targets itself
```

The only difference between clusters is the list of directories:

```
IDP:           all, hub, internal-developer-portal
dev-workload:  all, workload, workload-dev, dev-workload
stg-workload:  all, workload, workload-stg, stg-workload
prod-workload: all, workload, workload-prod, prod-workload
```

### Bootstrap sequence

Run the following on each cluster:

1. Manually apply `bootstrap/` → ArgoCD is installed
2. ArgoCD picks up `clusters/<cluster-name>/` → ApplicationSets are created
3. ApplicationSets discover matching overlays under `apps/` → Applications are generated automatically

## components/ design

Resources shared across multiple apps or tiers live in the root `components/` directory.

- **shared-tekton-tasks/** — Shared pipeline tasks referenced by both `apps/core/pipelines/` and app repositories generated from `templates/`
- **alerting-common/** — Common alert definitions referenced by both Grafana alerting and platform-alerting

These are distinct from app-level `components/` (e.g. `apps/core/argocd/components/notifications/`). The root `components/` serves as a repository-wide shared library, while app-level `components/` controls feature variations within a single component.

## infrastructure/ design

AWS resources are managed with Terraform + Terragrunt. This is outside the scope of GitOps (Kustomize / ArgoCD).

Key resources: VPC, ROSA clusters, IAM, Route53, S3 (Quay / Tempo / Logging), SES, CodeArtifact, VPN, ACK.

## Adding a new component

1. Choose a tier (core / hub / workload)
2. Create resources in `apps/<tier>/<component>/base/`
3. If the component has optional features, extract them into `components/` as `kind: Component`
4. Choose an overlay granularity and create `overlays/<target>/kustomization.yaml`
5. In the overlay, reference the base and compose the desired components

```yaml
# overlays/<target>/kustomization.yaml — basic template
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

components:                      # Optional — list only the features you need
  - ../../components/feature-a

patches:                         # Optional — override cluster-specific values
  - path: patch-domain.yaml
```

As long as the overlay directory matches `apps/*/*/overlays/<target>`, the corresponding cluster's ApplicationSet will automatically generate an Application. No manual ArgoCD Application registration is needed.
