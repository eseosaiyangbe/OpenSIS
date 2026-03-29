#!/bin/sh
set -e

# Pre-check script for Dev_test2 Vault + openSIS stack
# Usage: ./scripts/precheck.sh

REQ_DIRS="vault-agent/db-approle vault-agent/app-approle vault-bootstrap/policies vault-agent/db-config vault-agent/app-config observability/grafana/provisioning/datasources observability/grafana/provisioning/dashboards observability/grafana/dashboards"
REQ_FILES="docker-compose.yaml Dockerfile scripts/bootstrap.sh scripts/seed.sh"

echo "Running pre-checks..."

for d in $REQ_DIRS; do
  if [ ! -d "$d" ]; then
    echo "ERROR: Required directory missing: $d"
    exit 1
  fi
done

for f in $REQ_FILES; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Required file missing: $f"
    exit 1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not installed or not in PATH"
  exit 1
fi

# Check for docker-compose (legacy) or docker compose (new)
if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker-compose not installed or not in PATH"
  exit 1
fi

if [ $(id -u) -eq 0 ]; then
  echo "WARNING: Running as root. It is safer to run as non-root user."
fi

# Suggest cleanup checks
if docker ps -a --format '{{.Names}}' | grep -q '^vault$'; then
  echo "INFO: Existing vault container found, it may cause conflicts"
  docker ps -a --format '{{.Names}}' | grep '^vault$'
fi

if docker volume ls --format '{{.Name}}' | grep -q '^vault_data$'; then
  echo "INFO: vault_data volume exists (good)"
fi

echo "Pre-check complete. Ready to run docker-compose up."
