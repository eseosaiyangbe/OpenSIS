#!/usr/bin/env bash
set -euo pipefail

APP_NS="opensis"
CF_NS="cloudflare"
ARGO_NS="argocd"
APP_NAME="opensis-prod"
CF_APP_NAME="opensis-cloudflare"
URL="https://opensis.eseosadevbox.com"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

require kubectl
require curl

printf '==> Argo CD application status\n'
kubectl get applications.argoproj.io -n "$ARGO_NS" "$CF_APP_NAME" "$APP_NAME"

printf '\n==> UI deployment image and rollout\n'
kubectl get deployment opensis-ui -n "$APP_NS" -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get deployment opensis-ui -n "$APP_NS" -o jsonpath='{.spec.replicas}{" desired / "}{.status.readyReplicas}{" ready\n"}'
kubectl get pods -n "$APP_NS" -l app=opensis-ui -o wide

printf '\n==> Public HTTP checks\n'
curl -k -I "$URL/"
printf '\n'
curl -k -I "$URL/install/"

printf '\n==> Redis-backed PHP session settings on every UI pod\n'
for pod in $(kubectl get pods -n "$APP_NS" -l app=opensis-ui -o name); do
  printf '\n-- %s --\n' "$pod"
  kubectl exec -n "$APP_NS" "${pod#pod/}" -- sh -lc \
    'php -i | grep -E "session.save_handler|session.save_path|session.cookie_secure|session.cookie_samesite"'
done

printf '\n==> Cloudflare adapter rollout state\n'
kubectl get deploy,pods -n "$CF_NS" -l app=opensis-origin-adapter

printf '\n==> Smoke result\n'
printf 'prod smoke checks completed successfully for %s\n' "$URL"
