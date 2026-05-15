#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-stop.sh [options]

Stop the OpenSIS dev overlay from the current Kubernetes context.
This preserves the namespace and persistent data by scaling OpenSIS workloads
down to zero instead of deleting the full overlay.

Options:
  --wait       Wait for workloads to terminate before returning
  -h, --help   Show this help message
EOF
}

WAIT_FOR_DELETE=0
NAMESPACE="opensis-dev"

DEPLOYMENTS=(
  opensis-apache-exporter
  opensis-mysqld-exporter
  opensis-session-redis
  opensis-ui
  opensis-vault-synthetic-exporter
)

STATEFULSETS=(
  opensis-db
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait)
      WAIT_FOR_DELETE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[opensis-k8s] Namespace ${NAMESPACE} does not exist. Nothing to stop."
  exit 0
fi

echo "[opensis-k8s] Scaling deployments to zero"
kubectl -n "${NAMESPACE}" scale deployment "${DEPLOYMENTS[@]}" --replicas=0 >/dev/null 2>&1 || true

echo "[opensis-k8s] Scaling statefulsets to zero"
kubectl -n "${NAMESPACE}" scale statefulset "${STATEFULSETS[@]}" --replicas=0 >/dev/null 2>&1 || true

if [[ "${WAIT_FOR_DELETE}" -eq 1 ]]; then
  echo "[opensis-k8s] Waiting for workload shutdown"
  kubectl -n "${NAMESPACE}" wait --for=delete pod -l app=opensis-ui --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" wait --for=delete pod -l app=opensis-session-redis --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" wait --for=delete pod -l app=opensis-db --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" wait --for=delete pod -l app=opensis-apache-exporter --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" wait --for=delete pod -l app=opensis-mysqld-exporter --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" wait --for=delete pod -l app=opensis-vault-synthetic-exporter --timeout=300s >/dev/null 2>&1 || true
fi

echo "[opensis-k8s] OpenSIS workloads stopped. Namespace and persistent data were preserved."
