# Kubernetes Verification Helpers

This folder holds reusable Kubernetes verification helpers for the OpenSIS learning stack.

## Current Scripts

- `backup-run.sh`
  - triggers a one-off database backup job from the `opensis-db-backup` `CronJob`
- `backup-inspect.sh`
  - mounts the backup PVC in a temporary pod and lists the files stored on it
- `backup-delete.sh`
  - deletes one backup file or all backup dump files from the backup PVC
- `restore-reset.sh`
  - resets the dev database schema before a restore drill
- `restore-run.sh`
  - mounts the backup PVC and restores a chosen or latest dump back into MariaDB
- `restore-verify.sh`
  - verifies that the restored schema and key application table data are present
- `vault-smoke.yaml`
  - creates a simple Vault-injected pod for end-to-end secret-injection validation

## Default Namespace

The scripts default to `opensis-dev` because that is the safest place to validate new changes first.

You can override the namespace with:

```bash
NAMESPACE=opensis ./tests/k8s/<script>.sh
```
