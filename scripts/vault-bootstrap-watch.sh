#!/bin/sh
set -eu

RECONCILE_INTERVAL="${VAULT_BOOTSTRAP_RECONCILE_INTERVAL:-30}"
FAILURE_BACKOFF="${VAULT_BOOTSTRAP_FAILURE_BACKOFF:-5}"

echo "[vault-bootstrap-watch] Starting Vault reconcile loop."

while true; do
  if /bootstrap.sh; then
    echo "[vault-bootstrap-watch] Vault reconcile succeeded. Sleeping ${RECONCILE_INTERVAL}s."
    sleep "$RECONCILE_INTERVAL"
  else
    echo "[vault-bootstrap-watch] Vault reconcile failed. Retrying in ${FAILURE_BACKOFF}s."
    sleep "$FAILURE_BACKOFF"
  fi
done
