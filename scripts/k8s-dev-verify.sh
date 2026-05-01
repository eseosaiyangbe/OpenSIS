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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTNAME_OVERRIDE="opensis.devops.local"

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
kubectl get pods -n opensis-dev
kubectl get svc -n opensis-dev
kubectl get ingress -n opensis-dev

echo "[opensis-k8s] Verifying ingress response"
http_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${HOSTNAME_OVERRIDE}" "http://${TRAEFIK_ADDR}/")"
if [[ "${http_code}" != "200" && "${http_code}" != "302" ]]; then
  echo "ERROR: Expected OpenSIS ingress to return HTTP 200 or 302, got ${http_code}." >&2
  exit 1
fi

echo "[opensis-k8s] Verifying application runtime state"
kubectl exec -n opensis-dev deploy/opensis-ui -- sh -lc 'test -s /opt/opensis/secrets/app.env && test -f /var/www/openSIS/install/index.php' >/dev/null

echo "[opensis-k8s] Verifying MariaDB and Redis"
kubectl exec -n opensis-dev statefulset/opensis-db -- sh -lc '. /opt/opensis/secrets/db.env && mysqladmin ping -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" --silent' >/dev/null
kubectl exec -n opensis-dev deploy/opensis-session-redis -- sh -lc 'redis-cli ping | grep -q PONG' >/dev/null

echo "[opensis-k8s] Verifying observability exporters"
kubectl exec -n opensis-dev deploy/opensis-mysqld-exporter -- sh -lc 'wget -qO- http://127.0.0.1:9104/metrics | grep -q "^mysql_up "' >/dev/null
kubectl exec -n opensis-dev deploy/opensis-apache-exporter -- sh -lc 'wget -qO- http://127.0.0.1:9117/metrics | grep -q "^apache_up "' >/dev/null
kubectl exec -n opensis-dev deploy/opensis-vault-synthetic-exporter -- sh -lc 'wget -qO- http://127.0.0.1:9105/metrics | grep -q "^opensis_vault_health_status "' >/dev/null

echo "[opensis-k8s] Verification passed"
