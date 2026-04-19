#!/bin/sh
set -e

export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
DATA_DIR="/vault/data"

echo "Waiting for Vault to be ready..."

# Wait until Vault is initialized AND unsealed
RETRY=0
MAX_RETRIES=60  # ~2 minutes
until vault status -format=json >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  if [ $RETRY -gt $MAX_RETRIES ]; then
    echo "ERROR: Vault not responding after 2 minutes"
    exit 1
  fi
  echo "Waiting for Vault... (attempt $RETRY/$MAX_RETRIES)"
  sleep 2
done

SEALED=$(vault status -format=json | jq -r '.sealed')
INITIALIZED=$(vault status -format=json | jq -r '.initialized')

echo "Vault status: initialized=$INITIALIZED sealed=$SEALED"

if [ "$INITIALIZED" != "true" ] || [ "$SEALED" != "false" ]; then
  echo "FATAL: Vault not properly initialized (initialized=$INITIALIZED sealed=$SEALED)"
  exit 1
fi

echo "Vault is ready."

# Load root token
if [ ! -f "$DATA_DIR/root_token" ]; then
  echo "ERROR: root_token not found at $DATA_DIR/root_token"
  exit 1
fi

VAULT_TOKEN=$(cat "$DATA_DIR/root_token") || {
  echo "ERROR: Failed to read root_token"
  exit 1
}
export VAULT_TOKEN

echo "Seeding Vault secrets (idempotent)..."

# Verify we can connect with the token
vault token lookup >/dev/null 2>&1 || {
  echo "ERROR: Cannot authenticate to Vault with root token"
  exit 1
}

# ---------------------------------------------------
# Seed DB secrets (only if not exists)
# ---------------------------------------------------
if ! vault kv get kv/dev/opensis-db >/dev/null 2>&1; then
  echo "Creating DB secrets..."

  if [ -z "$MYSQL_ROOT_PASSWORD" ] || [ -z "$MYSQL_DATABASE" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ]; then
    echo "ERROR: Missing required environment variables (MYSQL_ROOT_PASSWORD, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD)"
    exit 1
  fi

  vault kv put kv/dev/opensis-db \
    MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    MYSQL_DATABASE="$MYSQL_DATABASE" \
    MYSQL_USER="$MYSQL_USER" \
    MYSQL_PASSWORD="$MYSQL_PASSWORD" || {
    echo "ERROR: Failed to write DB secrets to Vault"
    exit 1
  }
  echo "DB secrets created successfully."
else
  echo "DB secrets already exist. Skipping."
fi

# ---------------------------------------------------
# Seed App secrets
# ---------------------------------------------------
if ! vault kv get kv/dev/opensis-app >/dev/null 2>&1; then
  echo "Creating App secrets..."

  if [ -z "$MYSQL_DATABASE" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ]; then
    echo "ERROR: Missing required environment variables for app secrets"
    exit 1
  fi

  vault kv put kv/dev/opensis-app \
    MYSQL_DATABASE="$MYSQL_DATABASE" \
    MYSQL_USER="$MYSQL_USER" \
    MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    DB_HOST="opensis-db" \
    DB_PORT="3306" || {
    echo "ERROR: Failed to write App secrets to Vault"
    exit 1
  }
  echo "App secrets created successfully."
else
  echo "App secrets already exist. Skipping."
fi

# Verify secrets were written
echo "Verifying secrets..."
vault kv get kv/dev/opensis-db >/dev/null || {
  echo "ERROR: DB secrets not found after writing"
  exit 1
}
vault kv get kv/dev/opensis-app >/dev/null || {
  echo "ERROR: App secrets not found after writing"
  exit 1
}

echo "Vault seeding completed successfully."