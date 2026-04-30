# 03: Kubernetes Bootstrap Guide

This guide explains the older end-to-end Kubernetes bootstrap path from a clean cluster to a working `dev` and `prod` deployment model.

It is now preserved as legacy reference material.

The active owned Kubernetes path for the shared DevOps Easy Learning workspace now starts at:

- [../k8s/README.md](../k8s/README.md)

It is written as the simpler public-facing version of the deeper operator notebook in [FROM_SCRATCH_LOCAL_BOOTSTRAP.md](../k8s-legacy-platform/FROM_SCRATCH_LOCAL_BOOTSTRAP.md).

This path is production-minded, but still practical for a single-node lab cluster.

## What This Path Includes

- `k3s` as the Kubernetes runtime
- `ingress-nginx` as the explicit ingress controller
- Vault for secret management
- Vault Agent Injector for runtime secret rendering
- Argo CD for GitOps
- `opensis-dev` and `opensis` environments
- observability with Prometheus, Alertmanager, Grafana, blackbox-exporter, and mysqld-exporter
- backup and restore helpers
- Cloudflare-facing production routing

## Before You Start

Make sure you already completed:

- [01-prerequisites.md](01-prerequisites.md)
- [02-local-compose-guide.md](02-local-compose-guide.md) if you want the easiest first learning step

If you are on macOS, this Kubernetes guide still works, but your cluster will usually be remote or running on another Linux machine. In that case, make sure `kubectl get nodes` works before you continue.

## Recommended Order

Do not try to do everything at once.

Use this order:

1. build the cluster
2. install ingress
3. install Argo CD
4. install Vault
5. initialize and unseal Vault
6. enable Kubernetes auth and seed secrets
7. validate secret injection
8. deploy `dev`
9. validate backup and restore
10. deploy `prod`
11. validate observability and public edge routing

## 1. Build The Cluster

For a local learning lab, `k3s` is a strong fit.

The validated bootstrap path in this repo uses:

- single-node `k3s`
- a default `StorageClass`
- bundled Traefik disabled
- ingress installed intentionally afterward

Create the `k3s` config directory:

```bash
sudo mkdir -p /etc/rancher/k3s
```

Copy the repo starter config into place:

```bash
sudo cp k8s/bootstrap/k3s/config.yaml /etc/rancher/k3s/config.yaml
```

Install `k3s`:

```bash
curl -sfL https://get.k3s.io | sh -
```

Point your shell at the kubeconfig:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

If you want K9s and other tools to work cleanly, create a standard kubeconfig too:

```bash
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

Optional cleanup for a friendlier context name:

```bash
kubectl config rename-context default k3s-devbox
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

You want:

- the node in `Ready`
- core system pods healthy
- no bundled Traefik pods, because ingress will be managed explicitly

## 2. Install Ingress Intentionally

Because bundled Traefik is disabled, install an ingress controller on purpose.

For this repo’s validated learning path, use `ingress-nginx`.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx
```

Verify:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

## 3. Install Argo CD

Install Argo CD into its own namespace:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Verify:

```bash
kubectl get pods -n argocd
```

If tools like K9s show `n/a`, confirm that your kubeconfig is present and usable:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl get nodes
```

## 4. Install Vault

Vault is the source of truth for secrets in this repo.

At a minimum you need:

- Vault server
- Vault Agent Injector
- Kubernetes auth enabled
- policies
- roles
- seeded secrets for app and DB

Create the namespace:

```bash
kubectl create namespace vault
```

Add the HashiCorp Helm repo:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Install Vault with the repo values:

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --version 0.32.0 \
  -f k8s/bootstrap/vault-values.yaml
```

Verify:

```bash
kubectl get pods -n vault
kubectl get svc -n vault
```

You want:

- `vault-0` running
- `vault-agent-injector` running

## 5. Initialize, Unseal, And Log In To Vault

Exec into the Vault pod:

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Initialize:

```bash
vault operator init
```

Save the output carefully. It contains:

- unseal keys
- root token

Do not commit these values to Git.

Unseal Vault:

```bash
vault operator unseal
```

Repeat with the required threshold of keys.

Log in:

```bash
vault login
```

If `vault login` returns `Vault is sealed`, finish the unseal flow first.

## 6. Enable Kubernetes Auth And Seed Secrets

Still inside the Vault pod shell:

```bash
vault secrets enable -path=kv kv-v2
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
```

You then need:

- policies for app and DB access
- roles bound to the right Kubernetes service accounts
- seeded secrets for both `dev` and `prod`

Expected secret groups in this repo include:

- `kv/dev/opensis-app`
- `kv/dev/opensis-db`
- `kv/production/opensis-app`
- `kv/production/opensis-db`

Use the repo bootstrap helpers and policy files where available instead of retyping everything by hand.

## 7. Add Vault TLS And Injector Trust

This is one of the most important practical lessons from the validated run.

Vault TLS is not optional in the proven path anymore. When you enable Vault TLS, workloads that use Vault Agent injection also need:

- a namespace-local `vault-agent-ca` secret
- `vault.hashicorp.com/tls-secret`
- `vault.hashicorp.com/ca-cert`

Without that trust chain, injected workloads can hang in init with certificate verification errors.

If you want the detailed step-by-step path, use:

- [FROM_SCRATCH_LOCAL_BOOTSTRAP.md](../k8s/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)

## 8. Deploy The Base And Overlays

Base manifests live under:

- [k8s/base](../k8s/base)

Overlays live under:

- [k8s-legacy-platform/overlays](../k8s-legacy-platform/overlays)

Argo applications to expect:

- `opensis-dev`
- `opensis-prod`
- `opensis-cloudflare`

## 9. Validate Secret Injection Before The App Layer

Before you trust the app rollout, make sure the Vault model is working.

Look for:

- injected pods finishing init
- rendered secret files in `/run/secrets`
- no `x509: certificate signed by unknown authority` errors in injector-connected workloads

This step saves a lot of time later.

## 10. Validate Dev First

Always validate `dev` before `prod`.

Useful checks:

```bash
kubectl get applications -n argocd
kubectl get pods -n opensis-dev
./scripts/smoke-dev.sh
```

You want:

- `opensis-dev` synced
- `opensis-dev` healthy
- the smoke script passing

This repo also validated an important app-side lesson: browser-only request assumptions caused failures behind probes and proxies. The app and edge path are now more tolerant, but `dev` should still be your first checkpoint before promoting anything.

## 11. Validate Backup And Restore

Do not treat backup and restore as optional.

Important helper scripts:

- [backup-run.sh](../tests/k8s/backup-run.sh)
- [backup-inspect.sh](../tests/k8s/backup-inspect.sh)
- [restore-reset.sh](../tests/k8s/restore-reset.sh)
- [restore-run.sh](../tests/k8s/restore-run.sh)
- [restore-verify.sh](../tests/k8s/restore-verify.sh)

This matters because backup jobs are part of the platform itself. In this repo’s real run, failed backup Jobs were enough to make Argo show `Degraded` even while the public site still served `200`.

## 12. Promote To Prod

Useful checks:

```bash
kubectl get applications -n argocd
kubectl get pods -n opensis
./scripts/smoke-prod.sh
curl -I https://opensis.raysosglobal.com
```

You want:

- `opensis-prod` synced
- `opensis-prod` healthy
- the public URL returning `200`

## 13. Know The Practical Lessons Already Captured In This Repo

This repo has already validated a few production lessons worth knowing before you hit them yourself:

- failed backup Jobs can make Argo show `Degraded`
- Vault trust changes can temporarily move apps through `OutOfSync` and `Progressing`
- database user drift can break both backup jobs and app startup
- blackbox probes need explicit network policy egress for public `443`
- single-node clusters can require extra care with anti-affinity and rolling updates

Those are documented in:

- [FROM_SCRATCH_LOCAL_BOOTSTRAP.md](../k8s/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)
- [PRODUCTION_GRADE_CICD_BLUEPRINT.md](../k8s/PRODUCTION_GRADE_CICD_BLUEPRINT.md)

## 14. Use The Long-Form Guides For Full Detail

For full operator detail, use:

- [k8s/README.md](../k8s/README.md)
- [k8s-legacy-platform/README.md](../k8s-legacy-platform/README.md)
- [FROM_SCRATCH_LOCAL_BOOTSTRAP.md](../k8s/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)
- [PRODUCTION_GRADE_CICD_BLUEPRINT.md](../k8s/PRODUCTION_GRADE_CICD_BLUEPRINT.md)

## 15. Next Step

Once the cluster is up, move to:

- [04-operations-runbook.md](04-operations-runbook.md)
