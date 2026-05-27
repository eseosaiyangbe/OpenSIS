#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ./tests/k8s/backup-delete.sh [--all]
  ./tests/k8s/backup-delete.sh --keep-latest
  ./tests/k8s/backup-delete.sh <backup-file-name>

Modes:
  --all
      Delete all OpenSIS backup archives from the backup PVC.

  --keep-latest
      Keep only the newest OpenSIS backup archive.

  <backup-file-name>
      Delete one named backup archive from the backup PVC.
EOF
}

NAMESPACE="${NAMESPACE:-opensis-dev}"
POD_NAME="${POD_NAME:-backup-delete}"
PVC_NAME="${PVC_NAME:-opensis-db-backup-storage}"
IMAGE="${IMAGE:-busybox:1.36}"
TARGET="${1:---all}"

if ! kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1; then
  echo "ERROR: PVC $PVC_NAME not found in namespace $NAMESPACE" >&2
  exit 1
fi

case "$TARGET" in
  -h|--help)
    usage
    exit 0
    ;;
  --all)
    DELETE_CMD='rm -f /backup/opensis-*.sql.gz && ls -lh /backup'
    ;;
  --keep-latest)
    DELETE_CMD='
      latest_backup="$(find /backup -maxdepth 1 -type f -name "opensis-*.sql.gz" -size +0c | sort | tail -n 1)"
      for file in /backup/opensis-*.sql.gz; do
        [ -e "$file" ] || continue
        [ "$file" = "$latest_backup" ] && continue
        rm -f "$file"
      done
      ls -lh /backup
    '
    ;;
  *)
    if [ "$#" -ne 1 ]; then
      echo "ERROR: invalid backup-delete invocation" >&2
      usage >&2
      exit 1
    fi
    DELETE_CMD="rm -f /backup/$TARGET && ls -lh /backup"
    ;;
esac

kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
trap 'kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true' EXIT

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    backup-role: state-backup
spec:
  restartPolicy: Never
  containers:
    - name: delete
      image: ${IMAGE}
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 64Mi
      command:
        - sh
        - -ec
        - |
$(printf '%s\n' "$DELETE_CMD" | sed 's/^/          /')
      volumeMounts:
        - name: backup-storage
          mountPath: /backup
  volumes:
    - name: backup-storage
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF

for _ in $(seq 1 60); do
  phase="$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ]; then
    break
  fi
  sleep 1
done

kubectl logs -n "$NAMESPACE" "$POD_NAME"
