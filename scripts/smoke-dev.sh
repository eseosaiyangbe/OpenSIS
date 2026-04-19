#!/usr/bin/env bash
set -euo pipefail

APP_NS="opensis-dev"
ARGO_NS="argocd"
APP_NAME="opensis-dev"
URL="https://opensis.dev.local"
UA="Mozilla/5.0"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

require kubectl
require curl

printf '==> Argo CD application status\n'
kubectl get applications.argoproj.io -n "$ARGO_NS" "$APP_NAME"

printf '\n==> Workload status\n'
kubectl get deploy,pods,svc,ingress -n "$APP_NS"

printf '\n==> Browser-style HTTP check\n'
curl -k -I -A "$UA" "$URL"

printf '\n==> Live PHP session settings\n'
kubectl exec -n "$APP_NS" deploy/opensis-ui -- sh -lc \
  'php -i | grep -E "session.save_handler|session.save_path|session.cookie_secure|session.cookie_samesite"'

printf '\n==> Smoke result\n'
printf 'dev smoke checks completed successfully for %s\n' "$URL"
