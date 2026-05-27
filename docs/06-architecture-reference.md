# 06: Architecture Reference

This guide explains how the whole project fits together.

Use it when you want the big picture, not just the next command.

This document is especially useful for:

- future teammates
- interview reviewers
- operators learning the system
- anyone trying to understand why the repo is structured the way it is

## 1. Main Design Goal

This project turns openSIS into a repeatable deployment platform instead of a one-off app install.

The design aims for:

- repeatable local setup
- Vault-managed secrets
- Kubernetes workloads
- GitOps reconciliation
- observability
- backup and restore workflows

The key idea is that the app should not live alone. It should live inside a platform model that can be explained, operated, and improved over time.

## 2. Main Runtime Modes

The repo supports two main runtime modes.

### Local mode

Local mode uses Docker Compose.

Main idea:

- bootstrap Vault locally
- seed secrets into Vault
- let Vault agents render runtime files
- start MariaDB and openSIS using those files

Why this mode exists:

- easier first-day learning
- faster local iteration
- simpler debugging before Kubernetes

### Cluster mode

Cluster mode uses Kubernetes plus Argo CD.

Main idea:

- Git stores the desired state
- Argo CD reconciles the cluster to that state
- Vault injects secrets into workloads
- observability tools monitor the running system

Why this mode exists:

- closer to real production operations
- better environment separation
- safer promotion and drift detection

## 3. Core Building Blocks

At a high level, the platform is made of:

- openSIS UI
- MariaDB
- Vault
- Argo CD
- ingress and edge routing
- observability
- backup and restore workflows

Each one solves a different problem:

- openSIS provides the application
- MariaDB stores the application data
- Vault provides secret delivery
- Argo CD provides deployment control
- ingress and edge routing expose the application safely
- observability helps you understand failures
- backup and restore protect the data layer

## 4. Secret Flow

Secrets are one of the most important architectural choices in this repo.

The project avoids storing long-lived application credentials directly in Git-managed Kubernetes Secrets when Vault delivery is available.

### Local secret flow

```text
.env -> Vault seed job -> Vault
Vault -> Vault Agent -> /run/secrets/*.env
/run/secrets/*.env -> MariaDB and openSIS
```

### Kubernetes secret flow

```text
Vault KV -> External Secrets -> Kubernetes Secret
Kubernetes Secret -> mounted secret file -> pod entrypoint -> runtime config
```

Important ideas:

- Vault is the source of truth
- External Secrets materializes environment-specific Kubernetes Secrets from Vault paths
- workloads read mounted secret files at runtime
- the repo keeps the secret-delivery pattern consistent across environments

## 5. Database Flow

The database is MariaDB.

In Kubernetes it runs as a `StatefulSet`, because the database needs stable storage and stable identity.

The database layer also supports:

- scheduled backup via `CronJob`
- manual backup verification
- restore testing
- exporter-based observability

The current OpenSIS `dev` data-protection path is now explicitly platformized:

- `CronJob/opensis-db-backup` runs daily at `02:00 UTC`
- backup retention keeps the newest `7` archives
- backup and restore helpers operate against the same `opensis-db-secrets` contract used by the live database workload
- restore drills are performed with temporary GitOps automation suspension and then reconciled back under Argo CD control

One important lesson already validated in this repo:

- if Vault and rendered DB files match, but auth still fails, the drift may be inside MariaDB itself rather than in Vault

That is an architectural insight as much as an operational one. Secret delivery and live database state are related, but they are not the same thing.

## 6. UI Flow

The UI is openSIS running in Apache and PHP.

At runtime it depends on:

- database connectivity
- rendered app secrets
- session storage configuration
- stable request handling through the chosen edge path

In Kubernetes, session handling matters a lot because multiple UI pods may run at the same time. That is why session storage is treated as part of the platform design, not as a minor PHP detail.

## 7. Traffic Flow

Traffic looks different in local mode and cluster mode.

### Local

```text
Browser -> localhost:8088 -> openSIS UI -> MariaDB
```

This path is intentionally simple. It reduces moving parts so you can focus on app, DB, and secret flow first.

### Production-style cluster flow

```text
Browser -> Cloudflare -> cloudflared -> ingress -> openSIS UI -> MariaDB
```

Why this matters:

- Cloudflare provides the public edge
- ingress controls in-cluster HTTP entry
- openSIS remains a private workload behind that edge model

This repo also captured a real lesson here:

- app behavior can be affected by edge assumptions, forwarded headers, and request shape

That is why the repo includes both architecture notes and troubleshooting notes around the origin path.

## 8. GitOps Flow

GitOps is the control plane for the Kubernetes path.

```text
Git commit -> GitHub -> Argo CD detects drift -> cluster reconciles -> smoke checks verify result
```

Important principle:

- production recovery should not depend on random live mutation if Git can be the source of correction

That does not mean live fixes never happen. It means:

- live fixes are for stabilization during incidents
- permanent fixes should be pushed back into Git afterward

This repo has already followed that pattern several times, especially after trust fixes, network policy fixes, and database-entrypoint fixes.

## 9. Observability Flow

Observability is part of the architecture, not just an extra dashboard.

Prometheus scrapes:

- blackbox-exporter
- mysqld-exporter
- node-exporter
- kube-state-metrics
- Prometheus itself

Alertmanager handles alert routing.

Grafana visualizes the system.

Why this matters:

- you can detect user-facing failure
- you can detect internal failure even when the public site still works
- you can compare cluster health against app health

One important example from this repo:

- a blackbox alert can fail because probe traffic is blocked, even when the site itself is healthy

That is why observability must be interpreted, not just watched.

## 10. Why Vault Matters Here

Vault improves:

- secret centralization
- environment separation
- pod-level secret delivery
- auditability of secret paths
- recovery clarity when credentials drift

This repo also demonstrates a valuable real-world lesson:

- if Vault and rendered files agree, but auth still fails, the live application or database state may have drifted away from Vault

That makes Vault useful not only for delivery, but also for diagnosis.

## 11. Why Argo CD Matters Here

Argo CD gives:

- a visible desired state
- drift detection
- safer promotions
- a useful health model

It also creates an important operator responsibility:

- learn to interpret `OutOfSync`, `Progressing`, and `Degraded` correctly

In this repo, those states have sometimes represented:

- expected convergence after a sync
- temporary rollout behavior during trust changes
- real platform issues such as failed backup Jobs
- temporary `OutOfSync` during restore-drill suspension or manual validation Jobs until the runtime cleanup and GitOps refresh are completed

So Argo status is important, but it must always be read with runtime context.

## 12. Why Backup And Restore Are Architectural, Not Optional

Backup and restore are not side features in this repo.

They are part of the platform contract.

Why:

- the database is the critical stateful layer
- recovery confidence matters as much as backup existence
- backup failures can affect platform health signals

That is why this repo includes:

- backup scripts
- restore scripts
- inspection helpers
- operational guidance for diagnosing failed backup Jobs

## 13. Why The Local And Cluster Paths Both Matter

The local Compose path is not a toy.

It teaches:

- the secret model
- the app and DB dependency chain
- the basic startup and health flow

The Kubernetes path then adds:

- GitOps
- cluster scheduling
- Vault injector behavior
- ingress and edge routing
- observability
- platform recovery patterns

Together, they create a learning path that is easier to explain and easier to maintain than jumping straight into production-style Kubernetes on day one.

## 14. Key Production Lessons Already Built Into This Repo

This repo has already validated several lessons that are now part of the design story:

- backup failures can degrade Argo even when the site still serves traffic
- blackbox probes need real egress to the public target they monitor
- database and app credentials must stay aligned across Vault and the live database
- Vault trust changes must be propagated to injected workloads
- edge behavior matters when the app is sensitive to request shape or headers

These are not hypothetical lessons. They came from real incidents already handled during this project.

## 15. Recommended Mental Model

A good way to think about the system is in five layers:

1. application
2. data
3. secrets
4. delivery
5. operations

In this repo, those layers are:

1. openSIS
2. MariaDB and backups
3. Vault
4. Docker Compose or Kubernetes plus Argo CD
5. smoke checks, observability, alerts, and recovery runbooks

This mental model makes it easier to debug:

- if the site fails, ask which layer is actually failing
- if Argo is unhealthy, ask whether the runtime is also unhealthy
- if auth fails, ask whether Vault, rendered secrets, or live DB state is the real source

## 16. Where To Go Next

- practical steps: [04-operations-runbook.md](04-operations-runbook.md)
- problem solving: [05-troubleshooting-guide.md](05-troubleshooting-guide.md)
