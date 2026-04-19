#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/compose-stop.sh [options]

Stop the local Docker Compose stack.

Options:
  --build-local   Use the local-build compose override
  --edge          Include edge services (Traefik and Cloudflare Tunnel)
  --volumes       Remove named volumes as well
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
  local remove_volumes=0
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
      --volumes)
        remove_volumes=1
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

  if [[ "$build_local" -eq 1 ]]; then
    compose_cmd+=(-f docker-compose.yaml -f docker-compose.buildlocal.yaml)
  fi

  if [[ "$edge" -eq 1 ]]; then
    compose_cmd+=(--profile edge)
  fi

  compose_cmd+=(down --remove-orphans)

  if [[ "$remove_volumes" -eq 1 ]]; then
    compose_cmd+=(-v)
  fi

  echo "Stopping local stack..."
  "${compose_cmd[@]}"
}

main "$@"
