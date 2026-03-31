# Vault Setup - Quick Troubleshooting Guide

Use this when testing the fixed Vault setup.

---

## Quick Test Commands

```bash
cd /home/theinventor/Desktop/devops/devopseasylearning/OpenSIS

# Clean start (removes old data)
docker-compose down -v && docker-compose up --build

# Or gradual start to watch progress
docker-compose down -v
docker-compose up vault-volume-init
docker-compose up vault-agent-init
docker-compose up vault
docker-compose up vault-bootstrap
docker-compose up vault-seed
docker-compose up
```

---

## Checking Each Stage

### Stage 1: Volume Permissions
```bash
# Should complete immediately
docker logs vault-volume-init
# Expected: No output (Alpine, quick chown)

docker logs vault-agent-init  
# Expected: No output
```

### Stage 2: Vault Server Ready
```bash
# Check Vault is listening and healthy
curl -s http://localhost:8200/v1/sys/health | jq .
# Expected: Returns JSON with "sealed_status"

docker logs vault
# Watch for: "core: server started"
```

### Stage 3: Bootstrap Initialization
```bash
# Watch bootstrap progress
docker logs -f vault-bootstrap

# Expected pattern:
# Waiting for Vault to become reachable...
# Vault is reachable.
# Vault status: initialized=true sealed=false
# Loading policies...
# Generating AppRole credentials...
# Vault bootstrap completed successfully.
```

### Stage 4: Seed Database Secrets
```bash
docker logs vault-seed

# Expected:
# Waiting for Vault to be ready...
# Vault is ready.
# Seeding Vault secrets (idempotent)...
# Creating DB secrets...
# Creating App secrets...
# Vault seeding completed successfully.
```

### Stage 5: Vault Agents Start
```bash
docker logs vault-agent-db
docker logs vault-agent-app

# Expected: No errors, just startup messages about templating
# The agents run in background, watching for secret changes
```

---

## Common Issues & Fixes

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Missing credentials** | vault-agent-db/app exits | Check `docker logs vault-bootstrap` for errors |
| **Timeout waiting for Vault** | bootstrap hangs then exits | Wait 5 min, check Vault logs: `docker logs vault` |
| **Can't write to /vault/approle** | bootstrap fails with permission error | Verify directories exist: `ls -la vault-agent/*/approle/` |
| **Vault won't unseal** | bootstrap reports sealed=true | Check unseal_key file: `docker exec vault cat /vault/data/unseal_key` |
| **Secrets not found** | vault-agent-app fails template render | Check seed completed: `docker logs vault-seed` |

---

## Manual Testing

### Get Root Token
```bash
docker exec vault cat /vault/data/root_token
# Save this, you can login to Vault UI at http://localhost:8200
```

### List Secrets
```bash
TOKEN=$(docker exec vault cat /vault/data/root_token)
docker exec -e VAULT_TOKEN="$TOKEN" vault \
  vault kv list kv/dev
# Expected output:
# Keys
# ----
# opensis-app
# opensis-db
```

### Read DB Credentials from Within Container
```bash
docker exec vault-agent-db cat /vault/secrets/db.env
# Expected output (rendered from template):
# MYSQL_ROOT_PASSWORD=your_root_pass
# MYSQL_DATABASE=opensis
# MYSQL_USER=opensis
# MYSQL_PASSWORD=your_password
```

### Test AppRole Authentication
```bash
# Get the role_id and secret_id that bootstrap created
ROLE_ID=$(cat vault-agent/db-approle/role_id)
SECRET_ID=$(cat vault-agent/db-approle/secret_id)

echo "Role ID: $ROLE_ID"
echo "Secret ID: $SECRET_ID"

# Try to authenticate with them
docker exec vault vault write auth/approle/login \
  role_id="$ROLE_ID" \
  secret_id="$SECRET_ID"
  
# Should reply with a valid token
```

---

## Stack Startup Order (Verified)

```
✅ vault-volume-init → completes
✅ vault-agent-init → completes  
✅ vault → starts and becomes healthy (healthcheck passes)
✅ vault-bootstrap → runs bootstrap.sh (creates credentials)
✅ vault-seed → runs seed.sh (injects secrets)
✅ vault-agent-db → auto-auth with AppRole, renders db.env
✅ vault-agent-app → auto-auth with AppRole, renders app.env
✅ opensis-db → starts, reads credentials from vault-agent-db
✅ opensis-ui → starts, reads credentials from vault-agent-app
```

---

## Clean Up / Reset

### Restart Just Vault Stack
```bash
docker-compose down
docker volume rm vault_data
docker-compose up vault-volume-init vault-agent-init vault vault-bootstrap vault-seed
```

### Full Clean Reset  
```bash
docker-compose down -v
rm -f vault-agent/*/approle/{role_id,secret_id}
docker-compose up
```

### Check Current State
```bash
# All containers running?
docker-compose ps

# All services healthy?
docker-compose ps | grep -E "healthy|Up"

# All volumes mounted?
docker inspect vault-bootstrap -f '{{json .Mounts}}' | jq .
```

---

## Logs to Monitor

Watch these in separate terminals:

```bash
# Terminal 1: Bootstrap
docker logs -f vault-bootstrap

# Terminal 2: Vault Server  
docker logs -f vault

# Terminal 3: Seed
docker logs -f vault-seed

# Terminal 4: Database Agent
docker logs -f vault-agent-db

# Terminal 5: App Agent
docker logs -f vault-agent-app

# Terminal 6: All services
docker-compose logs -f
```

---

## Expected Timing

- **Total startup**: 30-45 seconds (from `docker-compose up` to all services healthy)
- **Vault init + unseal**: 2-3 seconds
- **Bootstrap policies + AppRoles**: 3-5 seconds
- **Seed secrets**: 2-3 seconds  
- **Vault agents auto-auth**: 1-2 seconds each
- **Database health check pass**: 10-15 seconds (MariaDB startup)
- **Application startup**: 5-10 seconds

If taking longer, check logs for "Waiting for..." messages.

---

## Success Checklist

- [ ] `docker-compose ps` shows all containers in "Up" state
- [ ] `docker logs vault-bootstrap | grep "completed successfully"`
- [ ] `docker logs vault-seed | grep "completed successfully"`
- [ ] `curl -s http://localhost:8200/v1/sys/health | jq .sealed` returns `false`
- [ ] `curl -s http://localhost:8080/` returns 200 (app is accessible)
- [ ] `docker exec opensis-ui cat /run/secrets/app.env` shows DB credentials

If all ✅, your Vault setup is working correctly!
