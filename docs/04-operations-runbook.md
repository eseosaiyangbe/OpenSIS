# 04: Operations Runbook

This guide is for day-2 work.

Use it after the platform is already running.

This guide applies to both Linux and macOS terminals.

If you are on macOS:

- make sure Docker Desktop is running before using Compose commands
- make sure your kubeconfig is available before using Kubernetes commands

## 1. What This Runbook Covers

Use this guide when you need to:

- confirm the stack is healthy
- restart a component safely
- understand whether Argo drift is expected or dangerous
- run a backup or restore
- check Vault health
- respond to alerts
- verify whether `dev` and `prod` are actually healthy

For symptom-by-symptom debugging, use [05-troubleshooting-guide.md](05-troubleshooting-guide.md).

## 2. Core Health Checks

### Docker Compose

```bash
docker compose ps
docker compose logs --tail=50 opensis-ui opensis-db vault
```

If Docker commands fail on macOS, open Docker Desktop first and wait for it to finish starting.

### Kubernetes

```bash
kubectl get applications -n argocd
kubectl get pods -n opensis-dev
kubectl get pods -n opensis
./scripts/k8s-start.sh --help
./scripts/k8s-stop.sh --help
./scripts/smoke-dev.sh
./scripts/smoke-prod.sh
```

### Quick public-prod check

```bash
curl -I https://opensis.raysosglobal.com
```

Healthy steady state usually looks like:

- Argo apps are `Synced` and `Healthy`
- `dev` and `prod` smoke checks pass
- the public prod URL returns `200`
- Vault is unsealed and healthy

## 3. Safe Daily Checks

These are good “start here” commands before you change anything:

```bash
kubectl get applications -n argocd
kubectl get pods -n opensis
kubectl get pods -n opensis-dev
kubectl get jobs -n opensis --sort-by=.metadata.creationTimestamp
kubectl get jobs -n opensis-dev --sort-by=.metadata.creationTimestamp
curl -I https://opensis.raysosglobal.com
```

If your terminal cannot see the cluster, fix kubeconfig first:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl get nodes
```

If you use `k3s`, remember that some tools expect `~/.kube/config` to exist even when `kubectl` itself already works.

## 4. Safe Restart Patterns

Restart the smallest thing that solves the problem.

### Start the local k3s cluster

For the local single-node `k3s` lab cluster, use:

```bash
./scripts/k8s-start.sh
```

This script:

- starts the `k3s` service
- waits for the Kubernetes API
- waits for `node/devbox` to become `Ready`
- optionally cleans stale pods stuck in `Unknown`
- prints node, Argo CD, and non-running pod status

After a machine reboot or k3s restart, Vault may come back sealed. To start k3s and unseal Vault in one pass:

```bash
./scripts/k8s-start.sh --unseal-vault
```

For the strongest local verification, include smoke checks:

```bash
./scripts/k8s-start.sh --unseal-vault --smoke
```

Use this when you want to confirm:

- Vault is unsealed
- Argo CD apps are healthy
- dev responds through `https://opensis.dev.local`
- prod responds through `https://opensis.raysosglobal.com`

### Stop the local k3s cluster

To stop the local `k3s` cluster:

```bash
./scripts/k8s-stop.sh
```

This script:

- stops the `k3s` service
- confirms the service state
- confirms the Kubernetes API is no longer reachable

Expected output includes:

```text
k3s service state:
inactive

Kubernetes API is not reachable, as expected after stopping k3s.
```

If your terminal asks for a `sudo` password, that is normal on machines where stopping system services requires elevated permissions.

### Important Vault note after restart

Vault uses Shamir unseal in this lab. That means a k3s restart can leave Vault running but sealed.

Symptoms:

- `vault-0` is `Running` but not `Ready`
- Vault Agent init containers are stuck
- pod logs mention `Vault is sealed`
- Argo CD may temporarily show apps as `Progressing`, `Unknown`, or `Degraded`

The normal recovery command is:

```bash
./scripts/k8s-start.sh --unseal-vault
```

The script reads the local lab unseal keys from `vault/init/init.txt` and does not print the key values.

Do not commit real production unseal keys or root tokens to a public repository.

### Restart only the prod UI

```bash
kubectl rollout restart deployment/opensis-ui -n opensis
kubectl rollout status deployment/opensis-ui -n opensis
curl -I https://opensis.raysosglobal.com
```

### Restart only the dev UI

```bash
kubectl rollout restart deployment/opensis-ui -n opensis-dev
kubectl rollout status deployment/opensis-ui -n opensis-dev
```

### Restart Argo controller when app health looks stuck

```bash
kubectl rollout restart statefulset/argocd-application-controller -n argocd
kubectl rollout status statefulset/argocd-application-controller -n argocd
kubectl get applications -n argocd
```

### Refresh Argo app state

```bash
kubectl annotate application opensis-prod -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## 5. Backup Operations

Backups are part of the platform, not an optional afterthought.

Run a one-off backup:

```bash
./tests/k8s/backup-run.sh
```

Inspect stored backups:

```bash
./tests/k8s/backup-inspect.sh
```

Delete old backup files:

```bash
./tests/k8s/backup-delete.sh
```

Important lesson from this repo’s real operation:

- a failed backup Job can make Argo show `Degraded` even while the site still returns `200`

So always check recent Jobs when Argo health looks worse than the user-facing system.

## 6. Restore Operations

Use restores deliberately and in order.

Reset the target DB first:

```bash
./tests/k8s/restore-reset.sh
```

Run the restore:

```bash
./tests/k8s/restore-run.sh
```

Verify the restore:

```bash
./tests/k8s/restore-verify.sh
```

Do not treat a restore as complete until verification passes.

## 7. Vault Operations

Check Vault status:

```bash
kubectl exec -n vault vault-0 -- sh -lc 'export VAULT_ADDR=https://vault.vault.svc:8200 VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault status'
```

Check Vault pods:

```bash
kubectl get pods -n vault
kubectl logs -n vault vault-0 --tail=100
kubectl logs -n vault deploy/vault-agent-injector --tail=100
```

If Vault restarts sealed, you must unseal it again using your unseal keys.

If injected workloads are stuck in init, check for TLS trust failures such as:

- `x509: certificate signed by unknown authority`

That usually means the workload is missing:

- namespace-local `vault-agent-ca` secret
- `vault.hashicorp.com/tls-secret`
- `vault.hashicorp.com/ca-cert`

## 8. Image Promotion And Verification

For production validation:

```bash
./scripts/smoke-prod.sh
kubectl get deployment opensis-ui -n opensis -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

For development validation:

```bash
./scripts/smoke-dev.sh
kubectl get deployment opensis-ui -n opensis-dev -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

The main idea is simple:

- validate `dev` first
- confirm the image reference
- then verify `prod`

## 9. When Argo Shows OutOfSync

First ask:

- was there a recent Git push
- was there a recent sync or promotion
- is the app still healthy
- is the public URL still returning `200`

Then check:

```bash
kubectl get applications -n argocd
kubectl describe application opensis-prod -n argocd
kubectl describe application opensis-dev -n argocd
```

In this repo, `OutOfSync` has sometimes been expected during trust updates or manifest promotions. The important question is whether the system is converging back to the declared state.

## 10. When Argo Shows Degraded

Do not assume the UI is broken first.

Check:

```bash
kubectl get jobs -n opensis --sort-by=.metadata.creationTimestamp
kubectl get pods -n opensis
curl -I https://opensis.raysosglobal.com
```

If you see a recent failed backup Job, inspect it:

```bash
kubectl logs -n opensis job/<recent-backup-job> --all-containers=true --tail=200
```

This repo has already shown:

- failed backup Jobs can degrade Argo while the public site still serves traffic
- deleting the stale failed Job may not be enough if the underlying backup problem still exists

## 11. When Public Alerts Fire

For a public HTTP probe failure, check:

```bash
curl -I https://opensis.raysosglobal.com
kubectl get pods -n opensis
kubectl get pods -n opensis -l app=blackbox-exporter
```

If the site is healthy but the blackbox alert is firing, also inspect:

```bash
kubectl get networkpolicy -n opensis
kubectl logs -n opensis deploy/blackbox-exporter --tail=100
```

One validated lesson from this repo:

- blackbox probes needed explicit egress allowance to public `443`

## 12. When Database Auth Drifts

Database auth drift is serious because it can break:

- app startup
- backup jobs
- Argo app health

Start with:

```bash
kubectl exec -n opensis opensis-db-0 -- sh -lc 'cat /run/secrets/db.env'
kubectl exec -it -n vault vault-0 -- sh -lc 'export VAULT_ADDR=https://vault.vault.svc:8200; export VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault kv get kv/production/opensis-db'
```

If Vault and the rendered DB pod secret match, but MariaDB still rejects the credentials, the drift is inside MariaDB itself.

That is an operational repair, not just a secret reread.

## 13. What Good Looks Like

Healthy steady state:

- Argo apps are `Synced` and `Healthy`
- `dev` and `prod` smoke checks pass
- backup jobs complete successfully
- public prod URL returns `HTTP 200`
- Vault is unsealed and healthy
- recent alerts are quiet or understood

## 14. Where To Go Next

For failure scenarios, use:

- [05-troubleshooting-guide.md](05-troubleshooting-guide.md)
