# OpenSIS Platform Deployment Guide

This repository packages `openSIS Classic` into a practical, production-minded deployment stack.

It includes:

- a simple local Docker Compose path for learning and development
- a Kubernetes path with Vault-backed secret delivery
- Argo CD GitOps workflows for `dev` and `prod`
- backup, restore, observability, and operator runbooks

The goal of this repo is not just to run the app once. The goal is to show a complete journey from local setup to a maintainable deployment model that can be explained, repeated, and improved over time.

## CI/CD Workflow Model

This repository now uses a four-lane delivery model:

- `validate.yml`
  Repository validation for workflows, shell scripts, YAML, and Kubernetes render checks.
- `publish-dockerhub-image.yml`
  Docker Hub image publishing with immutable `git-<sha>` tagging, SBOM generation, Trivy reporting, and Cosign signing.
- `smoke-dev-public.yml`
  Scheduled and on-demand verification of the active public `dev` edge.
- `promote-prod.yml`
  Manual GitOps promotion for the dormant `prod` contract, kept available but not treated as the active operating lane.

For the current `dev`-first posture, `dev` follows `main` plus the mutable `dev` image alias. That is why there is no separate manual `promote-dev` workflow today. Manual promotion remains the right boundary for the held `prod` path.

This separation keeps validation, artifact publishing, active `dev` verification, and dormant `prod` promotion independent. That makes the pipeline easier to audit, easier to reason about, and safer to operate.

## Who This Is For

This repository is written for:

- Beginners who want a clear step-by-step path
- Engineers learning Vault, Argo CD, and Kubernetes operations
- Teammates who want to understand the design quickly
- Operators who need a working runbook, not just manifests

## What You Can Build With This Repo

### Local Stack

The local stack uses Docker Compose and brings up:

- Vault
- Vault bootstrap and seed jobs
- Vault agents for app and database secrets
- MariaDB
- openSIS UI

Optional local edge components are also available:

- Traefik
- Cloudflare Tunnel

### Kubernetes Stack

The active owned Kubernetes path now uses:

- Kustomize overlays
- Vault-first secret delivery
- Argo CD
- Traefik-aligned ingress direction
- shared observability integration through the workspace control plane
- backup and restore workflows

## Start Here

Choose one path:

1. Local Docker Compose:
   Read [Local Compose Guide](docs/02-local-compose-guide.md)
2. Kubernetes bootstrap:
   Read [Kubernetes Bootstrap Guide](docs/03-kubernetes-bootstrap-guide.md)

If you are brand new, read these first:

- [Prerequisites](docs/01-prerequisites.md)
- [Architecture Reference](docs/06-architecture-reference.md)

## Recommended Reading Order

1. [Prerequisites](docs/01-prerequisites.md)
2. [Local Compose Guide](docs/02-local-compose-guide.md)
3. [Kubernetes Bootstrap Guide](docs/03-kubernetes-bootstrap-guide.md)
4. [Operations Runbook](docs/04-operations-runbook.md)
5. [Troubleshooting Guide](docs/05-troubleshooting-guide.md)
6. [Architecture Reference](docs/06-architecture-reference.md)

## Documentation Map

- [docs/01-prerequisites.md](docs/01-prerequisites.md)
  Environment, tools, and account requirements.
- [docs/02-local-compose-guide.md](docs/02-local-compose-guide.md)
  Beginner-friendly local setup using Docker Compose.
- [docs/03-kubernetes-bootstrap-guide.md](docs/03-kubernetes-bootstrap-guide.md)
  End-to-end Kubernetes deployment flow.
- [docs/04-operations-runbook.md](docs/04-operations-runbook.md)
  Daily operational commands and maintenance flows.
- [docs/05-troubleshooting-guide.md](docs/05-troubleshooting-guide.md)
  Common failures and practical fixes.
- [docs/06-architecture-reference.md](docs/06-architecture-reference.md)
  End-to-end architecture, traffic flow, secrets flow, and design decisions.

## Kubernetes Paths

The repo now has two Kubernetes paths:

- active owned path:
  - [OpenSIS Owned Kubernetes Path](k8s/README.md)
- archived legacy reference path:
  - [Legacy Kubernetes Base](k8s-legacy-platform/README.md)
  - [From-Scratch Local Bootstrap](k8s-legacy-platform/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)
  - [Production-Grade CI/CD Blueprint](k8s-legacy-platform/PRODUCTION_GRADE_CICD_BLUEPRINT.md)

## Existing Deep-Dive Guides

These longer repo-specific guides remain useful for advanced work:

- [Troubleshooting](TROUBLESHOOTING.md)
- [Security Notes](SECURITY_NOTES.md)
- [Tests And Verification](tests/README.md)

## Quick Local Start

Clone the repository and move into the project directory:

```bash
git clone https://github.com/eseosaiyangbe/OpenSIS.git
cd OpenSIS
```

Then run the local stack:

```bash
./scripts/precheck.sh
./scripts/compose-start.sh
./scripts/docker-storage-check.sh
```

The default local path now builds `opensis-ui` locally, which makes the repo portable across:

- macOS Intel
- macOS Apple Silicon
- Linux AMD64
- Linux ARM64

This is also why plain `docker compose up -d` now works consistently across those host architectures.

Open:

- app: `http://localhost:8088`
- Vault: `http://localhost:8200`

To bring the stack down:

```bash
docker compose down
or
./scripts/compose-stop.sh
```

If you want the raw Docker Compose equivalent of the default portable start:

```bash
docker compose up -d --build
```

`./scripts/docker-storage-check.sh` gives a quick operator view of Docker storage usage, current OpenSIS container logging policy, and the largest visible Docker `json-file` logs. Run it before demos or during disk-pressure incidents.

If you are on a compatible platform and explicitly want to force the published image path:

```bash
./scripts/compose-start.sh --pull-image
or
docker compose -f docker-compose.yaml -f docker-compose.pullimage.yaml up -d
```

## High-Level Architecture

### Local

```text
Browser -> openSIS UI -> MariaDB
             |
             -> Vault Agent rendered secrets
Vault Bootstrap -> Vault -> AppRole data -> Vault Agents
```

### Kubernetes

```text
Browser -> Cloudflare -> cloudflared -> ingress -> openSIS UI -> MariaDB
                                         |              |
                                         |              -> backup jobs
                                         |
                                         -> Vault Agent Injector rendered secrets

Argo CD -> Kustomize overlays -> live cluster
Prometheus -> exporters -> Alertmanager / Grafana
```

## Repository Highlights

- [docker-compose.yaml](docker-compose.yaml)
  Main local stack definition.
- [docker-compose.buildlocal.yaml](docker-compose.buildlocal.yaml)
  Legacy local UI build override retained for compatibility.
- [docker-compose.pullimage.yaml](docker-compose.pullimage.yaml)
  Optional override that replaces the local UI build with the published dev image.
- [scripts/precheck.sh](scripts/precheck.sh)
  Local environment readiness check.
- [scripts/k8s-start.sh](scripts/k8s-start.sh)
  Start or resume the repo-local OpenSIS Kubernetes dev slice.
- [scripts/k8s-stop.sh](scripts/k8s-stop.sh)
  Stop the repo-local OpenSIS Kubernetes dev slice without deleting state.
- [scripts/k8s-reset.sh](scripts/k8s-reset.sh)
  Destructively reset the repo-local OpenSIS Kubernetes dev slice for a clean reinstall.
- [scripts/smoke-dev.sh](scripts/smoke-dev.sh)
  Dev verification helper.
- [scripts/smoke-prod.sh](scripts/smoke-prod.sh)
  Prod verification helper.
- [tests/k8s/README.md](tests/k8s/README.md)
  Backup, restore, and Vault verification helpers.

## OpenSIS Kubernetes Lifecycle

Use these three commands deliberately. They are not interchangeable.

- `./scripts/k8s-start.sh`
  Safe start or resume for `opensis-dev`. If the namespace already exists, it scales the preserved workloads back up. If the namespace does not exist, it runs the full deploy path.
- `./scripts/k8s-stop.sh`
  Safe stop for `opensis-dev`. It scales the deployments and statefulset down to `0` and preserves the namespace, PVC, schema, and accounts.
- `./scripts/k8s-reset.sh`
  Destructive reset for `opensis-dev`. It deletes the namespace and PVC so the next `k8s-start.sh` run comes back as a fresh install.

Normal daily lifecycle:

```bash
cd /Users/raymond/Documents/devops-easy-learning/opensis
./scripts/k8s-start.sh
./scripts/k8s-stop.sh
```

State-preserving stop with wait:

```bash
cd /Users/raymond/Documents/devops-easy-learning/opensis
./scripts/k8s-stop.sh --wait
```

Destructive reset and reinstall path:

```bash
cd /Users/raymond/Documents/devops-easy-learning/opensis
./scripts/k8s-reset.sh --wait
./scripts/k8s-start.sh
```

After a destructive reset, complete the installer at:

- [https://opensis.eseosadevbox.com/install/index.php](https://opensis.eseosadevbox.com/install/index.php)

Installer values used by the current dev environment:

- MySQL server: `opensis-db`
- Port: `3306`
- MySQL username: `root`
- MySQL password: `opensis-root-123`
- Database name: `opensis`
- Admin username: `admin`
- Admin password: `Raymond@123`

After reinstall, verify:

```bash
kubectl -n opensis-dev get pods
kubectl -n opensis-dev exec deploy/opensis-ui -- sh -c 'ls -l /var/www/openSIS/Data.php'
kubectl -n opensis-dev exec statefulset/opensis-db -- sh -c 'mysql -N -uroot -popensis-root-123 -D opensis -e "SELECT username, profile_id FROM login_authentication WHERE username=\"admin\";"'
```

## Professional Notes

This repository is designed as a learning and portfolio project, but the operational model is intentionally serious:

- secrets come from Vault
- Kubernetes changes are driven through GitOps
- backups are tested, not just assumed
- observability is part of the platform
- drift, outages, and recovery steps are documented

That means the repo is suitable for:

- demonstration
- learning
- interviews
- iterative improvement toward stronger production maturity

## License

openSIS itself is an open source project. Review the upstream license and any image or dependency licenses before commercial use.
