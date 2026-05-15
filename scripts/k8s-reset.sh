#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="opensis-dev"
WAIT_FOR_DELETE=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-reset.sh [options]

Destructively reset the OpenSIS dev Kubernetes slice.

This deletes the entire opensis-dev namespace and all resources inside it,
including the MariaDB persistent volume claim. Use this only when you
intentionally want a clean reinstall.

Options:
  --yes        Skip the interactive confirmation prompt
  --wait       Wait for namespace deletion to complete before returning
  -h, --help   Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES=1
      shift
      ;;
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
  echo "[opensis-k8s] Namespace ${NAMESPACE} does not exist. Nothing to reset."
  exit 0
fi

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  cat <<EOF
[opensis-k8s] WARNING: This will permanently delete the ${NAMESPACE} namespace.
[opensis-k8s] It will remove:
  - OpenSIS deployments, services, ingress, and secrets
  - the MariaDB persistent volume claim
  - the current OpenSIS schema and accounts

Type RESET to continue:
EOF
  read -r confirmation
  if [[ "${confirmation}" != "RESET" ]]; then
    echo "[opensis-k8s] Reset cancelled."
    exit 1
  fi
fi

echo "[opensis-k8s] Deleting namespace ${NAMESPACE}"
kubectl delete namespace "${NAMESPACE}" >/dev/null

if [[ "${WAIT_FOR_DELETE}" -eq 1 ]]; then
  echo "[opensis-k8s] Waiting for namespace deletion"
  while kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; do
    sleep 2
  done
fi

echo "[opensis-k8s] OpenSIS dev namespace deleted. The next k8s-start.sh run will perform a fresh install path."
