# Day-1 Production Architecture

This document defines the first real production layer for the openSIS Kubernetes migration.

It is intentionally narrow. Day 1 is not about moving every Compose service into Kubernetes. It is about standing up the business path in a way that is secure, supportable, and easy to evolve:

- `opensis-ui`
- `opensis-db`
- ingress
- Vault-backed secret delivery

Everything else should be treated as a separate platform concern or a later phase.

## Goals

The day-1 production layer should:

- serve openSIS over HTTPS
- keep MariaDB private and stateful
- source secrets from Vault
- avoid Docker-era AppRole handoff patterns
- be simple enough to debug during the first production rollout
- establish clean foundations for later observability and scale work

## Scope

Included on day 1:

- `opensis-ui` as a `Deployment`
- `opensis-db` as a `StatefulSet`
- a Kubernetes `Ingress` for the application
- Kubernetes `ServiceAccount` identities for app and DB
- Vault Agent Injector annotations for secret delivery
- persistent storage for MariaDB
- health probes
- resource requests and limits

Not included on day 1:

- self-hosted Vault in the same application layer
- Grafana, Prometheus, Loki, or Alertmanager in the critical path
- standalone exporter migration
- Cloudflare tunnel migration
- HA database design
- multi-region or DR topology

## Architecture

The production request path is:

1. user traffic enters through the cluster ingress controller
2. TLS is terminated at ingress
3. ingress routes traffic to the `opensis-ui` service
4. the `opensis-ui` pod reads runtime secrets from `/run/secrets/app.env`
5. the app connects to the internal `opensis-db` service
6. the `opensis-db` pod reads runtime secrets from `/run/secrets/db.env`
7. MariaDB stores data on persistent volumes

The secret path is:

1. each workload uses its own Kubernetes `ServiceAccount`
2. Vault Kubernetes auth maps that identity to a Vault role
3. Vault Agent Injector renders the required secret file into the pod
4. the container starts using the injected file

## Design Decisions

### 1. Vault Is A Platform Dependency

Vault should not be part of this first application layer.

Reasoning:

- it reduces blast radius during migration
- it avoids coupling app rollout with Vault lifecycle
- it matches how production platforms are usually managed
- it keeps the first production layer focused on serving the application

Day-1 assumption:

- Vault already exists
- Vault Agent Injector is installed in the cluster
- Vault Kubernetes auth is enabled

### 2. MariaDB Is Stateful And Private

`opensis-db` should be deployed as a `StatefulSet` with `volumeClaimTemplates`.

Reasoning:

- MariaDB needs durable storage and stable identity
- storage should be owned by the workload, not manually stitched together
- the database should only be reachable inside the cluster

Operational expectations:

- one replica on day 1
- backup job exists before go-live
- restore procedure is tested before go-live

### 3. openSIS UI Is Stateless

`opensis-ui` should be deployed as a `Deployment`.

Reasoning:

- application pods should be replaceable
- ingress and scaling belong at the deployment layer
- secret injection should not require custom secret sidecars in the manifest

Operational expectations:

- at least one replica on day 1
- probes tuned to actual startup behavior
- rollout strategy should prefer low-risk updates

### 4. Secret Delivery Uses Kubernetes Auth

The app and DB should authenticate to Vault using Kubernetes auth and their service accounts.

Reasoning:

- this is the Kubernetes-native replacement for the Compose AppRole handoff
- it removes the need to transport `role_id` and `secret_id`
- it aligns with least privilege and workload identity

Expected Vault roles:

- `opensis-app`
- `opensis-db`

Expected paths:

- `kv/data/production/opensis-app`
- `kv/data/production/opensis-db`

### 5. Ingress Terminates TLS

The application should be published through a standard ingress controller with TLS.

Reasoning:

- avoids direct node exposure
- centralizes hostname and certificate handling
- keeps the application service internal to the cluster

Day-1 preference:

- cert-manager for certificate automation
- a dedicated hostname for openSIS
- ingress class and issuer handled in overlays

## Kubernetes Objects

The first production layer needs:

- `Namespace`
- `ServiceAccount` for `opensis-ui`
- `ServiceAccount` for `opensis-db`
- `ConfigMap` for `opensis-ui`
- `ConfigMap` for `opensis-db`
- `Deployment` for `opensis-ui`
- `Service` for `opensis-ui`
- `Ingress` for `opensis-ui`
- `StatefulSet` for `opensis-db`
- `Service` for `opensis-db`
- `volumeClaimTemplates` inside the MariaDB `StatefulSet`

## Security Baseline

Minimum day-1 security expectations:

- no plaintext production secrets in repo files
- no `.env`-driven production secret flow
- one service account per workload
- internal-only database access
- TLS at ingress
- Vault roles scoped only to the secrets each workload needs
- image tags pinned before production rollout

Should be added in the next phase:

- `NetworkPolicy`
- stricter `securityContext`
- non-root execution where compatible
- read-only root filesystem where compatible

## Storage And Data Protection

MariaDB storage should use a known production storage class.

Before production:

- choose the storage class intentionally
- define requested size and growth expectations
- document retention expectations
- validate that PVC reclaim behavior matches your operational model

Backups are mandatory on day 1.

Minimum backup requirements:

- scheduled database dump or volume-aware backup
- off-cluster backup target
- documented restore procedure
- at least one successful restore test

## Networking Model

Day-1 network posture:

- `opensis-ui` is reachable through ingress only
- `opensis-db` is reachable only inside the namespace or approved internal policies
- Vault is not exposed through this application layer

This should evolve into explicit `NetworkPolicy` objects as the next security step.

## Operational Readiness Checklist

Before the first production rollout:

- Vault Injector is installed and healthy
- Vault Kubernetes auth is configured
- `opensis-app` and `opensis-db` roles exist
- production secrets exist at the expected paths
- MariaDB backups are configured
- restore testing has been completed
- app and DB images are pinned
- ingress TLS is ready
- DNS points to the ingress entrypoint
- rollback procedure is written down

## What Comes Next

After the day-1 production layer is stable, the next steps should be:

1. add `prod` and `dev` overlays
2. add `NetworkPolicy`
3. add stronger pod security settings
4. add observability as a separate layer
5. add alert routing and runbooks
6. review scaling and HA options

## Repo Mapping

This architecture maps directly to the current base manifests:

- [k8s/base/opensis-ui/deployment.yaml](base/opensis-ui/deployment.yaml)
- [k8s/base/opensis-ui/service.yaml](base/opensis-ui/service.yaml)
- [k8s/base/opensis-ui/ingress.yaml](base/opensis-ui/ingress.yaml)
- [k8s/base/opensis-db/statefulset.yaml](base/opensis-db/statefulset.yaml)
- [k8s/base/opensis-db/service.yaml](base/opensis-db/service.yaml)
- [k8s/base/kustomization.yaml](base/kustomization.yaml)

This base is the starting point, not the finished production platform.
