#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-dev-deploy.sh [options]

Build and deploy the OpenSIS k3s dev overlay to the current Kubernetes context.

Options:
  --skip-runtime           Skip local k3s runtime bootstrap
  --skip-build             Reuse existing local opensis-ui image
  --skip-secrets-platform  Skip shared Vault and External Secrets bootstrap
  --skip-apply             Only build and validate; do not apply manifests
  --hostname HOST          Override ingress hostname validation target
  -h, --help               Show this help message
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
HOSTNAME_OVERRIDE="opensis.devops.local"
SKIP_RUNTIME=0
SKIP_BUILD=0
SKIP_SECRETS_PLATFORM=0
SKIP_APPLY=0
UI_IMAGE="opensis-ui:dev"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-runtime)
      SKIP_RUNTIME=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --skip-secrets-platform)
      SKIP_SECRETS_PLATFORM=1
      shift
      ;;
    --skip-apply)
      SKIP_APPLY=1
      shift
      ;;
    --hostname)
      HOSTNAME_OVERRIDE="${2:?Missing hostname value}"
      shift 2
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

import_image_to_k3s() {
  local image_ref="$1"

  if ! docker image inspect "${image_ref}" >/dev/null 2>&1; then
    echo "ERROR: Required local image not found: ${image_ref}" >&2
    exit 1
  fi

  if command -v colima >/dev/null 2>&1; then
    echo "[opensis-k8s] Importing ${image_ref} into Colima k3s containerd"
    docker save "${image_ref}" | colima ssh -- sh -lc 'ctr -n k8s.io images import -' >/dev/null
    return 0
  fi

  if command -v k3s >/dev/null 2>&1; then
    echo "[opensis-k8s] Importing ${image_ref} into local k3s containerd"
    docker save "${image_ref}" | sudo k3s ctr images import - >/dev/null
    return 0
  fi

  echo "ERROR: Unable to determine how to import ${image_ref} into the k3s runtime." >&2
  exit 1
}

cd "${ROOT_DIR}"

if [[ "${SKIP_RUNTIME}" -eq 0 ]]; then
  "${WORKSPACE_ROOT}/scripts/ensure-k3s-runtime.sh" >/dev/null
fi

if [[ "${SKIP_SECRETS_PLATFORM}" -eq 0 ]]; then
  "${WORKSPACE_ROOT}/scripts/bootstrap-k3s-vault-secrets.sh" >/dev/null
fi

echo "[opensis-k8s] Validating kustomize overlay"
kubectl kustomize k8s/overlays/dev >/dev/null
kubectl apply --dry-run=client -k k8s/overlays/dev >/dev/null

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  echo "[opensis-k8s] Building local OpenSIS image"
  docker build -t "${UI_IMAGE}" .
fi

import_image_to_k3s "${UI_IMAGE}"

if [[ "${SKIP_APPLY}" -eq 1 ]]; then
  echo "[opensis-k8s] Skipping apply by request"
  exit 0
fi

echo "[opensis-k8s] Applying overlay"
kubectl apply -k k8s/overlays/dev

echo "[opensis-k8s] Waiting for External Secrets readiness"
kubectl wait --for=condition=Ready externalsecret/opensis-app-secrets-external -n opensis-dev --timeout=180s
kubectl wait --for=condition=Ready externalsecret/opensis-db-secrets-external -n opensis-dev --timeout=180s

echo "[opensis-k8s] Waiting for supporting services"
kubectl rollout status deployment/opensis-session-redis -n opensis-dev --timeout=180s
kubectl rollout status statefulset/opensis-db -n opensis-dev --timeout=300s
kubectl rollout status deployment/opensis-mysqld-exporter -n opensis-dev --timeout=180s
kubectl rollout status deployment/opensis-vault-synthetic-exporter -n opensis-dev --timeout=180s

echo "[opensis-k8s] Waiting for application rollout"
kubectl rollout status deployment/opensis-ui -n opensis-dev --timeout=300s
kubectl rollout status deployment/opensis-apache-exporter -n opensis-dev --timeout=180s

echo "[opensis-k8s] Verifying live path"
"${ROOT_DIR}/scripts/k8s-dev-verify.sh" --hostname "${HOSTNAME_OVERRIDE}"
