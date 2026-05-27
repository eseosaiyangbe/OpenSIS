#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ./tests/k8s/backup-run.sh
  ./tests/k8s/backup-run.sh --help

Behavior:
  Creates a one-off backup Job from CronJob/opensis-db-backup,
  waits for completion, and prints the backup container logs.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$#" -ne 0 ]; then
  echo "ERROR: backup-run.sh does not accept positional arguments" >&2
  usage >&2
  exit 1
fi

NAMESPACE="${NAMESPACE:-opensis-dev}"
CRONJOB_NAME="${CRONJOB_NAME:-opensis-db-backup}"
JOB_NAME="${JOB_NAME:-opensis-db-backup-manual}"
TIMEOUT="${TIMEOUT:-300s}"

if ! kubectl get cronjob -n "$NAMESPACE" "$CRONJOB_NAME" >/dev/null 2>&1; then
  echo "ERROR: CronJob $CRONJOB_NAME not found in namespace $NAMESPACE" >&2
  exit 1
fi

kubectl delete job -n "$NAMESPACE" "$JOB_NAME" --ignore-not-found >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  if ! kubectl get job -n "$NAMESPACE" "$JOB_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

kubectl create job --from=cronjob/"$CRONJOB_NAME" -n "$NAMESPACE" "$JOB_NAME"
kubectl wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout="$TIMEOUT"
kubectl logs -n "$NAMESPACE" job/"$JOB_NAME"
