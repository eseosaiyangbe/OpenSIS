#!/bin/sh
set -e

export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"

DATA_DIR="/vault/data"
DB_APPROLE_DIR="${DB_APPROLE_DIR:-/approle/db-approle}"
APP_APPROLE_DIR="${APP_APPROLE_DIR:-/approle/app-approle}"
RETRY=0
MAX_RETRIES=150  # ~5 minutes with 2-second sleep

echo "Waiting for Vault to become reachable..."

# Use Vault CLI instead of curl (correct approach)
# Added timeout/retry logic to prevent infinite hangs
until vault status -format=json 2>/dev/null | jq . >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  if [ $RETRY -gt $MAX_RETRIES ]; then
    echo "ERROR: Vault not responding after 5 minutes. Exiting."
    exit 1
  fi
  sleep 2
done

echo "Vault is reachable."

INITIALIZED=$(vault status -format=json | jq -r '.initialized')
SEALED=$(vault status -format=json | jq -r '.sealed')

echo "Vault status: initialized=$INITIALIZED sealed=$SEALED"

# ---------------------------------------------------
# Initialize Vault (only once)
# ---------------------------------------------------
if [ "$INITIALIZED" = "false" ]; then
  echo "Initializing Vault..."

  INIT_OUTPUT=$(vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json)

  echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]' > "$DATA_DIR/unseal_key" || {
    echo "ERROR: Failed to write unseal_key"
    exit 1
  }
  echo "$INIT_OUTPUT" | jq -r '.root_token' > "$DATA_DIR/root_token" || {
    echo "ERROR: Failed to write root_token"
    exit 1
  }
  echo "Vault initialized successfully."
fi

UNSEAL_KEY=$(cat "$DATA_DIR/unseal_key") || {
  echo "ERROR: Cannot read unseal_key from $DATA_DIR"
  exit 1
}
ROOT_TOKEN=$(cat "$DATA_DIR/root_token") || {
  echo "ERROR: Cannot read root_token from $DATA_DIR"
  exit 1
}

export VAULT_TOKEN="$ROOT_TOKEN"

# ---------------------------------------------------
# Unseal if needed
# ---------------------------------------------------
SEALED=$(vault status -format=json | jq -r '.sealed')

if [ "$SEALED" = "true" ]; then
  echo "Unsealing Vault..."
  vault operator unseal "$UNSEAL_KEY" || {
    echo "ERROR: Failed to unseal Vault"
    exit 1
  }
  echo "Vault unsealed successfully."
fi

echo "Vault is initialized and unsealed."

# ---------------------------------------------------
# Enable engines (idempotent)
# ---------------------------------------------------
vault secrets enable -path=kv kv-v2 2>/dev/null || true
vault auth enable approle 2>/dev/null || true

# ---------------------------------------------------
# Load policies
# ---------------------------------------------------
echo "Loading policies..."

if [ ! -f /policies/opensis-db-policy.hcl ]; then
  echo "ERROR: Policy file not found: /policies/opensis-db-policy.hcl"
  exit 1
fi

if [ ! -f /policies/opensis-app-policy.hcl ]; then
  echo "ERROR: Policy file not found: /policies/opensis-app-policy.hcl"
  exit 1
fi

vault policy write opensis-db /policies/opensis-db-policy.hcl || {
  echo "ERROR: Failed to write opensis-db policy"
  exit 1
}
vault policy write opensis-app /policies/opensis-app-policy.hcl || {
  echo "ERROR: Failed to write opensis-app policy"
  exit 1
}
echo "Policies loaded successfully."

# ---------------------------------------------------
# Create AppRoles (idempotent)
# ---------------------------------------------------
echo "Creating AppRoles..."

vault write auth/approle/role/opensis-db \
  token_policies="opensis-db" \
  token_ttl="1h" \
  token_max_ttl="4h" 2>/dev/null || true

vault write auth/approle/role/opensis-app \
  token_policies="opensis-app" \
  token_ttl="1h" \
  token_max_ttl="4h" 2>/dev/null || true

echo "AppRoles created."

# ---------------------------------------------------
# Generate credentials
# ---------------------------------------------------
echo "Generating AppRole credentials..."

mkdir -p "$DB_APPROLE_DIR" || {
  echo "ERROR: Failed to create $DB_APPROLE_DIR directory"
  exit 1
}
mkdir -p "$APP_APPROLE_DIR" || {
  echo "ERROR: Failed to create $APP_APPROLE_DIR directory"
  exit 1
}

vault read -format=json auth/approle/role/opensis-db/role-id \
  | jq -r '.data.role_id' > "$DB_APPROLE_DIR/role_id" || {
  echo "ERROR: Failed to write db-approle role_id"
  exit 1
}

vault write -f -format=json auth/approle/role/opensis-db/secret-id \
  | jq -r '.data.secret_id' > "$DB_APPROLE_DIR/secret_id" || {
  echo "ERROR: Failed to write db-approle secret_id"
  exit 1
}

vault read -format=json auth/approle/role/opensis-app/role-id \
  | jq -r '.data.role_id' > "$APP_APPROLE_DIR/role_id" || {
  echo "ERROR: Failed to write app-approle role_id"
  exit 1
}

vault write -f -format=json auth/approle/role/opensis-app/secret-id \
  | jq -r '.data.secret_id' > "$APP_APPROLE_DIR/secret_id" || {
  echo "ERROR: Failed to write app-approle secret_id"
  exit 1
}

# Verify credentials were written
if [ ! -s "$DB_APPROLE_DIR/role_id" ] || [ ! -s "$DB_APPROLE_DIR/secret_id" ]; then
  echo "ERROR: DB AppRole credentials not properly written"
  exit 1
fi

if [ ! -s "$APP_APPROLE_DIR/role_id" ] || [ ! -s "$APP_APPROLE_DIR/secret_id" ]; then
  echo "ERROR: App AppRole credentials not properly written"
  exit 1
fi

echo "Vault bootstrap completed successfully."
