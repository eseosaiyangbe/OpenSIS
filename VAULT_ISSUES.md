# Vault Setup Issues & Root Causes

## Critical Issues Found

### 1. **Missing AppRole Credential Directories** ⚠️ BLOCKING
**Problem:** The bootstrap script writes AppRole credentials to directories that don't exist:
```
/approle/db-approle/role_id
/approle/db-approle/secret_id
/approle/app-approle/role_id
/approle/app-approle/secret_id
```

**Evidence:**
- `vault-agent/db-approle/` directory doesn't exist
- `vault-agent/app-approle/` directory doesn't exist
- Vault agents (vault-agent-db, vault-agent-app) expect these files to exist at startup

**Impact:** Vault agents fail immediately because they can't find the AppRole credentials needed for authentication.

---

### 2. **No Healthcheck Before Vault-Bootstrap Starts** 
**Problem:** In docker-compose.yaml, `vault-bootstrap` only depends on `vault: service_started`, not `service_healthy`
```yaml
depends_on:
  vault:
    condition: service_started  # ❌ Should be service_healthy
```

**Impact:** Bootstrap runs before Vault is actually ready to accept commands, causing timeouts or failures in initialization.

**Correct dependency:** Should be `service_healthy` to match the healthcheck defined on the vault service.

---

### 3. **Vault Agent Startup Race Condition**
**Problem:** Vault agents reference `/vault/approle/role_id` and `/vault/approle/secret_id` files that are created AFTER they start:
- `vault-bootstrap` runs and creates credentials
- But `vault-agent-db` and `vault-agent-app` launch simultaneously, before credentials exist

**Evidence:** In agent-db.hcl and agent-app.hcl:
```
role_id_file_path   = "/vault/approle/role_id"
secret_id_file_path = "/vault/approle/secret_id"
```

These files are only created by the bootstrap script after Vault is ready.

**Impact:** Vault agents crash trying to authenticate with non-existent credentials.

---

### 4. **Missing Initial Directory Creation in Bootstrap**
**Problem:** The bootstrap script (`scripts/bootstrap.sh`) creates `/approle/db-approle/` and `/approle/app-approle/` directories:
```bash
mkdir -p /approle/db-approle
mkdir -p /approle/app-approle
```

But if the parent `/vault-agent/` volume has restrictive permissions from `vault-agent-init`, this may fail.

**Map of volume mounts:**
```
Docker Path         → Host Path
/approle            → ./vault-agent
/approle/db-approle → ./vault-agent/db-approle  (MUST EXIST)
/approle/app-approle→ ./vault-agent/app-approle (MUST EXIST)
```

---

### 5. **Vault Agents Waiting on Wrong Dependencies**
**Problem:** `vault-agent-db` and `vault-agent-app` depend on `vault: service_healthy` BUT they should also depend on `vault-bootstrap: service_completed_successfully`

Current state:
```yaml
vault-agent-db:
  depends_on:
    vault:
      condition: service_healthy  # Only waits for Vault, not for credentials
```

They launch before bootstrap finishes creating credentials → immediate auth failure.

---

## Startup Sequence (Current - Broken)

```
1. vault-volume-init ✓ completes
2. vault-agent-init ✓ completes
3. vault starts
4. vault-bootstrap starts (⚠️ vault may not be ready yet)
   └─ Tries to initialize/unseal Vault
   └─ Creates AppRole credentials → /approle/db-approle/ & /approle/app-approle/
5. vault-agent-db starts (⚠️ BEFORE bootstrap finishes! No credentials!)
   └─ Looks for /vault/approle/role_id → NOT FOUND → CRASH/HANG
6. vault-agent-app starts (⚠️ Same problem)
7. vault-seed starts (depends on vault-bootstrap completed)
```

---

## Startup Sequence (Expected - Should Work)

```
1. vault-volume-init ✓ completes
2. vault-agent-init ✓ completes
3. vault starts
4. vault healthcheck succeeds (Vault is READY)
5. vault-bootstrap starts (NOW safe to initialize Vault)
   └─ Initializes/unseals Vault
   └─ Creates AppRoles
   └─ Writes credentials to /vault-agent/db-approle/ & /vault-agent/app-approle/
6. vault-bootstrap ✓ completes_successfully
7. vault-agent-db starts (NOW credentials exist!)
   └─ Reads role_id and secret_id successfully
8. vault-agent-app starts (Same)
9. vault-seed starts (Depends on bootstrap completion)
```

---

## Missing Prerequisites

These directories must exist BEFORE containerization:
```
./vault-agent/
├── db-approle/            ← MISSING
├── app-approle/           ← MISSING
├── db-config/             ✓ exists
├── db-secrets/            ✓ exists
├── db-templates/          ✓ exists
├── app-config/            ✓ exists
├── app-secrets/           ✓ exists
└── app-templates/         ✓ exists
```

---

## Additional Concerns

### Timeout Waiting for vault status
The bootstrap script uses:
```bash
until vault status -format=json 2>/dev/null | jq . >/dev/null 2>&1; do
  sleep 2
done
```

**Risk:** If Vault is slow to start or jq fails, this loops infinitely. Should add max retry counter:
```bash
RETRY=0
MAX_RETRIES=150  # ~5 minutes
until vault status -format=json 2>/dev/null | jq . >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  if [ $RETRY -gt $MAX_RETRIES ]; then
    echo "FATAL: Vault not responding after 5 minutes"
    exit 1
  fi
  sleep 2
done
```

### seed.sh Exit on Failure
The seed.sh script has `set -e` but exits on ANY error. If seeding fails midway, Vault is left in inconsistent state. Should either:
- Have retry logic
- Or use idempotent checks (which it does, but could be improved)
