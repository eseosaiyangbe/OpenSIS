# OpenSIS Owned Kubernetes Path

This directory is the new owned Kubernetes path for `OpenSIS` in the shared DevOps Easy Learning workspace.

It exists because the older `OpenSIS` Kubernetes tree carried useful production-minded work, but it was built around older platform assumptions that no longer match the workspace standard.

Current workspace standard:

- shared local `k3s` runtime
- Traefik for ingress
- Vault as the secret source of truth
- Argo CD for GitOps
- shared observability through `Obervability-Stack`
- explicit `dev` and `prod` environments

## What Happened To The Older Kubernetes Tree

The previous OpenSIS Kubernetes implementation was preserved intact at:

- [k8s-legacy-platform](../k8s-legacy-platform)

That legacy tree still contains valuable reference material, including:

- older Vault Agent Injector integration
- Argo CD application structure
- MariaDB `StatefulSet` patterns
- backup and restore workflows
- historical production-edge notes

It is now treated as archival engineering history, not the active owned path for this workspace.

## What This New Path Will Own

This new `k8s/` tree will become the authoritative OpenSIS Kubernetes path for this project.

The intended owned shape is:

- `base`
  - application runtime
  - MariaDB
  - session Redis
  - Traefik ingress
  - minimal exporter and probe surfaces for the shared observability control plane
  - Vault-first runtime secret delivery
- `overlays/dev`
  - local `k3s` validation path
  - lower resources
  - local hostnames
  - `opensis-dev` namespace
- `overlays/prod`
  - stricter production contract
  - pinned images
  - production hostnames
  - `opensis-prod` namespace
- `argocd`
  - repo-owned application manifests for `dev` and `prod`

## Current Status

This tree is now the clean ownership boundary for the active OpenSIS Kubernetes path in this workspace.

What is already true:

- the older Kubernetes path has been archived under `k8s-legacy-platform`
- this new directory is now the active target for future OpenSIS Kubernetes work
- the assessment and migration decision for the new path is recorded in:
  - [OPENSIS-K8S-ASSESSMENT.md](../OPENSIS-K8S-ASSESSMENT.md)
- a live `k3s` `dev` rollout now works from this owned path with:
  - Traefik ingress on `opensis.devops.local`
  - Vault-backed External Secrets for app and DB env files
  - MariaDB and session Redis in the `opensis-dev` namespace
  - the expected first-run redirect to `install/index.php`

What is not claimed yet:

- a complete `prod` contract implementation from this new path

## Operator Path

The owned OpenSIS Kubernetes slice follows the same operator contract as the other migrated apps:

```bash
cd /Users/raymond/Documents/devops-easy-learning/opensis
./scripts/k8s-dev-deploy.sh
./scripts/k8s-dev-verify.sh
./scripts/k8s-dev-destroy.sh
```

Expected local dev hostname:

- `http://opensis.devops.local`

Local browser host entries can be refreshed with:

```bash
cd /Users/raymond/Documents/devops-easy-learning
./scripts/setup-devops-local-hosts.sh
```

Secrets for both `dev` and `prod` are sourced from the shared workspace Vault bootstrap through External Secrets Operator. The active seeding and role reconciliation entrypoint is:

```bash
cd /Users/raymond/Documents/devops-easy-learning
./scripts/bootstrap-k3s-vault-secrets.sh
```

## Related Documents

- [OPENSIS-K8S-ASSESSMENT.md](../OPENSIS-K8S-ASSESSMENT.md)
- [README.md](../README.md)
- [docs/03-kubernetes-bootstrap-guide.md](../docs/03-kubernetes-bootstrap-guide.md)
- [k8s-legacy-platform/README.md](../k8s-legacy-platform/README.md)
