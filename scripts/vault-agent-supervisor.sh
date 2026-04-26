#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: vault-agent-supervisor.sh <config_path> <secrets_file> [required_pattern]" >&2
  exit 64
fi

CONFIG_PATH="$1"
SECRETS_FILE="$2"
REQUIRED_PATTERN="${3:-}"
WAIT_TIMEOUT="${VAULT_AGENT_INITIAL_RENDER_TIMEOUT:-120}"
SLEEP_INTERVAL="${VAULT_AGENT_RENDER_POLL_INTERVAL:-2}"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "[vault-agent-supervisor] ERROR: config not found: $CONFIG_PATH" >&2
  exit 66
fi

rendered() {
  if [ ! -s "$SECRETS_FILE" ]; then
    return 1
  fi

  if [ -n "$REQUIRED_PATTERN" ] && ! grep -q "$REQUIRED_PATTERN" "$SECRETS_FILE"; then
    return 1
  fi

  return 0
}

shutdown() {
  if [ -n "${child_pid:-}" ] && kill -0 "$child_pid" 2>/dev/null; then
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
}

trap shutdown INT TERM EXIT

echo "[vault-agent-supervisor] Starting Vault agent with config $CONFIG_PATH"
vault agent -config="$CONFIG_PATH" &
child_pid="$!"

elapsed=0
while kill -0 "$child_pid" 2>/dev/null; do
  if rendered; then
    echo "[vault-agent-supervisor] Initial secret render detected at $SECRETS_FILE"
    wait "$child_pid"
    exit $?
  fi

  if [ "$elapsed" -ge "$WAIT_TIMEOUT" ]; then
    echo "[vault-agent-supervisor] ERROR: secret render did not complete within ${WAIT_TIMEOUT}s" >&2
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    exit 1
  fi

  sleep "$SLEEP_INTERVAL"
  elapsed=$((elapsed + SLEEP_INTERVAL))
done

wait "$child_pid"
