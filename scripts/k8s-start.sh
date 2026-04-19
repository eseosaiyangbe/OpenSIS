#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-start.sh [options]

Start the local k3s Kubernetes cluster and run basic recovery checks.

Options:
  --unseal-vault        Unseal Vault using vault/init/init.txt after k3s starts
  --skip-stale-cleanup  Do not delete stale Kubernetes pods stuck in Unknown
  --smoke              Run dev and prod smoke checks after recovery
  -h, --help           Show this help message

Examples:
  ./scripts/k8s-start.sh
  ./scripts/k8s-start.sh --unseal-vault
  ./scripts/k8s-start.sh --unseal-vault --smoke
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1"
    exit 1
  fi
}

require_repo_root() {
  if [[ ! -f "k8s/README.md" || ! -d "scripts" ]]; then
    echo "ERROR: Run this script from the repository root."
    exit 1
  fi
}

run_systemctl() {
  local action="$1"

  if systemctl "$action" k3s; then
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    return 1
  fi

  echo "Direct systemctl ${action} failed; retrying with sudo..."
  sudo systemctl "$action" k3s
}

wait_for_api() {
  local timeout="${1:-180}"
  local elapsed=0

  echo "Waiting for Kubernetes API..."
  until kubectl get nodes >/dev/null 2>&1; do
    if [[ "$elapsed" -ge "$timeout" ]]; then
      echo "ERROR: Kubernetes API did not become available within ${timeout}s."
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

wait_for_node_ready() {
  echo "Waiting for node/devbox to become Ready..."
  kubectl wait --for=condition=Ready node/devbox --timeout=180s
}

vault_status() {
  kubectl exec -n vault vault-0 -- sh -lc \
    'export VAULT_ADDR=https://vault.vault.svc:8200 VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault status'
}

wait_for_vault_running() {
  local timeout="${1:-120}"
  local elapsed=0
  local phase

  echo "Waiting for vault/vault-0 pod to be Running..."
  while true; do
    phase="$(kubectl get pod -n vault vault-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$phase" == "Running" ]]; then
      return 0
    fi

    if [[ "$elapsed" -ge "$timeout" ]]; then
      echo "ERROR: vault/vault-0 did not reach Running phase within ${timeout}s."
      return 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done
}

unseal_vault() {
  local init_file="vault/init/init.txt"

  if ! kubectl get pod -n vault vault-0 >/dev/null 2>&1; then
    echo "Vault pod not found yet; skipping Vault unseal."
    return 0
  fi

  wait_for_vault_running 120

  echo "Checking Vault seal status..."
  if vault_status >/tmp/opensis-vault-status.$$ 2>/tmp/opensis-vault-status.err.$$; then
    cat /tmp/opensis-vault-status.$$
    rm -f /tmp/opensis-vault-status.$$ /tmp/opensis-vault-status.err.$$
    return 0
  fi

  if grep -q 'Sealed[[:space:]]*true' /tmp/opensis-vault-status.$$ 2>/dev/null; then
    if [[ ! -f "$init_file" ]]; then
      echo "ERROR: Vault is sealed, but $init_file was not found."
      echo "Unseal manually with: kubectl exec -n vault vault-0 -- vault operator unseal <key>"
      rm -f /tmp/opensis-vault-status.$$ /tmp/opensis-vault-status.err.$$
      return 1
    fi

    echo "Vault is sealed. Unsealing with the first 3 unseal keys from $init_file..."
    for n in 1 2 3; do
      local key
      key="$(awk -F': ' -v n="$n" '$1 == "Unseal Key " n {print $2}' "$init_file")"
      if [[ -z "$key" ]]; then
        echo "ERROR: Missing Unseal Key $n in $init_file."
        rm -f /tmp/opensis-vault-status.$$ /tmp/opensis-vault-status.err.$$
        return 1
      fi
      kubectl exec -n vault vault-0 -- sh -lc \
        'export VAULT_ADDR=https://vault.vault.svc:8200 VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault operator unseal "$1" >/dev/null' \
        sh "$key"
    done

    vault_status
  else
    cat /tmp/opensis-vault-status.$$ 2>/dev/null || true
    cat /tmp/opensis-vault-status.err.$$ 2>/dev/null || true
  fi

  rm -f /tmp/opensis-vault-status.$$ /tmp/opensis-vault-status.err.$$
}

delete_stale_unknown_pods() {
  local stale_pods
  stale_pods="$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4=="Unknown" {print $1, $2}')"

  if [[ -z "$stale_pods" ]]; then
    echo "No stale Unknown pods found."
    return 0
  fi

  echo "Deleting stale Unknown pods so controllers can recreate them..."
  while read -r namespace pod; do
    [[ -z "$namespace" || -z "$pod" ]] && continue
    echo "Deleting stale pod ${namespace}/${pod}"
    kubectl delete pod -n "$namespace" "$pod" --wait=false
  done <<<"$stale_pods"
}

show_status() {
  echo
  echo "Cluster:"
  kubectl get nodes -o wide

  echo
  echo "Argo CD applications:"
  kubectl get applications -n argocd 2>/dev/null || true

  echo
  echo "Non-running pods:"
  kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null || true
}

main() {
  local should_unseal_vault=0
  local cleanup_stale_pods=1
  local run_smoke=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --unseal-vault)
        should_unseal_vault=1
        shift
        ;;
      --skip-stale-cleanup)
        cleanup_stale_pods=0
        shift
        ;;
      --smoke)
        run_smoke=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown option: $1"
        echo
        usage
        exit 1
        ;;
    esac
  done

  require_repo_root
  require_command kubectl
  require_command systemctl

  echo "Starting k3s..."
  run_systemctl start

  wait_for_api 180
  wait_for_node_ready

  if [[ "$should_unseal_vault" -eq 1 ]]; then
    unseal_vault
  else
    echo
    echo "Vault note: if Vault is sealed after startup, run:"
    echo "  ./scripts/k8s-start.sh --unseal-vault"
  fi

  if [[ "$cleanup_stale_pods" -eq 1 ]]; then
    delete_stale_unknown_pods
  fi

  show_status

  if [[ "$run_smoke" -eq 1 ]]; then
    echo
    echo "Running smoke checks..."
    ./scripts/smoke-dev.sh
    ./scripts/smoke-prod.sh
  fi
}

main "$@"
