# Overlays

This directory contains environment-specific Kustomize overlays built on top of [k8s/base](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/kustomization.yaml).

## Design Intent

- `base` holds the shared architecture
- `dev` holds local-learning and lower-risk defaults
- `prod` holds production-facing hostnames, issuers, and image references

## dev

The dev overlay is intended for local and lab clusters.

It currently changes:

- namespace to `opensis-dev`
- `APP_ENV` to `dev`
- Vault roles and paths to `opensis-app-dev` / `opensis-db-dev`
- ingress host to `opensis.dev.local`
- issuer to `local-selfsigned`
- smaller DB storage and lower resource requests
- app image pinned through Kustomize to the CI-backed branch tag `docker.io/eseosaiyangbe/opensis-ui:main`
- local ingress kept on `nginx` so `https://opensis.dev.local` stays stable during public-edge experiments
- dev now uses Redis-backed PHP sessions for environment parity with prod, while still remaining at `1` UI replica

Apply it with:

```bash
kubectl apply -k k8s/overlays/dev
```

Current validation target:

- browser URL: `https://opensis.dev.local`
- expected ingress class in the live cluster: `nginx`
- current QA status: browser access, restart resilience, Vault-driven `Data.php` generation, and Redis-backed session validation are all passing
- known limitation: the live dev path is not currently served by Traefik, so direct Traefik checks for `opensis.dev.local` will return `404`

## prod

The prod overlay is intended as the production-facing shape.

It currently changes:

- namespace to `opensis`
- app replicas to `2`
- ingress host to `opensis.raysosglobal.com`
- issuer to `letsencrypt-prod`
- app image pinned through Kustomize to the immutable production tag `docker.io/eseosaiyangbe/opensis-ui:git-244d863`
- production Vault roles and secret paths
- public ingress bound to `traefik`
- prod-specific kube-state-metrics RBAC names so Argo CD does not fight `dev` for cluster-scoped ownership

Current promotion rule:

- build and validate in `dev` first
- promote `prod` only by changing the immutable `git-<sha>` tag in [k8s/overlays/prod/kustomization.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/kustomization.yaml)
- keep live production testing aligned with `https://opensis.raysosglobal.com`

Current public-edge note:

- the working public path uses Cloudflare Tunnel plus the internal `opensis-origin-adapter`
- that adapter exists because openSIS is sensitive to raw non-browser-style origin requests
- the adapter normalizes those requests before they reach `opensis-ui`
- the base `opensis-ui` NetworkPolicy explicitly allows the `cloudflare` namespace so the adapter can reach the app
- the adapter forwards `X-Forwarded-Proto https` so the public app sees the correct original scheme
- prod now uses Redis-backed PHP sessions, so the UI can scale safely beyond one replica
- the public login page now includes a visible demo panel for the shared demo user:
  - `Username: demo`
  - `Password: demo@123`
- the first prod backup job must run at least once so `opensis-db-backup-storage` can bind under the `local-path` `WaitForFirstConsumer` storage mode

Apply it with:

```bash
kubectl apply -k k8s/overlays/prod
```

Recommended verification after a prod image promotion:

```bash
kubectl kustomize k8s/overlays/prod | rg 'image:|ingressClassName:|opensis.raysosglobal.com|opensis-prod-kube-state-metrics'
kubectl get deploy,pods,svc,ingress -n opensis -o wide
kubectl logs -n opensis deploy/opensis-ui --since=5m
kubectl get applications.argoproj.io -n argocd
kubectl get pvc -n opensis
curl -k -I https://opensis.raysosglobal.com
```

Current steady-state expectation:

- `opensis-prod` should be `Synced` and `Healthy` in Argo CD
- both `opensis-ui` pods in `opensis` should be on `docker.io/eseosaiyangbe/opensis-ui:git-244d863`
- `opensis-session-redis` should be `Running` in `opensis`
- `opensis-db-backup-storage` should be `Bound` after the first backup run

Important installer note:

- when reinstalling openSIS, keep the selected database name aligned with the runtime convention `opensis`
- if the installer writes the schema into a different database name, the app can complete install but still return `500` on `/` and `/index.php`
