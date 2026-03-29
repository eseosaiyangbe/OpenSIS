# Vault Setup - Fixes Applied

## Summary of Changes

Your Vault setup was hanging due to **5 critical issues** with missing directories, race conditions, and lack of dependency ordering. All issues have been fixed.

---

## Issues Fixed

### 1. ✅ Missing AppRole Credential Directories
**Fixed:** Created required directories:
- `./vault-agent/db-approle/` (with placeholder role_id and secret_id files)
- `./vault-agent/app-approle/` (with placeholder role_id and secret_id files)

**Why:** Vault agents expect these credentials to exist on startup. Bootstrap script populates them.

---

### 2. ✅ Wrong Startup Sequence - No Health Check
**Fixed in docker-compose.yaml:**
```yaml
# BEFORE (Wrong):
vault-bootstrap:
  depends_on:
    vault:
      condition: service_started  # ❌ Too early!

# AFTER (Correct):
vault-bootstrap:
  depends_on:
    vault:
      condition: service_healthy   # ✅ Wait for Vault to be ready
```

**Impact:** Vault is now guaranteed to be initialized and accepting commands before bootstrap runs.

---

### 3. ✅ Vault Agents Started Before Credentials Ready
**Fixed in docker-compose.yaml:**
```yaml
# BEFORE (Wrong):
vault-agent-db:
  depends_on:
    vault:
      condition: service_healthy
    # No dependency on bootstrap! ❌

# AFTER (Correct):
vault-agent-db:
  depends_on:
    vault:
      condition: service_healthy
    vault-bootstrap:
      condition: service_completed_successfully  # ✅ Credentials must exist first!

# Same fix applied to vault-agent-app
```

**Impact:** Agents now wait for bootstrap to finish creating credentials before starting.

---

### 4. ✅ Timeout Hangs in bootstrap.sh
**Fixed in scripts/bootstrap.sh:**
```bash
# BEFORE (Could hang forever):
until vault status -format=json 2>/dev/null | jq . >/dev/null 2>&1; do
  sleep 2
done

# AFTER (Max 5-minute timeout):
RETRY=0
MAX_RETRIES=150  # ~5 minutes with 2-second sleep
until vault status -format=json 2>/dev/null | jq . >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  if [ $RETRY -gt $MAX_RETRIES ]; then
    echo "ERROR: Vault not responding after 5 minutes. Exiting."
    exit 1
  fi
  sleep 2
done
```

**Impact:** If Vault fails to start, bootstrap exits cleanly with error message instead of hanging.

---

### 5. ✅ Missing Error Handling & Validation
**Fixed in both bootstrap.sh and seed.sh:**
- Added explicit error checks for all file operations (`-s` test for non-empty files)
- Added checks for required environment variables
- Added validation that credentials were written before continuing
- Added better status logging at each step
- File write operations now have `|| exit 1` guards

**Examples:**
```bash
# BEFORE (Silent failures):
echo "$INIT_OUTPUT" | jq -r '.root_token' > "$DATA_DIR/root_token"

# AFTER (Explicit error handling):
echo "$INIT_OUTPUT" | jq -r '.root_token' > "$DATA_DIR/root_token" || {
  echo "ERROR: Failed to write root_token"
  exit 1
}

# Verification at end:
if [ ! -s /approle/db-approle/role_id ] || [ ! -s /approle/db-approle/secret_id ]; then
  echo "ERROR: DB AppRole credentials not properly written"
  exit 1
fi
```

---

## Complete Startup Sequence (Now Fixed)

```
1. vault-volume-init ✓
   └─ Sets permissions on vault_data volume

2. vault-agent-init ✓
   └─ Sets permissions on vault-agent bind mount

3. vault service starts
   └─ Listens on localhost:8200 (unsealed on first start)

4. Vault healthcheck passes (condition: service_healthy)
   └─ Now bootstrapping can safely begin

5. vault-bootstrap starts and runs bootstrap.sh
   ├─ Connects to Vault API
   ├─ Initializes Vault (if needed) → stores unseal_key and root_token
   ├─ Unseals Vault (if needed)
   ├─ Enables KV v2 secrets engine
   ├─ Enables AppRole auth method
   ├─ Writes policies (opensis-db, opensis-app)
   ├─ Creates AppRole roles (opensis-db, opensis-app)
   ├─ Generates role_id and secret_id → saves to /vault-agent/*/approle/
   └─ Exits with status 0 ✓

6. vault-seed starts and runs seed.sh
   ├─ Loads root_token from vault_data
   ├─ Verifies Vault is initialized and unsealed
   ├─ Seeds kv/dev/opensis-db secret
   ├─ Seeds kv/dev/opensis-app secret
   └─ Exits with status 0 ✓

7. vault-agent-db starts (NOW credentials exist!)
   ├─ Reads role_id from /vault/approle/role_id
   ├─ Reads secret_id from /vault/approle/secret_id
   ├─ Authenticates to Vault via AppRole
   ├─ Renders db.env.tpl → /vault/secrets/db.env
   └─ Stays running, watches for secret changes

8. vault-agent-app starts (credentials ready)
   ├─ Reads role_id and secret_id
   ├─ Authenticates to Vault
   ├─ Renders app.env.tpl → /vault/secrets/app.env
   └─ Stays running

9. opensis-db service
   ├─ Depends on vault-agent-db: service_started
   └─ Starts MariaDB

10. opensis-ui application
    ├─ Depends on opensis-db: service_healthy
    ├─ Depends on vault-agent-app: service_started
    └─ Starts PHP/Apache application
```

---

## How to Test the Fix

### Test 1: Clean Start
```bash
cd /home/theinventor/Desktop/devops/devopseasylearning/Dev_test2

# Remove old volumes to simulate fresh start
docker-compose down -v

# Start the stack
docker-compose up --build

# Expected output (watch the logs):
# vault-volume-init:     [complete]
# vault-agent-init:      [complete]
# vault:                 [listening on :8200, health checks pass]
# vault-bootstrap:       [runs to completion in 5-10 seconds]
# vault-seed:            [completes successfully]
# vault-agent-db:        [starts and authenticates]
# vault-agent-app:       [starts and authenticates]
# opensis-db:            [starts and becomes healthy]
# opensis-ui:            [starts successfully]
```

### Test 2: Monitor Bootstrap Status
```bash
# In another terminal, watch bootstrap logs
docker logs -f vault-bootstrap

# You should see:
# Waiting for Vault to become reachable...
# Vault is reachable.
# Vault status: initialized=true sealed=false
# Loading policies...
# Generating AppRole credentials...
# Vault bootstrap completed successfully.
```

### Test 3: Verify Agent Credentials
```bash
# Check if agents got their credentials
docker exec vault-agent-db cat /vault/approle/role_id
docker exec vault-agent-app cat /vault/approle/role_id

# Should output non-empty role IDs (32+ chars)
```

### Test 4: Check Secrets Were Seeded
```bash
# Access Vault UI at http://localhost:8200
# Login with root token from: docker exec vault cat /vault/data/root_token

# Or check via CLI:
docker exec vault vault login -method=token token=$(docker exec vault cat /vault/data/root_token) && \
  docker exec vault vault kv list kv/dev

# Should output:
# Keys
# ----
# opensis-app
# opensis-db
```

---

## If Issues Persist

### Symptom: vault-bootstrap still hanging
**Check:**
```bash
docker logs vault-bootstrap
# Look for timeout error (should exit after 5 min now)
# If in loop without timeout, try: docker-compose restart vault-bootstrap
```

### Symptom: vault-agent-db/app won't start
**Check:**
```bash
docker logs vault-agent-db
# If it says "secret_id_file_path ... not found"
# The bootstrap.sh failed silently
# Check: docker logs vault-bootstrap --tail 50
```

### Symptom: Database/App won't start
**Check:**
```bash
docker logs opensis-ui
# If environment variables missing, vault-agent-app failed to render template
# Verify AppRole auth worked: docker logs vault-agent-app
```

### Debug: Run bootstrap manually
```bash
# If you want to manually test the bootstrap script:
docker exec vault-bootstrap /bin/sh -c '/bootstrap.sh'
```

---

## Files Changed

1. **docker-compose.yaml**
   - Line 96: Changed `vault: condition: service_started` → `service_healthy`
   - Line 145-146: Added `vault-bootstrap: condition: service_completed_successfully` to vault-agent-db
   - Line 177-178: Added `vault-bootstrap: condition: service_completed_successfully` to vault-agent-app

2. **scripts/bootstrap.sh**
   - Added `RETRY` counter with 150 max retries (5-minute timeout)
   - Added error handling with `|| { echo "ERROR: ..."; exit 1; }` throughout
   - Added file existence and size validation (`[ ! -s file ]` checks)
   - Added better status messages with initialization/sealed status
   - Added policy file existence checks before loading

3. **scripts/seed.sh**
   - Added retry logic with 60-second max timeout
   - Added validation of required environment variables
   - Added token verification (`vault token lookup`)
   - Added post-write verification of secrets
   - Added detailed status logging

4. **New directories created:**
   - `vault-agent/db-approle/` (with placeholder files: role_id, secret_id)
   - `vault-agent/app-approle/` (with placeholder files: role_id, secret_id)

---

## Root Cause Summary

The core issue was a **missing link in the initialization chain**:

- Bootstrap needed to create AppRole credentials in `/vault-agent/*/approle/`
- Vault agents needed these credentials to authenticate
- But agents were starting before bootstrap finished (no dependency)
- And directories didn't exist, so bootstrap would fail silently

Plus missing error handling made diagnostics impossible.

✅ All fixed. Your stack should now start cleanly.
