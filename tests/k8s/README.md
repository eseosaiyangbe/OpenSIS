# Kubernetes Verification Helpers

This folder holds reusable Kubernetes verification helpers for the OpenSIS learning stack.

## Current Scripts

- `backup-run.sh`
  - triggers a one-off database backup job from the `opensis-db-backup` `CronJob`
  - supports `--help`
- `backup-inspect.sh`
  - mounts the backup PVC in a temporary pod and lists the files stored on it
  - supports `--help`
- `backup-delete.sh`
  - deletes one backup file, keeps only the newest file, or removes all backup dump files from the backup PVC
  - supports `--help`, `--keep-latest`, and `--all`
- `restore-reset.sh`
  - resets the dev database schema before a restore drill
- `restore-run.sh`
  - mounts the backup PVC and restores a chosen or latest dump back into MariaDB
  - supports `--help`
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

## Current Backup Contract

- `CronJob/opensis-db-backup`
  - schedule: `0 2 * * *`
  - timezone: `Etc/UTC`
- retention:
  - newest `7` backup archives
- artifact format:
  - `opensis-YYYYMMDDTHHMMSSZ.sql.gz`

## Useful End-To-End Commands

Run a one-off backup:

```bash
./tests/k8s/backup-run.sh
```

Inspect stored backups:

```bash
./tests/k8s/backup-inspect.sh
```

Keep only the newest backup archive:

```bash
./tests/k8s/backup-delete.sh --keep-latest
```

Reset the database before a restore drill:

```bash
./tests/k8s/restore-reset.sh
```

Restore a specific archive:

```bash
./tests/k8s/restore-run.sh opensis-YYYYMMDDTHHMMSSZ.sql.gz
```

Verify restored data:

```bash
./tests/k8s/restore-verify.sh
```

## Validated Dev Drill

The current OpenSIS dev backup and restore path has been validated against:

- backup artifact:
  - `opensis-20260527T163506Z.sql.gz`
- restore verification:
  - `102` tables present in `opensis`
  - `app` table row count: `5`
