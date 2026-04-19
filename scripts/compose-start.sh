#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/compose-start.sh [options]

Start the local Docker Compose stack.

Options:
  --build-local   Build the openSIS UI locally instead of pulling the dev image
  --edge          Include edge services (Traefik and Cloudflare Tunnel)
  --skip-precheck Skip ./scripts/precheck.sh
  -h, --help      Show this help message
EOF
}

require_repo_root() {
  if [[ ! -f "docker-compose.yaml" ]]; then
    echo "ERROR: Run this script from the repository root."
    exit 1
  fi
}

main() {
  local build_local=0
  local edge=0
  local skip_precheck=0
  local -a compose_cmd=(docker compose)

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-local)
        build_local=1
        shift
        ;;
      --edge)
        edge=1
        shift
        ;;
      --skip-precheck)
        skip_precheck=1
        shift
        ;;
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

  require_repo_root

  if [[ "$skip_precheck" -eq 0 ]]; then
    ./scripts/precheck.sh
  fi

  if [[ "$build_local" -eq 1 ]]; then
    compose_cmd+=(-f docker-compose.yaml -f docker-compose.buildlocal.yaml)
  fi

  if [[ "$edge" -eq 1 ]]; then
    compose_cmd+=(--profile edge)
  fi

  echo "Starting local stack..."
  if [[ "$build_local" -eq 1 ]]; then
    compose_cmd+=(up -d --build)
  else
    compose_cmd+=(up -d)
  fi

  "${compose_cmd[@]}"

  echo
  echo "Stack status:"
  docker compose ps
  echo
  echo "OpenSIS: http://localhost:8088"
  echo "Vault:   http://localhost:8200"
}

main "$@"
