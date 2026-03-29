# Kubernetes Base

See also: [Day-1 Production Architecture](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/DAY1_PRODUCTION_ARCHITECTURE.md)
See also: [From-Scratch Local Bootstrap](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)

This `k8s/` tree is the first production-minded migration layer for the business path only:

- `opensis-ui`
- `opensis-db`
- ingress
- Vault-backed secret delivery

It intentionally does not mirror the Docker Compose secret handoff. Instead, it assumes Kubernetes is already integrated with Vault using the Vault Agent Injector and Kubernetes auth.

## Design Intent

The base follows a more standard Kubernetes approach:

- MariaDB runs as a `StatefulSet`
- openSIS UI runs as a `Deployment`
- ingress is handled with a standard `Ingress` object
- each workload authenticates to Vault with its own Kubernetes `ServiceAccount`
- Vault Agent Injector renders `/run/secrets/app.env` and `/run/secrets/db.env` directly into the pods

This keeps the runtime behavior familiar to the application while avoiding Docker-era AppRole plumbing in the manifests.

## What Is Included

- Namespace and base kustomization
- openSIS DB `StatefulSet`, `Service`, `volumeClaimTemplates`, and `ServiceAccount`
- openSIS UI `Deployment`, `Service`, `Ingress`, and `ServiceAccount`
- ConfigMaps for app and DB runtime configuration
- Vault Injector annotations on the UI and DB pods

## Prerequisites

Before applying this base, the cluster should already have:

- Vault Agent Injector installed
- Vault Kubernetes auth enabled
- a Vault role for the app service account
- a Vault role for the DB service account
- KV secrets populated for the app and DB
- a default `StorageClass` or an overlay that sets the desired `storageClassName`

Expected Vault roles:

- `opensis-app`
- `opensis-db`

Expected secret paths:

- `kv/data/production/opensis-app`
- `kv/data/production/opensis-db`

## Important Notes

- This base assumes Vault is an external or separately managed platform dependency.
- TLS and ingress-class specifics should be set in overlays for your target cluster.
- Container images are still placeholders from the current local flow and should be replaced with pinned registry images before production.

## Suggested Apply Order

1. `namespace.yaml`
2. `opensis-db/*`
3. `opensis-ui/*`

## Example

```bash
kubectl apply -k k8s/base
```
