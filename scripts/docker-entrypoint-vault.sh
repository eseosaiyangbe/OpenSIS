#!/bin/sh
set -e

SECRETS_FILE="${APP_SECRETS_FILE:-/run/secrets/app.env}"
WAIT_TIMEOUT="${APP_SECRETS_WAIT_TIMEOUT:-60}"

echo "[entrypoint] Waiting for Vault-rendered application secrets..."

timeout="$WAIT_TIMEOUT"

while [ $timeout -gt 0 ]; do
  if [ -s "$SECRETS_FILE" ] && grep -q DB_HOST "$SECRETS_FILE"; then
    break
  fi

  sleep 2
  timeout=$((timeout-2))
done

if [ $timeout -eq 0 ]; then
  echo "[entrypoint] ERROR: Vault secrets not available after ${WAIT_TIMEOUT} seconds."
  exit 1
fi

echo "[entrypoint] Secrets file detected."

# Export environment variables
set -a
. "$SECRETS_FILE"
set +a

# Validate required variables
: "${DB_HOST:?Missing DB_HOST}"
: "${DB_PORT:?Missing DB_PORT}"
: "${MYSQL_DATABASE:?Missing MYSQL_DATABASE}"
: "${MYSQL_USER:?Missing MYSQL_USER}"
: "${MYSQL_PASSWORD:?Missing MYSQL_PASSWORD}"

echo "[entrypoint] Environment successfully loaded."

exec docker-php-entrypoint apache2-foreground
