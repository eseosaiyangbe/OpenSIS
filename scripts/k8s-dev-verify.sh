#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-dev-verify.sh [options]

Run the OpenSIS k3s dev verification path against the current Kubernetes context.

Options:
  --hostname HOST  Override ingress hostname target (default: opensis.devops.local)
  -h, --help       Show this help message
EOF
}

HOSTNAME_OVERRIDE="opensis.devops.local"
PORT_FORWARD_PID=""
EXPORTER_RETRY_ATTEMPTS=12
EXPORTER_RETRY_DELAY_SECONDS=5

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  fi
}

retry_check() {
  local description="$1"
  shift

  local attempt=1
  while (( attempt <= EXPORTER_RETRY_ATTEMPTS )); do
    if "$@"; then
      return 0
    fi

    if (( attempt == EXPORTER_RETRY_ATTEMPTS )); then
      echo "ERROR: ${description} did not succeed after ${EXPORTER_RETRY_ATTEMPTS} attempts." >&2
      return 1
    fi

    echo "[opensis-k8s] ${description} not ready yet (attempt ${attempt}/${EXPORTER_RETRY_ATTEMPTS}); retrying in ${EXPORTER_RETRY_DELAY_SECONDS}s"
    sleep "${EXPORTER_RETRY_DELAY_SECONDS}"
    ((attempt++))
  done
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

require_command kubectl
require_command curl

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)
      HOSTNAME_OVERRIDE="${2:?Missing hostname value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

TRAEFIK_ADDR="$(kubectl get ingress -n opensis-dev opensis-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if [[ -z "${TRAEFIK_ADDR}" ]]; then
  TRAEFIK_ADDR="$(kubectl get ingress -n opensis-dev opensis-ui -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
fi

if [[ -z "${TRAEFIK_ADDR}" ]]; then
  echo "ERROR: Could not determine OpenSIS ingress address." >&2
  exit 1
fi

echo "[opensis-k8s] Traefik address: ${TRAEFIK_ADDR}"
echo "[opensis-k8s] Verifying Kubernetes objects"
kubectl get pods -n opensis-dev
kubectl get svc -n opensis-dev
kubectl get ingress -n opensis-dev

echo "[opensis-k8s] Verifying ingress endpoints"
http_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${HOSTNAME_OVERRIDE}" "http://${TRAEFIK_ADDR}/")"
if [[ "${http_code}" != "200" && "${http_code}" != "302" ]]; then
  echo "ERROR: Expected OpenSIS ingress to return HTTP 200 or 302, got ${http_code}." >&2
  exit 1
fi

echo "[opensis-k8s] Running end-to-end UI validation via port-forward"
kubectl port-forward -n opensis-dev svc/opensis-ui 38088:80 >/tmp/opensis-k8s-port-forward.log 2>&1 &
PORT_FORWARD_PID="$!"
PORT_FORWARD_READY="false"
for _ in {1..20}; do
  port_forward_code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:38088/ 2>/dev/null || true)"
  if [[ "${port_forward_code}" == "200" || "${port_forward_code}" == "302" ]]; then
    PORT_FORWARD_READY="true"
    break
  fi
  sleep 1
done

if [[ "${PORT_FORWARD_READY}" != "true" ]]; then
  echo "ERROR: OpenSIS UI port-forward did not become ready within the expected time window." >&2
  echo "INFO: Port-forward log follows:" >&2
  sed -n '1,120p' /tmp/opensis-k8s-port-forward.log >&2 || true
  exit 1
fi

echo
echo "OpenSIS Validation — environment: dev"
echo "Base URL: http://127.0.0.1:38088"
echo "─────────────────────────────────────────"
echo

install_code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:38088/install/index.php)"
if [[ "${install_code}" != "200" && "${install_code}" != "302" ]]; then
  echo "ERROR: Expected OpenSIS installer path to return HTTP 200 or 302, got ${install_code}." >&2
  exit 1
fi

echo "[opensis-k8s] Verifying application runtime state"
kubectl exec -n opensis-dev deploy/opensis-ui -- sh -lc 'test -s /opt/opensis/secrets/app.env && test -f /var/www/openSIS/install/index.php' >/dev/null

schema_has_app="$(kubectl exec -n opensis-dev statefulset/opensis-db -- sh -lc '. /opt/opensis/secrets/db.env && mysql -N -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "SHOW TABLES LIKE '\''app'\'';"' | tr -d '\r')"
if [[ "${schema_has_app}" == "app" ]]; then
  kubectl exec -n opensis-dev deploy/opensis-ui -- sh -lc 'test -f /var/www/openSIS/Data.php' >/dev/null
fi

echo "[opensis-k8s] Verifying MariaDB and Redis"
kubectl exec -n opensis-dev statefulset/opensis-db -- sh -lc '. /opt/opensis/secrets/db.env && mysqladmin ping -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null
kubectl exec -n opensis-dev deploy/opensis-session-redis -- sh -lc 'redis-cli ping | grep -q PONG' >/dev/null

echo "[opensis-k8s] Verifying observability exporters"
retry_check "MySQL exporter metrics check" \
  kubectl exec -n opensis-dev deploy/opensis-mysqld-exporter -- sh -lc 'wget -qO- http://127.0.0.1:9104/metrics | grep -q "^mysql_up "' >/dev/null
retry_check "Apache exporter metrics check" \
  kubectl exec -n opensis-dev deploy/opensis-apache-exporter -- sh -lc 'wget -qO- http://127.0.0.1:9117/metrics | grep -q "^apache_up "' >/dev/null
retry_check "Vault synthetic exporter metrics check" \
  kubectl exec -n opensis-dev deploy/opensis-vault-synthetic-exporter -- sh -lc 'wget -qO- http://127.0.0.1:9105/metrics | grep -q "^opensis_vault_health_status "' >/dev/null

echo "[opensis-k8s] Verification passed"
