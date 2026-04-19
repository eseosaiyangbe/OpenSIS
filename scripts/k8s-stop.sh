#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-stop.sh [options]

Stop the local k3s Kubernetes cluster.

Options:
  -h, --help  Show this help message

Example:
  ./scripts/k8s-stop.sh
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1"
    exit 1
  fi
}

run_systemctl() {
  local action="$1"

  if systemctl "$action" k3s; then
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    return 1
  fi

  echo "Direct systemctl ${action} failed; retrying with sudo..."
  sudo systemctl "$action" k3s
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown option: $1"
        echo
        usage
        exit 1
        ;;
    esac
  done

  require_command systemctl

  echo "Stopping k3s..."
  run_systemctl stop

  echo
  echo "k3s service state:"
  systemctl is-active k3s || true

  echo
  echo "Kubernetes API check:"
  if command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    echo "WARNING: kubectl can still reach the API. Check k3s status manually."
  else
    echo "Kubernetes API is not reachable, as expected after stopping k3s."
  fi
}

main "$@"
