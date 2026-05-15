#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_IMAGES=0
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

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-start.sh [options] [-- <extra deploy args>]

Start the OpenSIS dev overlay in the current Kubernetes context.

If the OpenSIS namespace already exists, this script resumes the preserved
workloads by scaling them back up. If the namespace does not exist yet, it
falls back to the full deploy path.

By default, this reuses the existing local image. Use --build when you
intentionally want a fresh local image build.

Options:
  --build      Rebuild the OpenSIS image before deploy
  -h, --help   Show this help message
EOF
}

extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_IMAGES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

has_existing_namespace=0
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  has_existing_namespace=1
fi

if [[ "${BUILD_IMAGES}" -eq 0 && "${has_existing_namespace}" -eq 1 ]]; then
  echo "[opensis-k8s] Existing namespace detected. Resuming preserved workloads."
  kubectl -n "${NAMESPACE}" scale statefulset "${STATEFULSETS[@]}" --replicas=1
  kubectl -n "${NAMESPACE}" scale deployment "${DEPLOYMENTS[@]}" --replicas=1

  echo "[opensis-k8s] Waiting for supporting services"
  kubectl rollout status statefulset/opensis-db -n "${NAMESPACE}" --timeout=300s
  kubectl rollout status deployment/opensis-session-redis -n "${NAMESPACE}" --timeout=180s
  kubectl rollout status deployment/opensis-mysqld-exporter -n "${NAMESPACE}" --timeout=180s
  kubectl rollout status deployment/opensis-vault-synthetic-exporter -n "${NAMESPACE}" --timeout=180s

  echo "[opensis-k8s] Waiting for application rollout"
  kubectl rollout status deployment/opensis-ui -n "${NAMESPACE}" --timeout=300s
  kubectl rollout status deployment/opensis-apache-exporter -n "${NAMESPACE}" --timeout=180s

  exit 0
fi

cmd=("${ROOT_DIR}/scripts/k8s-dev-deploy.sh")
if [[ "${BUILD_IMAGES}" -eq 0 ]]; then
  cmd+=(--skip-build)
fi
if [[ "${#extra_args[@]}" -gt 0 ]]; then
  cmd+=("${extra_args[@]}")
fi

exec "${cmd[@]}"
