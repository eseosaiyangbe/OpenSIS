#!/usr/bin/env sh
set -eu

NAMESPACE="${NAMESPACE:-opensis-dev}"
POD_NAME="${POD_NAME:-backup-inspect}"
PVC_NAME="${PVC_NAME:-opensis-db-backup-storage}"
IMAGE="${IMAGE:-busybox:1.36}"

if ! kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1; then
  echo "ERROR: PVC $PVC_NAME not found in namespace $NAMESPACE" >&2
  exit 1
fi

kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
trap 'kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true' EXIT

kubectl run "$POD_NAME" \
  -n "$NAMESPACE" \
  --restart=Never \
  --image="$IMAGE" \
  --overrides="{
  \"spec\": {
    \"containers\": [
      {
        \"name\": \"$POD_NAME\",
        \"image\": \"$IMAGE\",
        \"command\": [\"sh\", \"-c\", \"ls -lh /backup\"],
        \"volumeMounts\": [
          {
            \"name\": \"backup-storage\",
            \"mountPath\": \"/backup\"
          }
        ]
      }
    ],
    \"volumes\": [
      {
        \"name\": \"backup-storage\",
        \"persistentVolumeClaim\": {
          \"claimName\": \"$PVC_NAME\"
        }
      }
    ]
  }
}"

for _ in $(seq 1 60); do
  phase="$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ] || [ "$phase" = "Running" ]; then
    break
  fi
  sleep 1
done

kubectl logs -n "$NAMESPACE" "$POD_NAME"
