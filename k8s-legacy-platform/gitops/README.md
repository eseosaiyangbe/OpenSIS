# GitOps Layer

This repo uses Argo CD as the GitOps controller for Kubernetes reconciliation.

See also: [From-Scratch Local Bootstrap](../FROM_SCRATCH_LOCAL_BOOTSTRAP.md)
See also: [Production-Grade CI/CD Blueprint](../PRODUCTION_GRADE_CICD_BLUEPRINT.md)

## What Lives Here

- [argocd/project.yaml](argocd/project.yaml): shared `AppProject` for openSIS
- [argocd/opensis-dev-application.yaml](argocd/opensis-dev-application.yaml): auto-sync application for the `dev` overlay
- [argocd/opensis-prod-application.yaml](argocd/opensis-prod-application.yaml): manual-sync application for the `prod` overlay

## Design Intent

- `dev` is reconciled automatically with prune and self-heal enabled
- `prod` is registered in Argo CD but intentionally left manual until the production overlay is shaped more deliberately
- the source of truth is the Git repository at `main`

## Example

Install Argo CD first, then apply this repo-owned GitOps layer:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -k k8s/gitops/argocd
```
