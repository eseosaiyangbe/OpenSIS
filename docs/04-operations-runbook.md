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
./scripts/k8s-reset.sh --help
./scripts/smoke-dev.sh
./scripts/smoke-prod.sh
```

### Quick public-prod check

```bash
curl -I https://opensis.eseosadevbox.com
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
curl -I https://opensis.eseosadevbox.com
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

### Start or resume the OpenSIS dev slice

For the repo-local OpenSIS dev slice, use:

```bash
./scripts/k8s-start.sh
```

This script:

- resumes the preserved `opensis-dev` workloads if the namespace already exists
- falls back to the full deploy path only when the namespace does not exist
- preserves the MariaDB PVC across normal stop/start cycles
- can still force a fresh image rollout with `--build`

### Stop the OpenSIS dev slice safely

To stop OpenSIS without deleting its state:

```bash
./scripts/k8s-stop.sh
```

This script:

- scales the OpenSIS deployments down to `0`
- scales the OpenSIS MariaDB statefulset down to `0`
- preserves the namespace and PVC
- does not intentionally remove schema or accounts

If you want the command to wait until workloads have terminated:

```bash
./scripts/k8s-stop.sh --wait
```

### Destructive reset for a clean reinstall

Use this only when you intentionally want to wipe the OpenSIS dev slice and reinstall it from scratch:

```bash
./scripts/k8s-reset.sh --wait
```

This script:

- deletes the entire `opensis-dev` namespace
- removes the OpenSIS MariaDB PVC
- destroys the current schema, `Data.php` path, and seeded accounts
- leaves the next `./scripts/k8s-start.sh` run to recreate the namespace and full install path

For unattended reset runs, use:

```bash
./scripts/k8s-reset.sh --yes --wait
```

Important boundary:

- `k8s-stop.sh` is the normal operational stop path
- `k8s-reset.sh` is destructive and should be treated like a reinstall action, not a pause action
- if you use `k8s-reset.sh`, you should expect to complete the installer again before login works

### Delete and reinstall the dev slice cleanly

When the dev environment is intentionally being rebuilt from scratch, use this exact order:

1. Destructively reset the namespace and PVC:

```bash
./scripts/k8s-reset.sh --wait
```

2. Recreate the namespace and workloads:

```bash
./scripts/k8s-start.sh
```

3. Open the installer:

- [https://opensis.eseosadevbox.com/install/index.php](https://opensis.eseosadevbox.com/install/index.php)

4. Use these database values:

- Server: `opensis-db`
- Port: `3306`
- Username: `root`
- Password: `opensis-root-123`
- Database: `opensis`

5. For the site admin account, use the current dev standard:

- Username: `admin`
- Password: `Raymond@123`

6. Validate the install after completion:

```bash
kubectl -n opensis-dev get pods
kubectl -n opensis-dev exec deploy/opensis-ui -- sh -c 'ls -l /var/www/openSIS/Data.php'
kubectl -n opensis-dev exec statefulset/opensis-db -- sh -c 'mysql -N -uroot -popensis-root-123 -D opensis -e "SELECT username, profile_id FROM login_authentication WHERE username=\"admin\";"'
curl -I https://opensis.eseosadevbox.com
```

Healthy reinstall signals:

- `opensis-ui`, `opensis-db`, `opensis-session-redis`, and exporters are `Running`
- `/var/www/openSIS/Data.php` exists in the UI pod
- the `admin` account exists in `login_authentication`
- the public URL returns `200`

### Restart only the prod UI

```bash
kubectl rollout restart deployment/opensis-ui -n opensis
kubectl rollout status deployment/opensis-ui -n opensis
curl -I https://opensis.eseosadevbox.com
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

The current `dev` backup contract is:

- `CronJob/opensis-db-backup`
  - schedule: `0 2 * * *`
  - timezone: `Etc/UTC`
- retention:
  - newest `7` backup archives
- artifact format:
  - `opensis-YYYYMMDDTHHMMSSZ.sql.gz`

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
./tests/k8s/backup-delete.sh --keep-latest
```

Delete all backup files:

```bash
./tests/k8s/backup-delete.sh --all
```

### Controlled restore drill

Suspend GitOps automation before a live restore drill:

```bash
kubectl patch application internal-developer-platform-dev-root -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl patch application opensis-dev -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
```

Reset, restore, and verify:

```bash
./tests/k8s/restore-reset.sh
./tests/k8s/restore-run.sh opensis-20260527T163506Z.sql.gz
./tests/k8s/restore-verify.sh
```

Re-enable GitOps automation afterward:

```bash
kubectl patch application internal-developer-platform-dev-root -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl patch application opensis-dev -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'
kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application opensis-dev -n argocd -o wide
```

Important lesson from this repo’s real operation:

- a failed backup Job can make Argo show `Degraded` even while the site still returns `200`
- the OpenSIS MariaDB policy must explicitly allow ingress from `opensis-db-backup`, or the backup pod will wait forever at the database connectivity step
- the MariaDB backup and restore helper pods must disable service account token mounts, or container startup can fail on this runtime with a read-only filesystem error under `/var/run/secrets/kubernetes.io/serviceaccount`
- backup and restore helper scripts must match the live DB secret path inside the database pod, which is `/opt/opensis/secrets/db.env` for reset and verification inside `opensis-db-0`

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
curl -I https://opensis.eseosadevbox.com
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
curl -I https://opensis.eseosadevbox.com
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
