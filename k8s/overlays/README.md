# Overlays

This directory contains environment-specific Kustomize overlays built on top of [k8s/base](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/kustomization.yaml).

## Design Intent

- `base` holds the shared architecture
- `dev` holds local-learning and lower-risk defaults
- `prod` holds production-facing hostnames, issuers, and image references

## dev

The dev overlay is intended for local and lab clusters.

It currently changes:

- namespace to `opensis-dev`
- `APP_ENV` to `dev`
- Vault roles and paths to `opensis-app-dev` / `opensis-db-dev`
- ingress host to `opensis.dev.local`
- issuer to `local-selfsigned`
- smaller DB storage and lower resource requests
- app image pinned through Kustomize to the CI-backed branch tag `docker.io/eseosaiyangbe/opensis-ui:main`

Apply it with:

```bash
kubectl apply -k k8s/overlays/dev
```

## prod

The prod overlay is intended as the production-facing shape.

It currently changes:

- namespace to `opensis`
- app replicas to `2`
- ingress host to `opensis.example.com`
- issuer to `letsencrypt-prod`
- app image pinned through Kustomize to the immutable production tag `docker.io/eseosaiyangbe/opensis-ui:git-36ee457`
- production Vault roles and secret paths

Before using it in a real release flow, replace the current production tag with your next immutable release tag and keep the hostname values aligned.

Apply it with:

```bash
kubectl apply -k k8s/overlays/prod
```
