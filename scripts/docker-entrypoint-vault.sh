#!/bin/sh
set -e

SECRETS_FILE="${APP_SECRETS_FILE:-/run/secrets/app.env}"
WAIT_TIMEOUT="${APP_SECRETS_WAIT_TIMEOUT:-180}"

echo "[entrypoint] Waiting for Vault-rendered application secrets..."

timeout="$WAIT_TIMEOUT"

while [ "$timeout" -gt 0 ]; do
  if [ -s "$SECRETS_FILE" ] && grep -q DB_HOST "$SECRETS_FILE"; then
    break
  fi

  sleep 2
  timeout=$((timeout-2))
done

if [ "$timeout" -eq 0 ]; then
  echo "[entrypoint] ERROR: Vault secrets not available after ${WAIT_TIMEOUT} seconds."
  exit 1
fi

echo "[entrypoint] Secrets file detected."

# Export environment variables
set -a
# shellcheck source=/dev/null
. "$SECRETS_FILE"
set +a

# Validate required variables
: "${DB_HOST:?Missing DB_HOST}"
: "${DB_PORT:?Missing DB_PORT}"
: "${MYSQL_DATABASE:?Missing MYSQL_DATABASE}"
: "${MYSQL_USER:?Missing MYSQL_USER}"
: "${MYSQL_PASSWORD:?Missing MYSQL_PASSWORD}"

SESSION_CONF_FILE="${PHP_SESSION_CONF_FILE:-/usr/local/etc/php/conf.d/zz-session-runtime.ini}"
: > "$SESSION_CONF_FILE"

if [ -n "${PHP_SESSION_SAVE_HANDLER:-}" ]; then
  echo "session.save_handler = ${PHP_SESSION_SAVE_HANDLER}" >> "$SESSION_CONF_FILE"
fi

if [ -n "${PHP_SESSION_SAVE_PATH:-}" ]; then
  echo "session.save_path = \"${PHP_SESSION_SAVE_PATH}\"" >> "$SESSION_CONF_FILE"
fi

if [ -n "${PHP_SESSION_COOKIE_SECURE:-}" ]; then
  echo "session.cookie_secure = ${PHP_SESSION_COOKIE_SECURE}" >> "$SESSION_CONF_FILE"
fi

if [ -n "${PHP_SESSION_COOKIE_SAMESITE:-}" ]; then
  echo "session.cookie_samesite = ${PHP_SESSION_COOKIE_SAMESITE}" >> "$SESSION_CONF_FILE"
fi

echo "[entrypoint] Environment successfully loaded."

exec docker-php-entrypoint apache2-foreground
