#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ./tests/k8s/restore-run.sh
  ./tests/k8s/restore-run.sh <opensis-backup.sql.gz>
  ./tests/k8s/restore-run.sh --help

Behavior:
  With no arguments, restore the newest valid OpenSIS backup archive.
  With one argument, restore the named backup archive.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "ERROR: expected zero arguments or one backup filename" >&2
  usage >&2
  exit 1
fi

NAMESPACE="${NAMESPACE:-opensis-dev}"
POD_NAME="${POD_NAME:-opensis-db-restore}"
PVC_NAME="${PVC_NAME:-opensis-db-backup-storage}"
IMAGE="${IMAGE:-mariadb:10.11.7}"
DUMP_HOST="${DUMP_HOST:-opensis-db}"
DUMP_PORT="${DUMP_PORT:-3306}"
BACKUP_FILE="${BACKUP_FILE:-${1:-}}"

case "$NAMESPACE" in
  opensis-dev)
    VAULT_ROLE="${VAULT_ROLE:-opensis-db-backup-dev}"
    VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-kv/data/dev/opensis-db}"
    ;;
  opensis)
    VAULT_ROLE="${VAULT_ROLE:-opensis-db-backup}"
    VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-kv/data/production/opensis-db}"
    ;;
  *)
    VAULT_ROLE="${VAULT_ROLE:-opensis-db-backup-dev}"
    VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-kv/data/dev/opensis-db}"
    ;;
esac

if ! kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1; then
  echo "ERROR: PVC $PVC_NAME not found in namespace $NAMESPACE" >&2
  exit 1
fi

kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
trap 'kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true' EXIT

RESTORE_SCRIPT='SECRETS_FILE="/run/secrets/db.env"
until [ -s "$SECRETS_FILE" ]; do
  sleep 2
done

set -a
. "$SECRETS_FILE"
set +a

backup_file="$BACKUP_FILE"
if [ -z "$backup_file" ]; then
  backup_file="$(ls -1 /backup/opensis-*.sql.gz 2>/dev/null | sort | tail -n 1)"
elif [ "${backup_file#/}" = "$backup_file" ]; then
  backup_file="/backup/$backup_file"
fi

if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
  echo "ERROR: backup file not found: ${backup_file:-<none>}" >&2
  exit 1
fi

echo "Waiting for MariaDB at $DUMP_HOST:$DUMP_PORT before restore"
for _ in $(seq 1 60); do
  if mysqladmin ping \
    --host="$DUMP_HOST" \
    --port="$DUMP_PORT" \
    --user=root \
    --password="$MYSQL_ROOT_PASSWORD" \
    --connect-timeout=5 \
    --silent >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! mysqladmin ping \
  --host="$DUMP_HOST" \
  --port="$DUMP_PORT" \
  --user=root \
  --password="$MYSQL_ROOT_PASSWORD" \
  --connect-timeout=5 \
  --silent >/dev/null 2>&1; then
  echo "ERROR: MariaDB not reachable at $DUMP_HOST:$DUMP_PORT" >&2
  exit 1
fi

echo "Restoring from $backup_file into $DUMP_HOST:$DUMP_PORT"
gzip -dc "$backup_file" | mysql \
  --host="$DUMP_HOST" \
  --port="$DUMP_PORT" \
  --user=root \
  --password="$MYSQL_ROOT_PASSWORD"
echo "Restore completed from $backup_file"'

export NAMESPACE POD_NAME PVC_NAME IMAGE VAULT_ROLE VAULT_SECRET_PATH BACKUP_FILE DUMP_HOST DUMP_PORT RESTORE_SCRIPT

python3 <<'PY' | kubectl apply -f - >/dev/null
import json
import os

namespace = os.environ['NAMESPACE']
pod_name = os.environ['POD_NAME']
pvc_name = os.environ['PVC_NAME']
image = os.environ['IMAGE']
vault_role = os.environ['VAULT_ROLE']
vault_secret_path = os.environ['VAULT_SECRET_PATH']
backup_file = os.environ['BACKUP_FILE']
dump_host = os.environ['DUMP_HOST']
dump_port = os.environ['DUMP_PORT']
restore_script = os.environ['RESTORE_SCRIPT']

print(f'''apiVersion: v1
kind: Pod
metadata:
  name: {pod_name}
  namespace: {namespace}
  labels:
    app: opensis-db-backup
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/agent-pre-populate-only: "true"
    vault.hashicorp.com/auth-path: "auth/kubernetes"
    vault.hashicorp.com/role: "{vault_role}"
    vault.hashicorp.com/secret-volume-path: "/run/secrets"
    vault.hashicorp.com/agent-inject-secret-db.env: "{vault_secret_path}"
    vault.hashicorp.com/agent-inject-template-db.env: |
      {{{{- with secret "{vault_secret_path}" -}}}}
      MYSQL_ROOT_PASSWORD={{{{ .Data.data.MYSQL_ROOT_PASSWORD }}}}
      MYSQL_DATABASE={{{{ .Data.data.MYSQL_DATABASE }}}}
      MYSQL_USER={{{{ .Data.data.MYSQL_USER }}}}
      MYSQL_PASSWORD={{{{ .Data.data.MYSQL_PASSWORD }}}}
      {{{{- end }}}}
spec:
  serviceAccountName: opensis-db-backup
  restartPolicy: Never
  containers:
    - name: restore
      image: {image}
      imagePullPolicy: IfNotPresent
      command:
        - /bin/sh
        - -ec
        - {json.dumps(restore_script)}
      env:
        - name: BACKUP_FILE
          value: {json.dumps(backup_file)}
        - name: DUMP_HOST
          value: {json.dumps(dump_host)}
        - name: DUMP_PORT
          value: {json.dumps(dump_port)}
      volumeMounts:
        - name: backup-storage
          mountPath: /backup
  volumes:
    - name: backup-storage
      persistentVolumeClaim:
        claimName: {pvc_name}
''')
PY

for _ in $(seq 1 180); do
  phase="$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ]; then
    break
  fi
  sleep 1
done

kubectl logs -n "$NAMESPACE" "$POD_NAME"
phase="$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [ "$phase" != "Succeeded" ]; then
  echo "ERROR: restore pod ended in phase ${phase:-Unknown}" >&2
  exit 1
fi
