#!/usr/bin/env sh
set -eu

NAMESPACE="${NAMESPACE:-opensis-dev}"
CRONJOB_NAME="${CRONJOB_NAME:-opensis-db-backup}"
JOB_NAME="${JOB_NAME:-opensis-db-backup-manual}"
TIMEOUT="${TIMEOUT:-300s}"

kubectl delete job -n "$NAMESPACE" "$JOB_NAME" --ignore-not-found >/dev/null 2>&1 || true
kubectl create job --from=cronjob/"$CRONJOB_NAME" -n "$NAMESPACE" "$JOB_NAME"
kubectl wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout="$TIMEOUT"
kubectl logs -n "$NAMESPACE" job/"$JOB_NAME"
