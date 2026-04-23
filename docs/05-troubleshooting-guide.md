# 05: Troubleshooting Guide

Use this guide by symptom.

The goal is simple:

1. confirm what is actually broken
2. narrow the likely cause
3. use the smallest safe fix

Many of the examples in this guide come from real incidents already seen in this repo.

## 1. Docker Compose Will Not Start

### Symptom

- `docker compose up -d` fails

### Check

```bash
./scripts/precheck.sh
docker compose config
docker compose logs
```

### Common causes

- port conflict
- missing `.env` values
- Docker Desktop not running on macOS
- missing build context files
- Apple Silicon host pulling an AMD64-only `opensis-ui:dev` image

### Typical fix

- resolve the first clear error
- rerun `docker compose config`
- retry `docker compose up -d`

### Apple Silicon / ARM64 Image Manifest Error

### Symptom

- `docker compose up -d` fails with:
- `no matching manifest for linux/arm64/v8 in the manifest list entries`

### What is happening

Older revisions of this repo used `docker.io/eseosaiyangbe/opensis-ui:dev` directly in the base Compose file.
That published dev image does not currently include an `linux/arm64/v8` manifest.

The portable local path is now:

```bash
./scripts/compose-start.sh
```

and the raw Compose equivalent is:

```bash
docker compose up -d --build
```

Both use the local Dockerfile for `opensis-ui`, which avoids host-architecture image manifest issues.

### Fix

Use one of these:

```bash
./scripts/compose-start.sh
```

or

```bash
docker compose up -d --build
```

Only use the published image path when you intentionally opt into it on a compatible platform:

```bash
./scripts/compose-start.sh --pull-image
```

## 2. Port Already In Use

### Symptom

- `failed to bind host port`

### Check on Linux

```bash
ss -ltnp | rg ':8088|:8200|:80'
```

### Check on macOS

```bash
lsof -nP -iTCP -sTCP:LISTEN | rg ':(8088|8200|80)\\b'
```

### Common causes

- another local app already owns the port
- a previous `kubectl port-forward` is still running
- an old Compose stack is still up

### Typical fix

- stop the process using the port
- or move the local port binding if needed

## 3. Vault UI Port-Forward Breaks

### Symptom

- `kubectl port-forward` disconnects

### Common cause

- the client connected to `http://localhost:8200` instead of `https://localhost:8200`

### What is happening

In this repo, Vault is TLS-enabled on port `8200`. Plain HTTP to that port can reset the connection and make the port-forward appear broken.

### Fix

Use:

```bash
kubectl port-forward -n vault svc/vault-ui 8200:8200
curl -k https://localhost:8200/v1/sys/health
```

## 4. K9s Shows `n/a`

### Symptom

- K9s opens but cannot connect to the cluster
- K9s falls back to `localhost:8080`

### Common cause

- K9s cannot find a standard kubeconfig

### Fix for `k3s`

```bash
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

Optional cleanup:

```bash
kubectl config rename-context default k3s-devbox
```

## 5. opensis-prod Is OutOfSync

### Check

```bash
kubectl get applications -n argocd
kubectl describe application opensis-prod -n argocd
```

### Typical causes

- a new Git commit has not been reconciled yet
- one resource drifted from the desired manifest
- a manual live patch was applied and Git has not caught up

### Fix

If the change should be in Git, sync the app. If the live cluster was patched manually, bring Git back in line or expect Argo to keep reporting drift.

## 6. opensis-prod Is Degraded But The Site Still Works

### Check

```bash
kubectl get jobs -n opensis --sort-by=.metadata.creationTimestamp
kubectl get pods -n opensis
curl -I https://opensis.raysosglobal.com
```

### Common cause in this repo

- a failed `opensis-db-backup` child Job

### Why this matters

Argo can mark the app `Degraded` because of a failed backup Job even when the public site still returns `200`.

### Next step

Inspect the recent backup Job:

```bash
kubectl logs -n opensis job/<job-name> --all-containers=true --tail=200
```

## 7. Backup Job Fails With Access Denied

### Symptom

- `mysqldump ... Access denied`

### Meaning

- Vault may be correct
- the rendered secret may also be correct
- but MariaDB users may have drifted away from the values stored in Vault

### Checks

```bash
kubectl exec -n opensis opensis-db-0 -- sh -lc 'cat /run/secrets/db.env'
kubectl exec -it -n vault vault-0 -- sh -lc 'export VAULT_ADDR=https://vault.vault.svc:8200; export VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault kv get kv/production/opensis-db'
```

If Vault and the rendered secret match, but MariaDB still rejects auth, the problem is inside the live MariaDB user state.

## 8. App Pods Return `500`

### Check

```bash
kubectl logs -n opensis deploy/opensis-ui --tail=100
kubectl logs -n opensis-dev deploy/opensis-ui --tail=100
```

### Things to check

- DB credentials
- session backend
- Vault-rendered `app.env`
- current image version
- whether the request path is coming through the expected edge flow

### Important repo lesson

This project previously had app code that behaved differently for browser and non-browser requests. If probes or non-browser traffic behave differently, check the deployed image version before assuming the edge layer is at fault.

## 9. Vault Agent Init Fails In Pods

### Symptom

- pod stuck in `Init`
- TLS verification errors against Vault

### Common cause

- missing `vault-agent-ca` secret
- missing `vault.hashicorp.com/tls-secret`
- missing `vault.hashicorp.com/ca-cert`

### Check

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> -c vault-agent-init
```

### Common error text

- `x509: certificate signed by unknown authority`

## 10. Vault Is Sealed After Restart

### Check

```bash
kubectl exec -n vault vault-0 -- sh -lc 'export VAULT_ADDR=https://vault.vault.svc:8200 VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault status'
```

### Fix

- unseal Vault with the required number of unseal keys

### Reminder

On this repo’s learning path, manual unseal is expected after certain restarts. That is a lab tradeoff, not a production-grade final state.

## 11. Blackbox HTTP Alert Fires While The Site Looks Fine

### Check

```bash
kubectl exec -n opensis deploy/prometheus -- sh -lc 'wget -qO- "http://127.0.0.1:9090/api/v1/alerts"'
kubectl exec -n opensis deploy/prometheus -- sh -lc 'wget -qO- "http://blackbox-exporter:9115/probe?module=http_2xx&target=https://opensis.raysosglobal.com&debug=true"'
```

### Common cause in this repo

- `blackbox-exporter` was missing outbound `443` egress in network policy

### Meaning

The site itself may be healthy while the probe path is blocked.

## 12. Database Auth Drift Breaks Backups Or Startup

### Symptom

- app startup fails
- backup jobs fail
- Argo health becomes worse than the visible user experience

### Check

```bash
kubectl exec -n opensis opensis-db-0 -- sh -lc 'cat /run/secrets/db.env'
kubectl exec -it -n vault vault-0 -- sh -lc 'export VAULT_ADDR=https://vault.vault.svc:8200; export VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault kv get kv/production/opensis-db'
```

### What it means

If Vault and the DB pod secret match, but the database still rejects auth, MariaDB itself has drifted.

That is a runtime repair, not just a secret refresh.

## 13. A Rollout Hangs With Old Pods Still Around

### Symptom

- `kubectl rollout status ...` hangs
- one new pod is ready, but an old pod is still pending termination

### Check

```bash
kubectl get pods -n <namespace> -l app=<app-name> -o wide
kubectl describe deployment <deployment-name> -n <namespace>
```

### Common meaning

- the new pod may still be stuck in init
- or the old pod may be taking too long to terminate

Always confirm the new pod is actually healthy before deleting the old one.

## 14. If You Need The Detailed Recovery Story

Use:

- [FROM_SCRATCH_LOCAL_BOOTSTRAP.md](../k8s/FROM_SCRATCH_LOCAL_BOOTSTRAP.md)

That file includes the validated incidents and recovery flows from the real build-out of this project.
