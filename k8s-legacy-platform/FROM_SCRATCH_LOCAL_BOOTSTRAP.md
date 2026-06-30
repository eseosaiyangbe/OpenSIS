# From-Scratch Local Bootstrap

This guide starts from zero and gets you to the point where this repo's Kubernetes base can work the right way:

1. install `k3s`
2. install `helm`
3. install Vault as a separate platform component
4. enable Vault Agent Injector
5. enable Vault Kubernetes auth
6. create the Vault roles and secrets that `opensis-ui` and `opensis-db` need
7. validate secret injection before deploying the app layer
8. build and import the app image into `k3s`
9. fix ingress class binding before adding certificates

This is a local learning bootstrap, but it intentionally follows the same architecture direction we want for production:

- Kubernetes is the runtime platform
- Vault is the secrets platform
- workloads authenticate to Vault with Kubernetes identities
- the app reads injected runtime files instead of repo secrets

## What This Is And What It Is Not

This is a strong starting point for learning and staging on one machine.

It is not full production HA:

- a single-node `k3s` cluster is not highly available
- a standalone Vault server is not highly available
- manual unseal is acceptable for learning but not ideal for production

Still, the identity model and secret-delivery model are the right ones to learn first.

For the next-level operating model after bootstrap, see [Production-Grade CI/CD Blueprint](PRODUCTION_GRADE_CICD_BLUEPRINT.md). That guide captures the target delivery architecture, promotion flow, security controls, and phased CI/CD implementation plan for this repo.

If you want the shorter public-facing guides first, use these alongside this deep-dive notebook:

- [Prerequisites](../docs/01-prerequisites.md)
- [Kubernetes Bootstrap Guide](../docs/03-kubernetes-bootstrap-guide.md)
- [Operations Runbook](../docs/04-operations-runbook.md)
- [Troubleshooting Guide](../docs/05-troubleshooting-guide.md)

## Authoritative DB Naming Rule

Treat the openSIS database name as a single source of truth.

For this repo, the canonical database name is:

- `opensis`

That same value must stay aligned everywhere:

- Vault `opensis-db` secret
- Vault `opensis-app` secret
- MariaDB bootstrap
- the database selected during install
- generated `Data.php` in the UI pod
- backup jobs
- exporter configuration

Do not mix names such as `opensis`, `opensis_dev`, `openSIS`, or any other variant across those layers. If the installed schema name and the configured schema name drift apart, the app can appear uninstalled, redirect back to `/install`, or fail readiness and ingress checks.

Unless you are intentionally redesigning the whole stack, use `opensis` everywhere. Consider this a required repo convention, not an optional preference.

## Suggested Host Shape

Use a dedicated Linux VM if you can.

Good starter shape:

- 4 vCPU
- 8 GB RAM
- 60 GB disk

This guide assumes:

- Linux
- `sudo` access
- outbound internet access

## Phase 1: Install k3s

The K3s quick-start guide confirms that a single-node server installation is a fully functional Kubernetes cluster and that the install script writes kubeconfig to `/etc/rancher/k3s/k3s.yaml`.

Create the config directory:

```bash
sudo mkdir -p /etc/rancher/k3s
```

This repo now includes a starter config at [k8s/bootstrap/k3s/config.yaml](bootstrap/k3s/config.yaml).

Copy it into place:

```bash
sudo cp k8s/bootstrap/k3s/config.yaml /etc/rancher/k3s/config.yaml
```

The file should look like this:

```yaml
write-kubeconfig-mode: "0644"
cluster-init: true
disable:
  - traefik
```

Why disable the bundled Traefik:

- ingress becomes an intentional platform choice
- it avoids hidden defaults
- it matches how we want to manage production components later

Install `k3s`:

```bash
curl -sfL https://get.k3s.io | sh -
```

Point your shell at the generated kubeconfig:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

You want:

- the node in `Ready`
- core system pods healthy
- no bundled Traefik pods, because ingress will be managed explicitly

## Phase 2: Install Helm

Vault is best installed with the official HashiCorp Helm chart.

Install Helm using your preferred official Helm method, then verify:

```bash
helm version
```

## Phase 3: Install an Ingress Controller

Because bundled Traefik is disabled, install an ingress controller intentionally.

For this learning path, use `ingress-nginx`.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx
```

Verify:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

## Phase 4: Install Vault in Its Own Namespace

Create the namespace:

```bash
kubectl create namespace vault
```

Add the HashiCorp Helm repo:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm search repo hashicorp/vault
```

The official Vault on Kubernetes docs say the chart supports multiple modes. For this local bootstrap, we are choosing standalone with persistent storage because it is the simplest clean learning path. HashiCorp also warns that standalone mode is not appropriate for a real production setup, so treat this as a staging step, not the final production Vault topology.

This repo now includes a starter values file at [k8s/bootstrap/vault-values.yaml](bootstrap/vault-values.yaml).

The values should include:

```yaml
injector:
  enabled: true

authDelegator:
  enabled: true

server:
  standalone:
    enabled: true
    config: |
      ui = true

      listener "tcp" {
        tls_disable = 1
        address = "[::]:8200"
        cluster_address = "[::]:8201"
      }

      storage "file" {
        path = "/vault/data"
      }

  dataStorage:
    enabled: true
    size: 10Gi

ui:
  enabled: true
  serviceType: ClusterIP
```

Install Vault:

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --version 0.32.0 \
  -f k8s/bootstrap/vault-values.yaml
```

Verify:

```bash
kubectl get pods -n vault
kubectl get svc -n vault
```

You want:

- `vault-0` running
- the injector deployment running

## Phase 5: Initialize, Unseal, and Log In to Vault

Exec into the Vault pod:

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Initialize:

```bash
vault operator init
```

Save the output carefully. It contains:

- unseal key(s)
- root token

Do not commit or keep those values in repo-tracked files. During this lab we exposed a root token in a plaintext file and in terminal output, which means it should be treated as compromised and rotated later.

Unseal:

```bash
vault operator unseal
```

Log in:

```bash
vault login
```

For a local learning cluster, manual unseal is fine. For real production later, we should move to HA plus auto-unseal.

If `vault login` returns a `503` with `Vault is sealed`, Vault is still sealed and you must finish the unseal flow first. In our run, Vault used Shamir seal with `Total Shares = 5` and `Threshold = 3`, which means one unseal key was not enough.

## Phase 6: Enable KV v2 and Kubernetes Auth

Still inside the Vault pod shell:

```bash
vault secrets enable -path=kv kv-v2
vault auth enable kubernetes
```

Configure Kubernetes auth.

HashiCorp's Kubernetes auth documentation recommends that when Vault runs in Kubernetes, you omit `token_reviewer_jwt` and `kubernetes_ca_cert` so Vault can use its local service account token and CA file:

```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
```

## Phase 7: Create the Application Namespace and Service Accounts

```bash
kubectl create namespace opensis
kubectl create serviceaccount opensis-ui -n opensis
kubectl create serviceaccount opensis-db -n opensis
```

## Phase 8: Create Vault Policies

Inside the Vault pod, create the UI policy:

```bash
cat <<'EOF' > /tmp/opensis-app-policy.hcl
path "kv/data/production/opensis-app" {
  capabilities = ["read"]
}
EOF

vault policy write opensis-app /tmp/opensis-app-policy.hcl
```

Create the DB policy:

```bash
cat <<'EOF' > /tmp/opensis-db-policy.hcl
path "kv/data/production/opensis-db" {
  capabilities = ["read"]
}
EOF

vault policy write opensis-db /tmp/opensis-db-policy.hcl
```

## Phase 9: Bind Vault Roles to Kubernetes Service Accounts

```bash
vault write auth/kubernetes/role/opensis-app \
  bound_service_account_names=opensis-ui \
  bound_service_account_namespaces=opensis \
  policies=opensis-app \
  ttl=1h
```

Vault may warn that no `audience` is configured on the role. That warning is acceptable for this learning phase and does not block the injector flow.

```bash
vault write auth/kubernetes/role/opensis-db \
  bound_service_account_names=opensis-db \
  bound_service_account_namespaces=opensis \
  policies=opensis-db \
  ttl=1h
```

## Phase 10: Seed the Secrets openSIS Needs

App secret:

```bash
vault kv put kv/production/opensis-app \
  MYSQL_DATABASE="opensis" \
  MYSQL_USER="opensis_rw" \
  MYSQL_PASSWORD="change-me" \
  DB_HOST="opensis-db.opensis.svc.cluster.local" \
  DB_PORT="3306"
```

DB secret:

```bash
vault kv put kv/production/opensis-db \
  MYSQL_ROOT_PASSWORD="change-me-root" \
  MYSQL_DATABASE="opensis" \
  MYSQL_USER="opensis_rw" \
  MYSQL_PASSWORD="change-me"
```

## Phase 11: Smoke-Test Vault Injection

Before applying the full app base, validate the injector path with a small test pod.

Create `vault-smoke.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vault-smoke
  namespace: opensis
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/agent-pre-populate-only: "true"
    vault.hashicorp.com/auth-path: "auth/kubernetes"
    vault.hashicorp.com/role: "opensis-app"
    vault.hashicorp.com/secret-volume-path: "/vault/secrets"
    vault.hashicorp.com/agent-inject-secret-app.env: "kv/data/production/opensis-app"
    vault.hashicorp.com/agent-inject-template-app.env: |
      {{- with secret "kv/data/production/opensis-app" -}}
      MYSQL_DATABASE={{ .Data.data.MYSQL_DATABASE }}
      MYSQL_USER={{ .Data.data.MYSQL_USER }}
      MYSQL_PASSWORD={{ .Data.data.MYSQL_PASSWORD }}
      DB_HOST={{ .Data.data.DB_HOST }}
      DB_PORT={{ .Data.data.DB_PORT }}
      {{- end }}
spec:
  serviceAccountName: opensis-ui
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
```

Apply it:

```bash
kubectl apply -f vault-smoke.yaml
kubectl get pod -n opensis vault-smoke
kubectl exec -n opensis vault-smoke -- cat /vault/secrets/app.env
```

If `app.env` renders correctly, the Vault identity path is working.

## Phase 12: Apply the Repo Base

Once the smoke test succeeds:

```bash
kubectl apply -k k8s/base
```

Validate:

```bash
kubectl get pods -n opensis
kubectl get svc -n opensis
kubectl get ingress -n opensis
```

Expected early behavior:

- `opensis-db-0` may start as `Pending` while its PVC binds
- `opensis-ui` may sit in an init state briefly while the Vault init container renders `app.env`

If `opensis-db` becomes `Running` and `opensis-ui` becomes `ImagePullBackOff`, the Kubernetes manifests are likely fine and the problem is the image source, not Vault or the app wiring.

## Phase 13: Build and Import the App Image Into k3s

This repo's base manifest currently uses a local-learning image tag:

- [k8s/base/opensis-ui/deployment.yaml](base/opensis-ui/deployment.yaml)

Build the image locally:

```bash
docker build \
  --build-arg APP_VERSION=dev \
  --build-arg VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo local) \
  -t opensis-ui:dev .
```

Import it into `k3s`:

```bash
docker save opensis-ui:dev -o /tmp/opensis-ui-dev.tar
sudo k3s ctr images import /tmp/opensis-ui-dev.tar
sudo k3s ctr images ls | grep opensis-ui
```

Then re-apply the base and restart the deployment:

```bash
kubectl apply -k k8s/base
kubectl rollout restart deployment/opensis-ui -n opensis
kubectl get pods -n opensis -w
```

If you see `ErrImagePull` or `ImagePullBackOff` for `opensis-ui:latest`, that means the placeholder image tag is still in the manifest or the image was not imported into `k3s`'s containerd. In our run, changing the deployment image to `opensis-ui:dev` and importing that exact tag resolved the issue.

## Phase 14: Fix Ingress Class Binding

Once the app pod is running, verify ingress:

```bash
kubectl get ingress -n opensis
curl -I -H 'Host: opensis.eseosadevbox.com' http://192.168.2.132
```

In our run, the ingress initially returned the default `404 Not Found` from `ingress-nginx` because the ingress resource had no class and the controller was not claiming it correctly.

The fix was to set:

```yaml
spec:
  ingressClassName: nginx
```

That change now exists in [k8s/base/opensis-ui/ingress.yaml](base/opensis-ui/ingress.yaml).

After reapplying, the host-header curl returned:

- `308 Permanent Redirect`

That confirmed the ingress was routing correctly and redirecting HTTP to HTTPS.

## Current Stopping Point

At the end of this bootstrap, the cluster is in a good day-1 state:

- `opensis-db` is running
- `opensis-ui` is running
- Vault injection is working
- ingress is bound to `ingress-nginx`
- HTTP routing works and redirects to HTTPS

The next missing piece is TLS issuance.

Right now [k8s/base/opensis-ui/ingress.yaml](base/opensis-ui/ingress.yaml) references the secret `opensis-ui-tls`, but that secret does not exist yet. That is why cert-manager is the next step in the journey.

## Troubleshooting Notes

These are the issues we actually hit during this lab and how we fixed them:

1. `vault login` returned `503` and `Vault is sealed`
- Cause: Vault had not been unsealed fully
- Fix: finish the Shamir unseal flow until `vault status` reports `Sealed false`

2. `opensis-ui` returned `ImagePullBackOff`
- Cause: Kubernetes could not pull `opensis-ui:latest`
- Fix: build the image locally, import it into `k3s` with `k3s ctr images import`, and use the exact imported tag in the deployment

3. ingress returned `404 Not Found` from `ingress-nginx`
- Cause: ingress class binding was missing
- Fix: set `ingressClassName: nginx` in the ingress manifest

4. `curl http://opensis.eseosadevbox.com` returned `530`
- Cause: request was going through Cloudflare, not directly to the local ingress, and TLS/origin setup was incomplete
- Fix: test locally against the ingress IP with a host header first, then add cert-manager before treating the public hostname as complete

5. `opensis-ui-tls` secret was missing
- Cause: cert-manager had not been installed yet
- Fix: install cert-manager and issue the certificate in the next phase

## Phase 15: Add cert-manager

This is the next step from the "What Comes Next" section and the natural follow-up to the missing `opensis-ui-tls` secret.

For this local bootstrap, start with a self-signed issuer. That gives you the correct Kubernetes certificate flow without depending on public ACME validation yet.

Install cert-manager using the static manifest path recommended in the cert-manager installation docs:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.5/cert-manager.yaml
```

Wait for the pods:

```bash
kubectl get pods -n cert-manager -w
```

You want these running:

- `cert-manager`
- `cert-manager-cainjector`
- `cert-manager-webhook`

This repo includes a starter issuer manifest at [k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml](bootstrap/cert-manager/selfsigned-clusterissuer.yaml).

Apply it:

```bash
kubectl apply -f k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml
kubectl get clusterissuer
```

The ingress is already prepared to use that issuer:

- [k8s/base/opensis-ui/ingress.yaml](base/opensis-ui/ingress.yaml)

Re-apply the base:

```bash
kubectl apply -k k8s/base
```

Now verify the certificate flow:

```bash
kubectl get certificate -n opensis
kubectl get certificaterequest -n opensis
kubectl get secret -n opensis opensis-ui-tls
```

What success looks like:

- a `Certificate` appears in the `opensis` namespace
- `opensis-ui-tls` is created
- ingress now has the secret it was waiting for

Important note:

- a self-signed certificate is good for local learning and flow validation
- browsers will not trust it by default
- later, replace this with a proper `ClusterIssuer` for Let's Encrypt or your chosen CA

## What Comes Next

After cert-manager is in place, the remaining roadmap items are:

1. create `k8s/overlays/dev`
2. create `k8s/overlays/prod`
3. add `NetworkPolicy`
4. pin app images in a real registry workflow
5. add DB backups
6. add observability as a separate layer

## Phase 16: Create and Test Kustomize Overlays

After cert-manager was in place, the next roadmap item was to add overlays so the repo could express environment-specific changes without duplicating the base.

The overlay structure now lives at:

- [k8s/overlays/dev](overlays/dev)
- [k8s/overlays/prod](overlays/prod)

The validation work was done against the `dev` overlay first, because it is the safest place to prove the pattern before making the `prod` overlay more intentional later.

### Commands We Ran

First, render the overlays before applying them:

```bash
kubectl kustomize k8s/base
kubectl kustomize k8s/overlays/dev
kubectl kustomize k8s/overlays/prod
```

Prepare Vault for the dev namespace by creating the dev-scoped policies and roles, then seed the dev secrets:

```bash
kubectl cp k8s/bootstrap/vault/opensis-app-dev-policy.hcl vault/vault-0:/tmp/opensis-app-dev-policy.hcl
kubectl cp k8s/bootstrap/vault/opensis-db-dev-policy.hcl vault/vault-0:/tmp/opensis-db-dev-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside the Vault pod:

```bash
vault policy write opensis-app-dev /tmp/opensis-app-dev-policy.hcl
vault policy write opensis-db-dev /tmp/opensis-db-dev-policy.hcl

vault write auth/kubernetes/role/opensis-app-dev \
  bound_service_account_names=opensis-ui \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-app-dev \
  ttl=1h

vault write auth/kubernetes/role/opensis-db-dev \
  bound_service_account_names=opensis-db \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-db-dev \
  ttl=1h

vault kv put kv/dev/opensis-app \
  MYSQL_DATABASE=opensis \
  MYSQL_USER=opensis_rw \
  MYSQL_PASSWORD=Password1 \
  DB_HOST=opensis-db.opensis-dev.svc.cluster.local \
  DB_PORT=3306

vault kv put kv/dev/opensis-db \
  MYSQL_ROOT_PASSWORD='Raymond@123' \
  MYSQL_DATABASE=opensis \
  MYSQL_USER=opensis_rw \
  MYSQL_PASSWORD=Password1
```

Apply and inspect the dev overlay:

```bash
kubectl apply -k k8s/overlays/dev
kubectl get all -n opensis-dev
kubectl get ingress -n opensis-dev
kubectl get certificate -n opensis-dev
kubectl get secret -n opensis-dev
```

Inspect the first failure symptoms when the overlay did not come up cleanly:

```bash
kubectl get pods -n opensis-dev
kubectl logs -n opensis-dev deploy/opensis-ui
kubectl describe pod -n opensis-dev opensis-db-0
kubectl exec -it -n vault vault-0 -- /bin/sh
vault kv get kv/dev/opensis-app
vault kv get kv/dev/opensis-db
```

Diagnose the injector path:

```bash
kubectl get pods -n vault
kubectl logs -n vault deploy/vault-agent-injector --tail=200
kubectl get mutatingwebhookconfiguration
kubectl describe mutatingwebhookconfiguration vault-agent-injector-cfg
kubectl get pod -n opensis-dev <opensis-ui-pod> -o yaml | sed -n '1,220p'
```

### Overlay issue we hit: invalid StatefulSet patch

The first dev apply failed with:

- `StatefulSet ... strict decoding error: unknown field "spec.template.metadata.containers"`

Cause:

- the overlay patch placed `containers:` under `spec.template.metadata` instead of `spec.template.spec`

Fix:

- move the `containers:` block into `spec.template.spec`
- fix both the `dev` and `prod` DB overlay patches

This is why validating overlays with `kubectl kustomize` before applying them is worth doing.

### Overlay issue we hit: Vault injector stopped mutating the dev pods

After the patch bug was fixed, `opensis-dev` still failed:

- `opensis-ui` entered `CrashLoopBackOff`
- `opensis-db` repeatedly failed readiness and liveness
- both pods were missing `/run/secrets/*.env`

Symptoms:

- pod annotations were present
- but there was no `vault-agent-init`
- no injected `vault-secrets` volume
- no `vault.hashicorp.com/agent-inject-status: injected`
- injector logs showed:
  - `TLS handshake error ... tls: bad certificate`

Root cause:

- the Vault injector webhook TLS state became unhealthy after a partial rolling restart
- the old injector pod kept serving
- the new injector pod stayed pending
- webhook mutation failed, but pods were still created because the webhook uses `failurePolicy: Ignore`

Fix:

1. scale the injector deployment to zero
2. wait until all injector pods are gone
3. scale it back to one replica
4. wait for rollout success
5. delete and recreate the `opensis-dev` pods

Commands:

```bash
kubectl scale deployment/vault-agent-injector -n vault --replicas=0
kubectl get pods -n vault -w
kubectl scale deployment/vault-agent-injector -n vault --replicas=1
kubectl rollout status deployment/vault-agent-injector -n vault
kubectl get pods -n vault -o wide
kubectl logs -n vault deploy/vault-agent-injector --tail=100
kubectl delete pod -n opensis-dev -l app=opensis-ui
kubectl delete pod -n opensis-dev -l app=opensis-db
kubectl get pods -n opensis-dev -w
kubectl describe pod -n opensis-dev $(kubectl get pods -n opensis-dev -l app=opensis-ui -o jsonpath='{.items[0].metadata.name}')
```

Success signal:

- recreated pods showed `vault-agent-init`
- `vault.hashicorp.com/agent-inject-status: injected`
- `/run/secrets` was mounted
- the `opensis-ui` pod became `Ready`

### Browser validation commands

Map the dev hostname locally and confirm the UI path:

```bash
echo "192.168.2.132 opensis.dev.local" | sudo tee -a /etc/hosts
getent hosts opensis.dev.local
curl -k -I https://opensis.dev.local
```

At the end of the dev overlay test:

- `opensis-dev` namespace was working
- dev-specific Vault roles and secret paths were working
- dev ingress was working
- dev TLS was working through cert-manager
- the overlay model itself was validated

This made the later roadmap phases much safer to test in `opensis-dev` first.

## Phase 17: Add and Validate NetworkPolicy

After the overlays were in place, the next roadmap item was `NetworkPolicy`.

The goal of this first policy layer is modest and intentional:

- default deny inside the application namespace
- only allow ingress to `opensis-ui` from `ingress-nginx`
- only allow ingress to `opensis-db` from `opensis-ui`
- only allow the egress paths the app and DB need right now

This repo now includes:

- [k8s/base/networking/default-deny.yaml](base/networking/default-deny.yaml)
- [k8s/base/networking/opensis-ui-policy.yaml](base/networking/opensis-ui-policy.yaml)
- [k8s/base/networking/opensis-db-policy.yaml](base/networking/opensis-db-policy.yaml)

The policies currently allow:

- `opensis-ui` ingress from the `ingress-nginx` namespace on TCP `80`
- `opensis-ui` egress to:
  - `opensis-db` on TCP `3306`
  - the `vault` namespace on TCP `8200`
  - DNS in `kube-system` on TCP/UDP `53`
- `opensis-db` ingress from `opensis-ui` on TCP `3306`
- `opensis-db` egress to:
  - the `vault` namespace on TCP `8200`
  - DNS in `kube-system` on TCP/UDP `53`

### Commands We Ran

```bash
kubectl apply -k k8s/overlays/dev
kubectl get networkpolicy -n opensis-dev
kubectl get pods -n opensis-dev
curl -I -H 'Host: opensis.dev.local' http://192.168.2.132
```

In our run, the result was successful:

- the three network policies were created
- both `opensis-db` and `opensis-ui` stayed `Running`
- ingress still returned `308 Permanent Redirect`

That confirmed the first policy set was not overblocking the application path.

### Why this phase matters

This is the first point in the journey where the cluster stops being "everything can talk to everything" by default.

It also establishes a good operating habit:

- add policies in small increments
- validate the app path after each change
- expand allowed traffic only when a concrete platform need appears

### Important note for later

This policy set is intentionally minimal.

As you add more platform components later, you should expect to extend it for:

- backup jobs
- observability agents/exporters
- migrations or admin jobs
- production ingress/controller differences

## Phase 18: Pin App Images In A Real Registry Workflow

After the networking layer was validated, the next roadmap item became the image workflow.

For this repo, the chosen direction is:

- GitHub Actions for build automation
- Docker Hub as the image registry

This keeps the local learning path simple while giving the project a real promotion path for later environments.

The workflow now lives at:

- [.github/workflows/publish-dockerhub-image.yml](../.github/workflows/publish-dockerhub-image.yml)

The supporting notes live at:

- [IMAGE_WORKFLOW.md](../IMAGE_WORKFLOW.md)

Set these in your GitHub repository before using the workflow:

- repository variable: `DOCKERHUB_USERNAME`
- repository variable: `DOCKERHUB_REPOSITORY`
- repository secret: `DOCKERHUB_TOKEN`

The workflow publishes:

- branch tags
- git SHA tags prefixed with `git-`
- release tags like `v1.0.0`

The workflow intentionally avoids `latest`.

### Commands We Ran

Initialize the repo locally if needed, connect it to GitHub, and push the project:

```bash
git init
git add .
git commit -m "Initial OpenSIS Kubernetes learning stack"
git branch -M main
git remote add origin https://github.com/<your-github-username>/OpeSIS.git
git push -u origin main
```

Trigger and validate the workflow from GitHub Actions, then verify the published image tag locally:

```bash
docker pull docker.io/eseosaiyangbe/opensis-ui:main
docker pull docker.io/eseosaiyangbe/opensis-ui:git-efd83e6
```

The first successful workflow validation published:

- `docker.io/eseosaiyangbe/opensis-ui:main`
- `docker.io/eseosaiyangbe/opensis-ui:git-efd83e6`

### Current overlay state

- `dev` is explicitly pinned through the `dev` overlay to the CI-backed integration tag `docker.io/eseosaiyangbe/opensis-ui:main`
- `prod` is explicitly pinned through the `prod` overlay to the immutable registry tag `docker.io/eseosaiyangbe/opensis-ui:git-efd83e6`
- the base deployment now carries only a neutral published baseline image, while overlays own the environment-specific image decision

The current pinned production-shaped image is:

- `docker.io/eseosaiyangbe/opensis-ui:git-efd83e6`

Recommended discipline going forward:

- let CI publish the fast-moving integration image from `main` and also stamp the mutable `dev` alias
- keep `prod` on an immutable release or commit tag
- change image references in the overlays, not ad hoc in the live cluster

Later, when you cut a formal release, you can replace that SHA tag with a version tag like `v1.0.0`.

## Phase 19: Add DB Backups

After the image workflow was validated, the next roadmap item became database backups.

For this repo, the day-1 backup design is intentionally simple and Kubernetes-native:

- a dedicated `CronJob` named `opensis-db-backup`
- a dedicated `ServiceAccount` named `opensis-db-backup`
- Vault-injected MariaDB credentials
- a dedicated backup PVC mounted at `/backup`
- a retention cleanup step in the backup script
- narrowly scoped network policy access so only the backup job can reach MariaDB

The main backup files now live at:

- [configmap.yaml](base/opensis-db-backup/configmap.yaml)
- [cronjob.yaml](base/opensis-db-backup/cronjob.yaml)
- [pvc.yaml](base/opensis-db-backup/pvc.yaml)
- [serviceaccount.yaml](base/opensis-db-backup/serviceaccount.yaml)
- [opensis-db-backup-policy.yaml](base/networking/opensis-db-backup-policy.yaml)

The Vault starter policy files live at:

- [opensis-db-backup-policy.hcl](bootstrap/vault/opensis-db-backup-policy.hcl)
- [opensis-db-backup-dev-policy.hcl](bootstrap/vault/opensis-db-backup-dev-policy.hcl)

### Commands We Ran

Copy the backup policy files into Vault and create the backup roles:

```bash
kubectl cp k8s/bootstrap/vault/opensis-db-backup-policy.hcl vault/vault-0:/tmp/opensis-db-backup-policy.hcl
kubectl cp k8s/bootstrap/vault/opensis-db-backup-dev-policy.hcl vault/vault-0:/tmp/opensis-db-backup-dev-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside the Vault pod:

```bash
vault policy write opensis-db-backup /tmp/opensis-db-backup-policy.hcl
vault policy write opensis-db-backup-dev /tmp/opensis-db-backup-dev-policy.hcl

vault write auth/kubernetes/role/opensis-db-backup \
  bound_service_account_names=opensis-db-backup \
  bound_service_account_namespaces=opensis \
  policies=opensis-db-backup \
  ttl=1h

vault write auth/kubernetes/role/opensis-db-backup-dev \
  bound_service_account_names=opensis-db-backup \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-db-backup-dev \
  ttl=1h
```

Apply the dev overlay, inspect the backup resources, and run a manual backup:

```bash
kubectl apply -k k8s/overlays/dev
kubectl get cronjob,pvc,sa -n opensis-dev
kubectl create job --from=cronjob/opensis-db-backup -n opensis-dev opensis-db-backup-manual
kubectl wait --for=condition=complete job/opensis-db-backup-manual -n opensis-dev --timeout=300s
kubectl logs -n opensis-dev job/opensis-db-backup-manual
```

Confirm the PVC is bound and the artifact persisted:

```bash
kubectl get pvc -n opensis-dev
kubectl get pods -n opensis-dev -l job-name=opensis-db-backup-manual
kubectl describe job -n opensis-dev opensis-db-backup-manual
kubectl run backup-inspect \
  -n opensis-dev \
  --restart=Never \
  --image=busybox:1.36 \
  --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "backup-inspect",
        "image": "busybox:1.36",
        "command": ["sh", "-c", "ls -lh /backup"],
        "volumeMounts": [
          {
            "name": "backup-storage",
            "mountPath": "/backup"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "backup-storage",
        "persistentVolumeClaim": {
          "claimName": "opensis-db-backup-storage"
        }
      }
    ]
  }
}'
kubectl logs -n opensis-dev backup-inspect
kubectl delete pod -n opensis-dev backup-inspect
```

The backup layer was validated in `opensis-dev` by:

1. applying the `dev` overlay
2. creating the Vault backup roles and policies
3. manually instantiating the `CronJob` as a one-off job
4. confirming the job completed successfully
5. confirming the dump file persisted on the backup PVC

The validated backup artifact was:

- `opensis-20260329-185837.sql.gz`

One small shell note from the validation: the first helper-pod inspection command used `-it`, which was unnecessary and produced a TTY warning. Re-running the inspection without TTY worked cleanly.

Reusable helpers for this phase now live under:

- [tests/k8s/backup-run.sh](../tests/k8s/backup-run.sh)
- [tests/k8s/backup-inspect.sh](../tests/k8s/backup-inspect.sh)
- [tests/k8s/backup-delete.sh](../tests/k8s/backup-delete.sh)

## Phase 19B: Add A Safe Restore Drill For `opensis-dev`

The backup path was validated earlier, but the restore path was still only a roadmap requirement. The next step is to prove that a known-good dump can be restored in `opensis-dev` without improvisation.

The restore drill is intentionally scoped to `opensis-dev` first because it is the safest place to rehearse destructive recovery. The drill uses the same backup PVC, the same MariaDB service, and the same Vault-backed root credentials already used by the backup job.

The restore helper scripts now live at:

- [tests/k8s/restore-reset.sh](../tests/k8s/restore-reset.sh)
- [tests/k8s/restore-run.sh](../tests/k8s/restore-run.sh)
- [tests/k8s/restore-verify.sh](../tests/k8s/restore-verify.sh)

The intended restore sequence is:

```bash
./tests/k8s/backup-run.sh
./tests/k8s/backup-inspect.sh
./tests/k8s/restore-verify.sh
./tests/k8s/restore-reset.sh
./tests/k8s/restore-run.sh
./tests/k8s/restore-verify.sh
```

What each step does:

1. creates a fresh backup from the `opensis-db-backup` `CronJob`
2. confirms the dump exists on the backup PVC
3. records a pre-restore baseline from the live `opensis` schema
4. resets the dev schema so the restore is meaningful instead of a no-op import
5. mounts the backup PVC in a temporary restore pod and imports either the latest dump or a specific dump file
6. verifies that the schema and application table data are present again after restore

Important operational notes:

- the restore pod reuses the `opensis-db-backup` service account and labels so the existing Vault role and MariaDB network policy continue to work without widening access
- `restore-run.sh` defaults to the newest `opensis-*.sql.gz` file on the PVC, but you can target a specific file with `BACKUP_FILE=<filename>`
- this section initially documented the procedure before live execution; the first real drill exposed that backup success did not yet guarantee backup quality

### Live Restore Drill Outcome

The live `opensis-dev` drill produced two important results:

1. the restore mechanism itself was validated successfully
2. the backup-quality assumptions were not validated successfully

What happened during the drill:

- the original backup PVC artifacts were present, but both files were only a few hundred bytes and not recoverable application backups
- one backup had been taken from the wrong schema (`opensis_dev`)
- a later backup targeted the correct schema name (`opensis`) but still contained an effectively empty dump
- the restore helper scripts had to be tightened during the drill so they preferred the real app schema and waited for MariaDB reachability instead of failing too early
- because there was no trustworthy backup on the PVC, `opensis-dev` was recovered by taking a fresh direct `mysqldump` from `opensis-db-0` in `prod` and importing it into `opensis-dev`

The successful emergency recovery sequence was:

```bash
kubectl exec -n opensis opensis-db-0 -- sh -lc '. /run/secrets/db.env && mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --quick --routines --triggers --events --databases opensis' | gzip -9 > /tmp/opensis-prod-clone.sql.gz

kubectl scale deployment/opensis-ui -n opensis-dev --replicas=0
./tests/k8s/restore-reset.sh
gzip -dc /tmp/opensis-prod-clone.sql.gz | kubectl exec -i -n opensis-dev opensis-db-0 -- sh -lc '. /run/secrets/db.env && mariadb -u root -p"$MYSQL_ROOT_PASSWORD"'
./tests/k8s/restore-verify.sh
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=1
kubectl rollout status deployment/opensis-ui -n opensis-dev
curl -k -A 'Mozilla/5.0' -I https://opensis.dev.local
```

Validated outcome:

- `opensis-dev` was recovered successfully
- `restore-verify.sh` returned the full `opensis` schema again with `table_count = 102`
- browser-style requests to `https://opensis.dev.local` returned `200`
- at the time of the first drill, generic non-browser probes could still report false negatives because openSIS remained sensitive to user-agent shape

Operational lesson from this phase:

- a mechanically successful backup job is not enough
- backup validation must prove that the artifact contains real schema or data markers before calling the job healthy
- restore testing should remain part of the go-live checklist because it is the only way to catch wrong-schema or empty-dump failures honestly

To prevent the same false-positive backup outcome from recurring, [configmap.yaml](base/opensis-db-backup/configmap.yaml) now fails the job when the archive is empty or does not contain expected SQL markers such as `USE`, `CREATE TABLE`, or `INSERT INTO`.

## Phase 20A: Add Observability Foundation

After the DB backup layer was validated, the next roadmap item became observability.

The first observability slice added in this repo is the foundation layer:

- Prometheus
- Grafana
- node-exporter
- kube-state-metrics

Those manifests now live under:

- [k8s/base/observability/prometheus](base/observability/prometheus)
- [k8s/base/observability/grafana](base/observability/grafana)
- [k8s/base/observability/node-exporter](base/observability/node-exporter)
- [k8s/base/observability/kube-state-metrics](base/observability/kube-state-metrics)

The supporting network policy lives at:

- [observability-policy.yaml](base/networking/observability-policy.yaml)

### Commands We Ran

Apply the foundation resources and inspect the new pods:

```bash
kubectl apply -k k8s/overlays/dev
kubectl get pods -n opensis-dev | grep -E 'prometheus|grafana|kube-state-metrics|node-exporter'
kubectl get pvc -n opensis-dev | grep -E 'prometheus-data|grafana-data'
```

Use port-forward for local access:

```bash
kubectl port-forward -n opensis-dev svc/grafana 3000:3000
kubectl port-forward -n opensis-dev svc/prometheus 9090:9090
```

Trigger a controlled restart to observe recovery behavior:

```bash
kubectl get pods -n opensis-dev -w
kubectl rollout restart deployment/opensis-ui -n opensis-dev
kubectl rollout status deployment/opensis-ui -n opensis-dev
kubectl get pods -n opensis-dev
curl -k -I https://opensis.dev.local
```

This foundation was validated in `opensis-dev` by:

1. applying the `dev` overlay with the new observability resources
2. confirming Prometheus, Grafana, node-exporter, and kube-state-metrics reached `Running`
3. confirming Prometheus and Grafana PVCs bound successfully
4. using a controlled `opensis-ui` rollout restart to observe recovery behavior
5. confirming the restart showed up through the new monitoring layer

For local access during this phase, Grafana and Prometheus are intentionally consumed through `kubectl port-forward` instead of public ingress.

## Phase 20B: Expand Observability

After the observability foundation was validated, the next expansion added:

- `blackbox-exporter`
- `Alertmanager`
- `mysqld-exporter`

Those manifests now live under:

- [k8s/base/observability/blackbox-exporter](base/observability/blackbox-exporter)
- [k8s/base/observability/alertmanager](base/observability/alertmanager)
- [k8s/base/observability/mysqld-exporter](base/observability/mysqld-exporter)

The Prometheus configuration was expanded to scrape the new targets and send alerts to Alertmanager through:

- [k8s/base/observability/prometheus/configmap.yaml](base/observability/prometheus/configmap.yaml)

The additional observability network policy layer now lives at:

- [k8s/base/networking/observability-expansion-policy.yaml](base/networking/observability-expansion-policy.yaml)

The `mysqld-exporter` Vault starter policy files now live at:

- [k8s/bootstrap/vault/opensis-mysqld-exporter-policy.hcl](bootstrap/vault/opensis-mysqld-exporter-policy.hcl)
- [k8s/bootstrap/vault/opensis-mysqld-exporter-dev-policy.hcl](bootstrap/vault/opensis-mysqld-exporter-dev-policy.hcl)

The Alertmanager Slack integration files now live at:

- [k8s/base/observability/alertmanager/configmap.yaml](base/observability/alertmanager/configmap.yaml)
- [k8s/base/observability/alertmanager/deployment.yaml](base/observability/alertmanager/deployment.yaml)
- [k8s/base/observability/alertmanager/serviceaccount.yaml](base/observability/alertmanager/serviceaccount.yaml)
- [k8s/overlays/dev/alertmanager-deployment-patch.yaml](overlays/dev/alertmanager-deployment-patch.yaml)

The Alertmanager Vault starter policy files now live at:

- [k8s/bootstrap/vault/opensis-alertmanager-policy.hcl](bootstrap/vault/opensis-alertmanager-policy.hcl)
- [k8s/bootstrap/vault/opensis-alertmanager-dev-policy.hcl](bootstrap/vault/opensis-alertmanager-dev-policy.hcl)

### Commands We Ran

Copy the exporter policy files into Vault and create the exporter roles:

```bash
kubectl cp k8s/bootstrap/vault/opensis-mysqld-exporter-policy.hcl vault/vault-0:/tmp/opensis-mysqld-exporter-policy.hcl
kubectl cp k8s/bootstrap/vault/opensis-mysqld-exporter-dev-policy.hcl vault/vault-0:/tmp/opensis-mysqld-exporter-dev-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside the Vault pod:

```bash
vault policy write opensis-mysqld-exporter /tmp/opensis-mysqld-exporter-policy.hcl
vault policy write opensis-mysqld-exporter-dev /tmp/opensis-mysqld-exporter-dev-policy.hcl

vault write auth/kubernetes/role/opensis-mysqld-exporter \
  bound_service_account_names=mysqld-exporter \
  bound_service_account_namespaces=opensis \
  policies=opensis-mysqld-exporter \
  ttl=1h

vault write auth/kubernetes/role/opensis-mysqld-exporter-dev \
  bound_service_account_names=mysqld-exporter \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-mysqld-exporter-dev \
  ttl=1h
```

Apply the expanded observability layer and inspect the core resources:

```bash
kubectl apply -k k8s/overlays/dev
kubectl get pods -n opensis-dev | grep -E 'alertmanager|blackbox|mysqld|prometheus|grafana'
kubectl get svc -n opensis-dev | grep -E 'alertmanager|blackbox|mysqld|prometheus|grafana'
```

Diagnose the first `mysqld-exporter` failure:

```bash
kubectl get pods -n opensis-dev
kubectl describe deployment -n opensis-dev mysqld-exporter
kubectl get rs -n opensis-dev | grep mysqld-exporter
kubectl describe rs -n opensis-dev mysqld-exporter-7d6dc4d8b6
kubectl get sa -n opensis-dev | grep mysqld-exporter
```

Validate the fixed exporter rollout and inspect its logs:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout restart deployment/mysqld-exporter -n opensis-dev
kubectl rollout status deployment/mysqld-exporter -n opensis-dev
kubectl get pods -n opensis-dev | grep mysqld-exporter
kubectl logs -n opensis-dev $(kubectl get pods -n opensis-dev -l app=mysqld-exporter -o jsonpath='{.items[0].metadata.name}') --tail=100
kubectl describe pod -n opensis-dev $(kubectl get pods -n opensis-dev -l app=mysqld-exporter -o jsonpath='{.items[0].metadata.name}')
```

Validate Prometheus targets and the UIs:

```bash
kubectl port-forward -n opensis-dev svc/prometheus 9090:9090
kubectl port-forward -n opensis-dev svc/grafana 3000:3000
kubectl port-forward -n opensis-dev svc/alertmanager 9093:9093
```

When Prometheus needed a config reload, restart it and confirm the single-replica PVC-backed rollout behavior:

```bash
kubectl rollout restart deployment/prometheus -n opensis-dev
kubectl rollout status deployment/prometheus -n opensis-dev
kubectl scale deployment/prometheus -n opensis-dev --replicas=0
kubectl scale deployment/prometheus -n opensis-dev --replicas=1
kubectl rollout status deployment/prometheus -n opensis-dev
```

Reapply the `Recreate` strategy improvement and verify Grafana restart behavior:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout restart deployment/grafana -n opensis-dev
kubectl rollout status deployment/grafana -n opensis-dev
kubectl get pods -n opensis-dev | grep grafana
```

Wire Alertmanager to Slack with a temporary Kubernetes Secret-backed approach and validate the receiver path:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout restart deployment/alertmanager -n opensis-dev
kubectl rollout status deployment/alertmanager -n opensis-dev
kubectl logs -n opensis-dev deploy/alertmanager --tail=100
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=0
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=1
kubectl rollout status deployment/opensis-ui -n opensis-dev
```

Diagnose the first Slack delivery failure and inspect the live policy:

```bash
kubectl logs -n opensis-dev deploy/alertmanager --tail=200
kubectl get networkpolicy -n opensis-dev alertmanager -o yaml
kubectl logs -n opensis-dev deploy/alertmanager --since=2m
```

After allowing Alertmanager egress for DNS and HTTPS, verify the live Slack path again:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout restart deployment/alertmanager -n opensis-dev
kubectl rollout status deployment/alertmanager -n opensis-dev
kubectl logs -n opensis-dev deploy/alertmanager --since=2m
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=0
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=1
kubectl rollout status deployment/opensis-ui -n opensis-dev
```

Tune the blackbox probe path after Slack delivery started working:

```bash
kubectl logs -n opensis-dev deploy/blackbox-exporter --tail=100
kubectl apply -k k8s/overlays/dev
kubectl logs -n opensis-dev deploy/blackbox-exporter --since=2m
kubectl logs -n opensis-dev deploy/alertmanager --since=2m
```

Migrate Alertmanager from the temporary Kubernetes `Secret` path to Vault and validate the final design:

```bash
kubectl cp k8s/bootstrap/vault/opensis-alertmanager-policy.hcl vault/vault-0:/tmp/opensis-alertmanager-policy.hcl
kubectl cp k8s/bootstrap/vault/opensis-alertmanager-dev-policy.hcl vault/vault-0:/tmp/opensis-alertmanager-dev-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside the Vault pod:

```bash
vault kv put kv/dev/alertmanager-slack \
  SLACK_WEBHOOK_URL='https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

vault kv put kv/production/alertmanager-slack \
  SLACK_WEBHOOK_URL='https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

vault policy write opensis-alertmanager /tmp/opensis-alertmanager-policy.hcl
vault policy write opensis-alertmanager-dev /tmp/opensis-alertmanager-dev-policy.hcl

vault write auth/kubernetes/role/opensis-alertmanager \
  bound_service_account_names=alertmanager \
  bound_service_account_namespaces=opensis \
  policies=opensis-alertmanager \
  ttl=1h

vault write auth/kubernetes/role/opensis-alertmanager-dev \
  bound_service_account_names=alertmanager \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-alertmanager-dev \
  ttl=1h
```

Back on the host:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout restart deployment/alertmanager -n opensis-dev
kubectl rollout status deployment/alertmanager -n opensis-dev
kubectl logs -n opensis-dev deploy/alertmanager --tail=100
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=0
kubectl scale deployment/opensis-ui -n opensis-dev --replicas=1
kubectl rollout status deployment/opensis-ui -n opensis-dev
```

This expansion was validated in `opensis-dev` by:

1. applying the `dev` overlay with the expansion resources
2. confirming `alertmanager`, `blackbox-exporter`, and `mysqld-exporter` resources were created
3. confirming `alertmanager`, `blackbox-exporter`, `grafana`, and `prometheus` reached healthy `Running` state
4. creating the `opensis-mysqld-exporter-dev` Vault role and policy so the exporter could authenticate cleanly
5. validating Prometheus target discovery after reloading Prometheus
6. integrating Alertmanager with Slack and proving `FIRING` and `RESOLVED` notifications reached Slack
7. migrating Alertmanager from a temporary Kubernetes `Secret` to Vault-backed injection and validating the same Slack flow again

During validation, six important fixes were made:

1. the initial `mysqld-exporter` Deployment defined its own `vault-secrets` volume and `/run/secrets` mount, which conflicted with the Vault injector and produced an invalid pod spec
2. MariaDB `NetworkPolicy` ingress was expanded to allow `app: mysqld-exporter`, which removed repeated exporter-side `connection refused` errors
3. both Prometheus and Grafana were updated to use `strategy: Recreate` so restarts behave correctly with their single-replica `ReadWriteOnce` PVCs
4. Alertmanager initially had no egress path for DNS or outbound HTTPS, so Slack delivery failed until the `alertmanager` `NetworkPolicy` allowed DNS on `53` and HTTPS on `443`
5. the blackbox probes were initially noisy because `blackbox-exporter` had egress to the app and DB, but `opensis-ui` and `opensis-db` were not allowing probe ingress back in; both app policies were expanded to allow `app: blackbox-exporter`
6. Alertmanager started with a temporary Kubernetes `Secret` for the Slack webhook to prove the path quickly, but was then migrated to Vault so the final secret-management model remained consistent with the rest of the stack

A final startup polish was also added to the exporter wrapper script so it waits for MariaDB TCP reachability before launching the exporter process:

- [k8s/base/observability/mysqld-exporter/configmap.yaml](base/observability/mysqld-exporter/configmap.yaml)
## Phase 20C: Harden UI Portability And Repeatability

After the Slack and observability work, the browser path exposed one more portability problem in `opensis-dev`:

- the UI initially pointed at `opensis_dev`, while the real installed schema lived in `opensis`
- `openSIS` still expected a generated `Data.php`, even though the pod already had Vault-injected `app.env`
- the MariaDB app user `opensis_rw` did not automatically have privileges on the real installed `opensis` schema
- the application also behaved differently for non-browser user agents, which caused Kubernetes probes to mark the pod unhealthy even when browser traffic was fine

The issue was diagnosed with these commands:

```bash
kubectl exec -n opensis-dev deploy/opensis-ui -- sh -lc 'cat /run/secrets/app.env'
kubectl exec -n opensis-dev opensis-db-0 -- sh -lc 'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
kubectl exec -n opensis-dev opensis-db-0 -- sh -lc 'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -D opensis -e "show tables; select * from app;"'
kubectl logs -n opensis-dev deploy/opensis-ui --tail=200
```

The first live recovery was:

```bash
vault kv put kv/dev/opensis-app \
  MYSQL_DATABASE=opensis \
  MYSQL_USER=opensis_rw \
  MYSQL_PASSWORD=Password1 \
  DB_HOST=opensis-db.opensis-dev.svc.cluster.local \
  DB_PORT=3306

kubectl exec -n opensis-dev opensis-db-0 -- sh -lc 'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON opensis.* TO \"opensis_rw\"@\"%\" IDENTIFIED BY \"Password1\"; FLUSH PRIVILEGES;"'
kubectl rollout restart deployment/opensis-ui -n opensis-dev
```

To make the fix repeatable across fresh pods and fresh machines, two repo-level changes were made:

1. [k8s/base/opensis-ui/deployment.yaml](base/opensis-ui/deployment.yaml) now generates `/var/www/openSIS/Data.php` from the Vault-rendered `/run/secrets/app.env` before Apache starts
2. [k8s/base/opensis-db/configmap.yaml](base/opensis-db/configmap.yaml) now wraps MariaDB startup with a small grant-reconciliation step that re-applies the application user privileges for the bootstrap DB and common openSIS database names such as `opensis` and `openSIS` whenever they exist

A second runtime polish was also added to the UI deployment so Kubernetes probes send a browser-like `User-Agent` instead of the default `kube-probe/...` string. At that stage this mattered because openSIS still had browser-sensitive request handling in its PHP code. Later validation traced that behavior to app code and confirmed that the remaining browser-only DB connection gate could be removed.

After those changes, the important validation commands were:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout restart deployment/opensis-ui -n opensis-dev
kubectl get pods -n opensis-dev | grep opensis-ui
curl -k -A 'Mozilla/5.0' -I https://opensis.dev.local
```

The expected healthy result is:

- the newest `opensis-ui` pod reaches `1/1 Running`
- browser traffic returns `HTTP/2 200`
- `Data.php` is present in the UI pod after each restart
- the fix survives new pod creation instead of depending on a one-off manual file copy

## Phase 20D: Add GitOps With Argo CD

Before shaping the `prod` overlay, GitOps was added so `opensis-dev` could be reconciled from Git instead of relying only on manual `kubectl apply -k` runs. Argo CD was chosen as the GitOps controller.

The repo-owned GitOps layer lives in:

- [k8s/gitops/argocd/project.yaml](gitops/argocd/project.yaml)
- [k8s/gitops/argocd/opensis-dev-application.yaml](gitops/argocd/opensis-dev-application.yaml)
- [k8s/gitops/argocd/opensis-prod-application.yaml](gitops/argocd/opensis-prod-application.yaml)
- [k8s/gitops/README.md](gitops/README.md)

The live install and registration flow was:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

That first install hit a CRD annotation-size problem on `applicationsets.argoproj.io`, so the install was completed with server-side apply:

```bash
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd
```

Once Argo CD itself was healthy, the repo-owned GitOps definitions were applied:

```bash
kubectl apply -k k8s/gitops/argocd
kubectl get applications.argoproj.io -n argocd
kubectl describe application opensis-dev -n argocd
```

Because the GitHub repository is private, the Applications could not sync over anonymous HTTPS. The GitOps manifests were switched to SSH and a dedicated Argo CD deploy key was generated instead:

```bash
ssh-keygen -t ed25519 -N '' -C 'argocd-opensis-github' -f /tmp/argocd-opensis-github
cat /tmp/argocd-opensis-github.pub
```

The public key was added in GitHub as a read-only deploy key for the repository, and Argo CD was given the matching private key through a repository secret. After that, a hard refresh was enough to trigger real reconciliation:

```bash
kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate application opensis-prod -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get applications.argoproj.io -n argocd
```

The expected steady state is:

- `opensis-dev` = `Synced`, `Healthy`
- `opensis-prod` = `OutOfSync`, `Healthy`

That result is intentional. `dev` is now fully GitOps-managed, while `prod` is only registered in Argo CD until the production overlay is shaped more deliberately.

One operational lesson from this phase is worth making explicit: once GitOps is active, the remote Git repository is the real source of truth. A local manifest fix is not durable until it is committed and pushed. During validation, the UI regression reappeared because Argo CD reconciled an older GitHub revision that did not yet contain the hardened `opensis-ui` startup command, `Data.php` generation, and browser-like probe headers. The durable recovery was to commit the fix, push it to GitHub, and refresh the Argo CD Application so the live cluster converged back to the correct state.

## Phase 21: Shape The Prod Overlay Deliberately

With `dev` now GitOps-managed and aligned to the normalized baseline, the `prod` overlay was tightened so it reflects intentional production behavior instead of just a lightly modified copy of `dev`.

The production overlay now carries its own explicit patches for:

- [k8s/overlays/prod/opensis-ui-ingress-patch.yaml](overlays/prod/opensis-ui-ingress-patch.yaml)
- [k8s/overlays/prod/prometheus-configmap-patch.yaml](overlays/prod/prometheus-configmap-patch.yaml)
- [k8s/overlays/prod/prometheus-deployment-patch.yaml](overlays/prod/prometheus-deployment-patch.yaml)
- [k8s/overlays/prod/prometheus-pvc-patch.yaml](overlays/prod/prometheus-pvc-patch.yaml)
- [k8s/overlays/prod/grafana-deployment-patch.yaml](overlays/prod/grafana-deployment-patch.yaml)
- [k8s/overlays/prod/grafana-pvc-patch.yaml](overlays/prod/grafana-pvc-patch.yaml)

The most important production-specific changes were:

1. Prometheus storage was increased to `20Gi`, retention was set to `15d`, and CPU/memory requests and limits were raised to more realistic production values.
2. Grafana storage was increased to `5Gi`, and Grafana CPU/memory requests and limits were raised above the dev defaults.
3. The production ingress host and the production blackbox HTTP probe target were both changed from the placeholder `opensis.example.com` to the real hostname `opensis.eseosadevbox.com`.
4. Grafana admin credentials were removed from inline manifest defaults and moved to Vault so they follow the same secret-delivery model as the rest of the stack.

The Grafana Vault move added these repo pieces:

- [k8s/base/observability/grafana/serviceaccount.yaml](base/observability/grafana/serviceaccount.yaml)
- [k8s/base/observability/grafana/deployment.yaml](base/observability/grafana/deployment.yaml)
- [k8s/overlays/dev/grafana-deployment-patch.yaml](overlays/dev/grafana-deployment-patch.yaml)
- [k8s/bootstrap/vault/opensis-grafana-policy.hcl](bootstrap/vault/opensis-grafana-policy.hcl)
- [k8s/bootstrap/vault/opensis-grafana-dev-policy.hcl](bootstrap/vault/opensis-grafana-dev-policy.hcl)

The Vault bootstrap flow for Grafana is now:

```bash
kubectl cp k8s/bootstrap/vault/opensis-grafana-policy.hcl vault/vault-0:/tmp/opensis-grafana-policy.hcl
kubectl cp k8s/bootstrap/vault/opensis-grafana-dev-policy.hcl vault/vault-0:/tmp/opensis-grafana-dev-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside the Vault pod:

```bash
vault policy write opensis-grafana /tmp/opensis-grafana-policy.hcl
vault policy write opensis-grafana-dev /tmp/opensis-grafana-dev-policy.hcl

vault write auth/kubernetes/role/opensis-grafana   bound_service_account_names=grafana   bound_service_account_namespaces=opensis   policies=opensis-grafana   ttl=1h

vault write auth/kubernetes/role/opensis-grafana-dev   bound_service_account_names=grafana   bound_service_account_namespaces=opensis-dev   policies=opensis-grafana-dev   ttl=1h

vault kv put kv/production/grafana   GF_SECURITY_ADMIN_USER=admin   GF_SECURITY_ADMIN_PASSWORD='choose-a-strong-prod-password'

vault kv put kv/dev/grafana   GF_SECURITY_ADMIN_USER=admin   GF_SECURITY_ADMIN_PASSWORD='choose-a-strong-dev-password'
```

The render validation commands for this phase were:

```bash
kubectl kustomize k8s/overlays/dev
kubectl kustomize k8s/overlays/prod
```

The expected production shape is now:

- Grafana no longer relies on inline `admin/admin` credentials.
- the production ingress host is `opensis.eseosadevbox.com`.
- the production blackbox HTTP probe checks `https://opensis.eseosadevbox.com`.
- Prometheus and Grafana have production-sized persistence and resources rather than inheriting only the base defaults.

## Phase 22A: Prepare Cloudflare And Traefik Edge Publication

To move the stack toward real public reachability, the next milestone prepared Cloudflare Tunnel and Traefik in the repo without breaking the currently healthy `nginx`-based dev ingress.

The main repo additions in this phase are:

- [k8s/platform/cloudflare/kustomization.yaml](platform/cloudflare/kustomization.yaml)
- [k8s/platform/cloudflare/namespace.yaml](platform/cloudflare/namespace.yaml)
- [k8s/platform/cloudflare/serviceaccount.yaml](platform/cloudflare/serviceaccount.yaml)
- [k8s/platform/cloudflare/deployment.yaml](platform/cloudflare/deployment.yaml)
- [k8s/platform/cloudflare/networkpolicy.yaml](platform/cloudflare/networkpolicy.yaml)
- [k8s/platform/cloudflare/secret.example.yaml](platform/cloudflare/secret.example.yaml)
- [k8s/platform/cloudflare/README.md](platform/cloudflare/README.md)
- [k8s/bootstrap/traefik/values.yaml](bootstrap/traefik/values.yaml)
- [k8s/bootstrap/traefik/README.md](bootstrap/traefik/README.md)

The cluster validation before adding those files confirmed that the current live cluster still only had the `nginx` ingress class:

```bash
kubectl get ingressclass
kubectl get svc -A | grep -i traefik
```

That mattered because the repo now wants Traefik for the future public edge path, but a direct cutover would have broken the currently working `opensis-dev` route.

The Cloudflare layer was therefore prepared as a separate, renderable namespace-scoped component first:

```bash
kubectl kustomize k8s/platform/cloudflare
```

The intended edge design is now explicit:

- Cloudflare provides the public edge for `opensis.eseosadevbox.com`
- `cloudflared` lives in its own `cloudflare` namespace
- Traefik remains the intended in-cluster ingress controller
- the tunnel should target Traefik only after Traefik is installed and the app ingress has been deliberately cut over

The safe cutoff point for this phase is also explicit:

- do not point public Cloudflare traffic at the cluster yet
- do not switch the working application ingress away from `nginx` yet
- first install Traefik, verify the `traefik` ingress class, then create the Cloudflare tunnel token Secret and apply the `cloudflared` Deployment

## Phase 22B: Install Traefik And Validate Ingress Cutover

This phase moved the cluster from `nginx`-only ingress toward a Traefik-based edge path that we can later place behind Cloudflare Tunnel.

What changed in the repo:

- `k8s/base/opensis-ui/ingress.yaml`
  - changed `ingressClassName` from `nginx` to `traefik`
- `k8s/base/networking/opensis-ui-policy.yaml`
  - temporarily allowed ingress from both the `ingress-nginx` and `traefik` namespaces during transition
- `k8s/bootstrap/traefik/values.yaml`
  - installed Traefik with one replica
  - later changed the Traefik Service from `ClusterIP` to `LoadBalancer` so the single-node lab could expose NodePorts for validation

Live install and validation commands:

```bash
kubectl get ingressclass
kubectl get ingress -A
kubectl get svc -A | grep -i traefik
```

Create the Traefik namespace and install the chart:

```bash
kubectl create namespace traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update
KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install traefik traefik/traefik -n traefik -f k8s/bootstrap/traefik/values.yaml
```

Verify the controller and ingress class:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
kubectl describe ingressclass traefik
```

Commit and push the ingress class cutover:

```bash
git add k8s/base/opensis-ui/ingress.yaml
git commit -m "Switch openSIS ingress to Traefik"
git push origin main
kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get applications.argoproj.io -n argocd
kubectl get ingress -n opensis-dev opensis-ui -o yaml
```

When the old ingress path stayed in place, fix the app-side policy to allow Traefik:

```bash
git add k8s/base/networking/opensis-ui-policy.yaml
git commit -m "Allow Traefik during ingress transition"
git push origin main
kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl delete ingress -n opensis-dev opensis-ui
kubectl get ingress -n opensis-dev opensis-ui -o yaml
kubectl describe ingress -n opensis-dev opensis-ui
```

When Traefik initially returned `404`, switch the Traefik Service exposure mode and reapply:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install traefik traefik/traefik -n traefik -f k8s/bootstrap/traefik/values.yaml
kubectl get svc -n traefik -o wide
kubectl logs -n traefik deploy/traefik --since=10m
kubectl get nodes -o wide
```

Validate that Traefik is actually routing the application:

```bash
curl -k -H 'Host: opensis.dev.local' https://127.0.0.1:32200 -I
curl -H 'Host: opensis.dev.local' http://127.0.0.1:30621 -I
```

Observed result:

- the earlier Traefik `404` disappeared
- the NodePort validations reached the `opensis-ui` backend
- the backend returned `500`, not `404`, which confirmed that Traefik was routing correctly and the response was now coming from the application itself
- this matched previous openSIS behavior where non-browser-style requests can still behave poorly even when the app is fundamentally healthy

Operational conclusion:

- Traefik is installed and active in the cluster
- the `opensis-dev` ingress now belongs to the `traefik` ingress class
- Traefik is a valid next hop for Cloudflare Tunnel
- the local browser edge path on standard `80/443` still needs deliberate finalization, but the in-cluster routing milestone is complete

## Phase 22C: Roll Back opensis-dev To nginx While Keeping Traefik For Public Edge Planning

After validating that Traefik could route traffic internally, the local browser path for `opensis.dev.local` still became awkward in this single-node lab. The app remained healthy, but local access on standard `80/443` was more stable through the existing `nginx` ingress controller.

Decision:

- keep `opensis-dev` on `nginx` for reliable day-to-day local use
- keep Traefik installed for the future public edge path with Cloudflare
- treat the dual-controller state as temporary transition architecture, not the final steady state

Rollback steps:

```bash
git add k8s/base/opensis-ui/ingress.yaml
git commit -m "Roll back dev ingress to nginx"
git push origin main

kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get applications.argoproj.io -n argocd
kubectl get ingress -n opensis-dev opensis-ui -o yaml
curl -k -A 'Mozilla/5.0' -I https://opensis.dev.local
```

Observed result:

- `opensis-dev` returned to `Synced` and `Healthy`
- the live ingress switched back to:
  - `ingressClassName: nginx`
- browser-style validation returned:
  - `HTTP/2 200`
- the openSIS UI became accessible again through the normal local hostname

Operational conclusion:

- local/dev ingress stays on `nginx` for now
- Traefik remains installed and validated as a future next hop for Cloudflare Tunnel
- once the public path is proven, the stack should be simplified back to a single ingress controller

This captures the lesson cleanly:

- Traefik validation succeeded
- local UX mattered more than forcing the cutover early
- `nginx` is now the local stabilizer
- Traefik is still the public-edge candidate

## Phase 22D: Prepare Cloudflare Tunnel For GitOps-Managed Public Edge

This phase made the Cloudflare edge path repo-driven and ready for live activation with Vault managing the tunnel token instead of a plain Kubernetes Secret.

What changed in the repo:

- `k8s/platform/cloudflare/deployment.yaml`
  - now uses Vault Agent injection to render a token file at `/run/secrets/cloudflare-token`
  - keeps `cloudflared` readiness and liveness probes through the built-in metrics endpoint on port `2000`
- `k8s/platform/cloudflare/networkpolicy.yaml`
  - now allows egress to Vault on port `8200` in addition to DNS and outbound HTTPS
- `k8s/platform/cloudflare/README.md`
  - now documents the Cloudflare dashboard hostname mapping and the Vault-first activation flow
- `k8s/bootstrap/vault/opensis-cloudflare-policy.hcl`
  - added the Vault policy for reading `kv/data/production/cloudflare`
- `k8s/gitops/argocd/cloudflare-application.yaml`
  - added a dedicated Argo CD application for the `cloudflare` namespace component
- `k8s/gitops/argocd/kustomization.yaml`
  - now includes the Cloudflare application
- `k8s/gitops/argocd/project.yaml`
  - now allows the `cloudflare` namespace as a valid deployment destination
- `k8s/overlays/prod/opensis-ui-ingress-patch.yaml`
  - now explicitly binds the production ingress to `ingressClassName: traefik`

Render validation commands:

```bash
kubectl kustomize k8s/platform/cloudflare
kubectl kustomize k8s/gitops/argocd
kubectl kustomize k8s/overlays/prod | grep -nE 'kind: Ingress|ingressClassName: traefik|opensis.eseosadevbox.com'
```

Expected result:

- the `cloudflare` platform component renders cleanly
- the Argo CD project and applications render cleanly, including `opensis-cloudflare`
- the production ingress renders with:
  - `ingressClassName: traefik`
  - host `opensis.eseosadevbox.com`

Cloudflare dashboard setup for the live cutover:

1. create a named tunnel in Cloudflare
2. add the public hostname:
   - `opensis.eseosadevbox.com`
3. point that hostname at the in-cluster origin adapter:
   - `http://opensis-origin-adapter.cloudflare.svc.cluster.local:8080`
4. copy the generated tunnel token

Single-node lab finding:

- the Cloudflare tunnel was initially pointed at `http://traefik.traefik.svc.cluster.local`
- later it was also tested against Traefik's NodePort
- both approaches were still brittle because openSIS was too sensitive to non-browser-style origin requests
- the stable public solution became an internal `opensis-origin-adapter` service in the `cloudflare` namespace
- that adapter forwards to openSIS with browser-like request headers so Cloudflare can reliably receive `200` responses
- the working public path is therefore:
  - Cloudflare
  - `cloudflared`
  - `opensis-origin-adapter`
  - `opensis-ui`

Seed the live token in Vault:

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside Vault:

```bash
vault kv put kv/production/cloudflare   TUNNEL_TOKEN='replace-with-your-cloudflare-tunnel-token'
```

Load the Cloudflare policy and role into Vault:

```bash
kubectl cp k8s/bootstrap/vault/opensis-cloudflare-policy.hcl vault/vault-0:/tmp/opensis-cloudflare-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside Vault:

```bash
vault policy write opensis-cloudflare /tmp/opensis-cloudflare-policy.hcl

vault write auth/kubernetes/role/opensis-cloudflare   bound_service_account_names=cloudflared   bound_service_account_namespaces=cloudflare   policies=opensis-cloudflare   ttl=1h
```

Apply or refresh the GitOps objects:

```bash
kubectl apply -k k8s/gitops/argocd
kubectl annotate application opensis-cloudflare -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get applications.argoproj.io -n argocd
```

Validate the Cloudflare namespace component:

```bash
kubectl get all -n cloudflare
kubectl logs -n cloudflare deploy/cloudflared --tail=100
```

Operational conclusion:

- the repo is now ready for a GitOps-managed Cloudflare Tunnel component in its own namespace
- Vault, not a plain Kubernetes Secret, is now the source of truth for the tunnel token
- the public application path is deliberately shaped as:
  - Cloudflare
  - `cloudflared`
  - `opensis-origin-adapter`
  - `opensis-ui`
- the production ingress remains Traefik-bound, while the adapter handles the request normalization needed for reliable public responses
- the only remaining live dependencies for activation are the real Cloudflare tunnel token, the Vault role/policy setup, and the dashboard hostname mapping


## Phase 22E: Reconcile Prod With GitOps And Stabilize The Public Path

After the public path first came up, the live `opensis` namespace still carried a lot of hand-applied recovery state. That made `opensis-prod` stay `OutOfSync`, and the public URL became fragile again during reinstall and promotion work.

What had to be corrected:

- the successful installer run had written the application schema into a database named `Raymond`, while the runtime convention and generated `Data.php` still pointed to `opensis`
- the result was that `/install/index.php` returned `200`, but `/` and `/index.php` returned `500`
- after the full `prod` overlay was applied, the `opensis-ui` NetworkPolicy no longer allowed ingress from the `cloudflare` namespace
- that blocked `opensis-origin-adapter` from reaching `opensis-ui`, which made Cloudflare return `502`
- `opensis-dev` and `opensis-prod` were also both trying to own the same cluster-scoped kube-state-metrics RBAC objects, which kept `opensis-prod` in drift even after most resources were reconciled

Fixes that made the public path and GitOps state line up again:

1. move the installed schema back into the canonical `opensis` database
2. restart `opensis-ui` and verify `/` returns `200` again
3. update the base `opensis-ui` NetworkPolicy to allow the `cloudflare` namespace
4. restart `opensis-origin-adapter` and verify it can proxy to `opensis-ui` again
5. give the `prod` overlay its own kube-state-metrics cluster-scoped RBAC names:
   - `opensis-prod-kube-state-metrics`
6. trigger a real Argo CD sync for `opensis-prod`, not just a refresh

Representative validation commands:

```bash
kubectl get applications.argoproj.io -n argocd
kubectl get deploy,pods,svc,ingress -n opensis -o wide
kubectl get deploy,pods -n cloudflare -o wide
kubectl exec -n opensis deploy/opensis-ui -- sh -lc 'curl -s -o /dev/null -w "%{http_code}\n" -A "Mozilla/5.0" http://127.0.0.1/'
kubectl exec -n cloudflare deploy/opensis-origin-adapter -- sh -lc 'wget -qSO- http://127.0.0.1:8080/ >/dev/null'
curl -k -I https://opensis.eseosadevbox.com
```

Final outcome of the reconciliation:

- `opensis-prod` moved from `OutOfSync` to `Synced`
- the public URL `https://opensis.eseosadevbox.com` returned `HTTP/2 200` again
- the current immutable prod image was later promoted to `docker.io/eseosaiyangbe/opensis-ui:git-c136761`
- `dev` and `prod` no longer compete for the same kube-state-metrics cluster-scoped RBAC objects

## Phase 22F: Finalize Prod Promotion, Demo Login, And Backup Readiness

After the public path was healthy again, the next milestones were to promote the refreshed immutable production image, expose a safe demo login on the public page, and clear the last Argo CD health blocker.

What changed:

- [app/LoginInc.php](../app/LoginInc.php)
  - now shows a visible demo login panel on the public login page:
    - `Username: demo`
    - `Password: demo@123`
- [k8s/overlays/prod/kustomization.yaml](overlays/prod/kustomization.yaml)
  - now pins production to `docker.io/eseosaiyangbe/opensis-ui:git-c136761`
- the production rollout also surfaced one more platform lesson:
  - `opensis-db-backup-storage` stayed `Pending` because the `local-path` StorageClass uses `WaitForFirstConsumer`
  - Argo CD therefore kept `opensis-prod` in `Progressing` until something actually mounted that backup PVC

Representative commands and checks:

```bash
kubectl get deployment opensis-ui -n opensis -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get pods -n opensis -l app=opensis-ui -o wide
curl -ks https://opensis.eseosadevbox.com | rg 'Demo Credentials|demo@123'

kubectl create job -n opensis --from=cronjob/opensis-db-backup opensis-db-backup-manual-$(date +%s)
kubectl get jobs,pods,pvc -n opensis
kubectl describe pvc -n opensis opensis-db-backup-storage
kubectl annotate application opensis-prod -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get applications.argoproj.io -n argocd
```

Operational outcome:

- the prod workload fully rolled to `docker.io/eseosaiyangbe/opensis-ui:git-c136761`
- the public login page now visibly presents the demo credentials for the `demo` user
- the one-off backup job caused `opensis-db-backup-storage` to bind successfully
- once that PVC was bound, `opensis-prod` finally moved from `Synced / Progressing` to `Synced / Healthy`
- all three Argo CD applications now report healthy steady state:
  - `opensis-cloudflare`
  - `opensis-dev`
  - `opensis-prod`

Lesson learned:

- in single-node `local-path` setups, a backup PVC with `WaitForFirstConsumer` may leave an otherwise healthy application showing `Progressing` until the first backup job runs
- once the first consumer mounts the claim, the PVC binds and Argo CD can report the application as fully healthy

## Phase 22F-1: Recover Prod Backup Auth Drift

Later, `opensis-prod` showed `Synced / Degraded` even though the public site was still serving `HTTP 200`.

What actually happened:

- the immediate trigger was a failed child Job from `CronJob/opensis-db-backup`
- Argo CD treated that failed backup run as part of the app health picture
- deleting the failed Job alone did not clear the degraded state because the next manual backup still failed for a real reason
- the real defect was credential drift between Vault and the MariaDB users stored inside the live `opensis-db` data directory

Representative checks that identified the real problem:

```bash
kubectl get applications -n argocd
kubectl get jobs -n opensis --sort-by=.metadata.creationTimestamp
kubectl logs -n opensis job/opensis-db-backup-manual-<timestamp> --all-containers=true --tail=200

kubectl exec -n opensis opensis-db-0 -- sh -lc 'cat /run/secrets/db.env'

kubectl exec -it -n vault vault-0 -- sh -lc '
export VAULT_ADDR=https://vault.vault.svc:8200
export VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt
export VAULT_TOKEN="<root-token>"
vault kv get kv/production/opensis-db
vault kv get kv/production/opensis-app
'
```

What those checks proved in our run:

- Vault Agent injection was healthy
- `kv/production/opensis-db` matched `/run/secrets/db.env` in `opensis-db-0`
- `mysqldump` in the backup Job was still getting `Access denied for user 'root'`
- `opensis-app` and `opensis-db` had drifted away from each other on the application user password
- the mismatch was therefore inside MariaDB itself, not in Vault

Recovery path we validated:

1. scale `opensis-ui` down temporarily so the database can be repaired cleanly
2. temporarily patch `opensis-db` to run `sleep infinity`
3. exec into `opensis-db-0` and start `mariadbd --skip-grant-tables`
4. inspect `mysql.user`
5. reset the MariaDB `root` and `opensis_rw` users to match the intended Vault values
6. restore the normal StatefulSet command and recycle `opensis-db-0`
7. verify both:
   - `mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;"`
   - `mariadb -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT 1;"`
8. create a fresh manual backup Job and confirm it completes
9. scale `opensis-ui` back up and hard-refresh Argo CD
10. delete stale failed manual backup Jobs so Argo can return to clean steady state

Operational outcome:

- the new manual backup run completed successfully and wrote a valid archive
- `opensis-ui` returned to `2/2 Running`
- `opensis-prod` returned from `Synced / Degraded` to `Synced / Healthy`
- the public URL kept returning `HTTP/2 200`

Lesson learned:

- when `opensis-prod` is degraded but the public site still works, inspect failed backup Jobs before assuming the UI rollout is bad
- if Vault values and rendered secret files agree, but MariaDB still rejects auth, the drift is in the live database users, not in Vault
- if the DB user password changes, `kv/production/opensis-db` and `kv/production/opensis-app` must stay aligned for `opensis-db-backup` and `opensis-ui`
- after backup-related recovery work, delete stale failed manual Jobs so Argo CD does not keep stale degraded evidence around

## Phase 22G: Stabilize Prod Login Sessions And Refresh Behavior

After the installer route was blocked successfully in production, the public login flow still behaved badly:

- login sometimes required multiple attempts
- the first post-login page could appear blank
- refreshing after a successful login could immediately return the user to the login page

Root cause:

- the `prod` overlay had been scaled to `replicas: 2` for `opensis-ui`
- PHP sessions were still using local file-backed storage inside each container
- because session data was not shared between pods, a refresh or follow-up request could hit the other pod and lose the authenticated session

Representative live checks that confirmed this:

```bash
kubectl get deployment opensis-ui -n opensis -o yaml | sed -n '/replicas:/,/strategy:/p'
kubectl get pods -n opensis -l app=opensis-ui -o wide
kubectl exec -n opensis deploy/opensis-ui -- sh -lc 'php -i | grep -E "session.save_handler|session.save_path|session.cookie_secure|session.cookie_samesite|session.use_strict_mode"'
```

The important findings were:

- `replicas: 2` in the live prod deployment
- `session.save_handler => files`
- no shared Redis or other centralized PHP session backend

Immediate remediation:

1. reduce `prod` `opensis-ui` replicas back to `1`
2. correct the Cloudflare origin adapter header so it forwards:
   - `X-Forwarded-Proto https`
3. refresh both `opensis-prod` and `opensis-cloudflare` through Argo CD
4. confirm only one `opensis-ui` pod remains in `opensis`

Representative rollout commands:

```bash
kubectl annotate application opensis-prod -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate application opensis-cloudflare -n argocd argocd.argoproj.io/refresh=hard --overwrite

kubectl patch application opensis-prod -n argocd --type merge -p '{"operation":{"sync":{"prune":false,"syncOptions":["CreateNamespace=true"],"syncStrategy":{"apply":{}}}}}'
kubectl patch application opensis-cloudflare -n argocd --type merge -p '{"operation":{"sync":{"prune":false,"syncOptions":["CreateNamespace=true"],"syncStrategy":{"apply":{}}}}}'

kubectl rollout status deployment/opensis-ui -n opensis
kubectl rollout status deployment/opensis-origin-adapter -n cloudflare
kubectl get deployment opensis-ui -n opensis -o jsonpath='{.spec.replicas}{" desired / "}{.status.readyReplicas}{" ready\n"}'
kubectl get pods -n opensis -l app=opensis-ui -o wide
```

Validated outcome:

- `opensis-ui` in `prod` now runs as `1 desired / 1 ready`
- the public login flow became stable again
- refresh no longer immediately logs the user out
- the session-loss issue was therefore environmental, not a credential or database problem

Operational lesson:

- this openSIS deployment should remain single-replica until PHP sessions are moved to shared storage such as Redis
- horizontal scaling without shared session state causes intermittent login failures and logout-on-refresh behavior

## Phase 22H: Enable Redis-Backed Sessions And Restore Safe Horizontal Scaling

After stabilizing prod temporarily by reducing `opensis-ui` to one replica, the next goal was to remove that temporary limitation and make multi-replica prod safe again.

What was added first:

- the UI image was extended to include the PHP `redis` extension
- the UI runtime and base config were extended with optional session settings:
  - `PHP_SESSION_SAVE_HANDLER`
  - `PHP_SESSION_SAVE_PATH`
  - `PHP_SESSION_COOKIE_SECURE`
  - `PHP_SESSION_COOKIE_SAMESITE`
- a prod-only in-cluster Redis service was added:
  - `opensis-session-redis`

The safe rollout order was deliberate:

1. build and validate the Redis-capable image locally
2. promote prod to that image while leaving Redis session settings disabled
3. verify the app still behaved normally
4. enable Redis-backed sessions in the prod config map
5. restart `opensis-ui` and verify the live PHP session settings
6. only after that, scale prod back to `2` replicas

Representative commands used for the `prod` rollout:

```bash
# promote the Redis-capable image first, but leave Redis sessions disabled
git push origin main

kubectl annotate application opensis-prod -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl patch application opensis-prod -n argocd --type merge -p '{"operation":{"sync":{"prune":false,"syncOptions":["CreateNamespace=true"],"syncStrategy":{"apply":{}}}}}'

kubectl rollout status deployment/opensis-ui -n opensis
kubectl get deployment opensis-ui -n opensis -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get deploy,svc,pods -n opensis | grep opensis-session-redis

# then enable Redis sessions in the prod config and restart the UI
kubectl get configmap -n opensis opensis-ui-config -o yaml
kubectl rollout restart deployment/opensis-ui -n opensis
kubectl rollout status deployment/opensis-ui -n opensis

# verify live PHP session settings and then scale safely back to two replicas
for p in $(kubectl get pods -n opensis -l app=opensis-ui -o name); do
  echo "--- $p ---"
  kubectl exec -n opensis ${p#pod/} -- sh -lc 'php -i | grep -E "session.save_handler|session.save_path|session.cookie_secure|session.cookie_samesite"'
done

kubectl get deployment opensis-ui -n opensis -o jsonpath='{.spec.replicas}{" desired / "}{.status.readyReplicas}{" ready\n"}'
kubectl get pods -n opensis -l app=opensis-ui -o wide
```

Validated outcome:

- `opensis-session-redis` is running in the `opensis` namespace
- both `opensis-ui` pods report:
  - `session.save_handler => redis`
  - `session.save_path => tcp://opensis-session-redis:6379`
  - `session.cookie_secure => On`
  - `session.cookie_samesite => Strict`
- prod now runs as `2 desired / 2 ready`
- browser login, refresh, and multi-tab behavior remained stable after scaling back up

Operational conclusion:

- the temporary single-replica workaround is no longer the production baseline
- Redis-backed sessions are now the steady-state solution for safe horizontal scaling
- future prod scaling should preserve the shared session backend as a first-class dependency

## Phase 22I: Bring Dev To The Same Redis-Backed Session Model

After production was validated with Redis-backed PHP sessions, the same session architecture was applied to `dev` so the two environments would stop diverging in one of the most failure-prone runtime behaviors.

Why this was worth doing even though `dev` was already stable:

- `dev` had been working at `1` replica with file-backed PHP sessions
- `prod` now depended on Redis-backed sessions for safe horizontal scaling
- keeping `dev` on a different session model would reduce environment parity and make session bugs harder to rehearse safely

What changed in `dev`:

- a `opensis-session-redis` deployment, service, and network policy were added to the `opensis-dev` namespace
- the `dev` UI config was updated to set:
  - `PHP_SESSION_SAVE_HANDLER=redis`
  - `PHP_SESSION_SAVE_PATH=tcp://opensis-session-redis:6379`
  - `PHP_SESSION_COOKIE_SECURE=1`
  - `PHP_SESSION_COOKIE_SAMESITE=Strict`
- `dev` was intentionally kept at `1` `opensis-ui` replica to preserve the already-stable browser path while gaining runtime parity

Representative commands used for the `dev` rollout:

```bash
git push origin main

kubectl annotate application opensis-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl patch application opensis-dev -n argocd --type merge -p '{"operation":{"sync":{"prune":false,"syncOptions":["CreateNamespace=true"],"syncStrategy":{"apply":{}}}}}'

kubectl rollout status deployment/opensis-ui -n opensis-dev
kubectl get deploy,svc,pods -n opensis-dev | grep opensis-session-redis

kubectl rollout restart deployment/opensis-ui -n opensis-dev
kubectl rollout status deployment/opensis-ui -n opensis-dev

kubectl exec -n opensis-dev deploy/opensis-ui -- sh -lc 'php -i | grep -E "session.save_handler|session.save_path|session.cookie_secure|session.cookie_samesite"'
```

Validated outcome:

- `opensis-session-redis` is running in `opensis-dev`
- the `opensis-dev` UI now reports:
  - `session.save_handler => redis`
  - `session.save_path => tcp://opensis-session-redis:6379`
  - `session.cookie_secure => On`
  - `session.cookie_samesite => Strict`
- browser behavior at `https://opensis.dev.local` remained stable

Operational conclusion:

- both `dev` and `prod` now use the same Redis-backed session model
- `dev` remains lower-risk because it still uses a single UI replica and local `nginx` ingress
- session behavior can now be tested with much better environment parity before production promotions

## Environment Summary

Current environment intent is now:

- `dev` is the stable local-learning environment at `https://opensis.dev.local`
- `dev` stays on `nginx` ingress for predictable browser access
- `dev` tracks the CI-backed image stream `docker.io/eseosaiyangbe/opensis-ui:main`
- `prod` is the public-facing environment at `https://opensis.eseosadevbox.com`
- `prod` is pinned to the immutable image `docker.io/eseosaiyangbe/opensis-ui:git-244d863`
- `prod` uses Traefik plus Cloudflare Tunnel, with the in-cluster origin adapter normalizing public requests before they reach openSIS
- the origin adapter now forwards `X-Forwarded-Proto https` so the app sees the correct public scheme
- `prod` now uses Redis-backed PHP sessions with secure session cookies
- `prod` runs `opensis-ui` safely at `2` replicas after validating shared session behavior across both pods
- `prod` now uses unique kube-state-metrics cluster-scoped RBAC names so Argo CD can keep `dev` and `prod` synced independently

Promotion rule:

- validate behavior in `dev` first
- promote `prod` only by changing the immutable `git-<sha>` tag in `k8s/overlays/prod/kustomization.yaml`
- verify the live public URL after each promotion

## Phase 22J: Harden Vault TLS

The restore milestone is now validated in `opensis-dev`, so the next hardening step is to remove the remaining plain-HTTP Vault transport inside the cluster.

Why this mattered now:

- the bootstrap install was still using `tls_disable = 1`
- earlier injector failures produced `TLS handshake error ... tls: bad certificate`, which showed the webhook trust path was still fragile
- Vault is the secrets control plane for both `dev` and `prod`, so this traffic should stop relying on plaintext service-to-service transport

This repo now includes two dedicated hardening assets:

- [tls-cert-manager.yaml](bootstrap/vault/tls-cert-manager.yaml)
- [vault-values-tls.yaml](bootstrap/vault-values-tls.yaml)

They intentionally do not replace the original learning install path. Instead, they provide a clean post-bootstrap upgrade once cert-manager is already running.

What the hardening upgrade does:

1. creates a Vault-local CA in the `vault` namespace with cert-manager
2. issues a server certificate for the live Vault services:
   - `vault`
   - `vault-internal`
   - `*.vault-internal.vault.svc`
3. issues a separate webhook certificate for `vault-agent-injector-svc`
4. mounts the Vault server certificate into the Helm release through `vault-values-tls.yaml`
5. switches the Vault listener from `tls_disable = 1` to explicit TLS certificate paths
6. lets cert-manager keep the injector webhook `caBundle` fresh through the annotation:
   - `cert-manager.io/inject-ca-from: vault/injector-certificate`

Live commands that were validated:

```bash
kubectl apply -f k8s/bootstrap/vault/tls-cert-manager.yaml
kubectl get issuer -n vault -w
kubectl get certificate -n vault -w

KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade vault hashicorp/vault   --namespace vault   --version 0.32.0   -f k8s/bootstrap/vault-values-tls.yaml
```

Two operational details mattered during the live upgrade:

1. the Vault StatefulSet uses `updateStrategy: OnDelete`, so the new server pod spec did not apply until `vault-0` was deleted manually
2. the injector Deployment uses pod anti-affinity, so on a single-node cluster the cleanest replacement path was to scale the injector to `0`, wait for the old pod to disappear, then scale back to `1`

Representative commands used after the Helm upgrade:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl delete pod -n vault vault-0
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get pod -n vault vault-0 -w

KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl scale deployment/vault-agent-injector -n vault --replicas=0
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get pods -n vault -w
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl scale deployment/vault-agent-injector -n vault --replicas=1
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get pods -n vault -w
```

Verification commands that matched the live certificate SANs:

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get secret -n vault vault-server-tls injector-tls
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl exec -n vault vault-0 -- sh -lc 'ls -R /vault/userconfig'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl exec -n vault vault-0 -- sh -lc 'export VAULT_ADDR=https://vault.vault.svc:8200 VAULT_CACERT=/vault/userconfig/vault-server-tls/ca.crt; vault status'
KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl logs -n vault deploy/vault-agent-injector --tail=100
```

One more expected behavior happened during the upgrade:

- after the new TLS-enabled `vault-0` started, Vault came up `Sealed=true`
- the pod only became fully healthy again after a normal manual unseal using the existing Shamir keys

Validated outcome:

- `vault-server-tls`, `injector-tls`, and `vault-ca-secret` exist in the `vault` namespace
- `/vault/userconfig/vault-server-tls` is mounted inside `vault-0`
- `vault status` works over `https://vault.vault.svc:8200` with `VAULT_CACERT` pointing at the mounted CA file
- Vault-injected workloads in `opensis-dev`, `opensis`, and `cloudflare` now need a namespace-local `vault-agent-ca` secret plus the annotations `vault.hashicorp.com/tls-secret: vault-agent-ca` and `vault.hashicorp.com/ca-cert: /vault/tls/ca.crt` so injected init containers can verify the Vault server certificate after the TLS upgrade
- the requirement above was validated live during later rollouts: without the namespace-local CA secret, restarted injected pods failed in `vault-agent-init` with `x509: certificate signed by unknown authority`; after the CA secret and annotations were applied, `opensis-dev` and `opensis` rolled forward cleanly again
- Vault is `Sealed=false` again after unseal
- `vault-0` is back to `1/1 Running`
- `vault-agent-injector` is back to `1/1 Running`
- the earlier bad-certificate injector behavior is no longer the steady-state condition

Operator note:

- [bootstrap.sh](../scripts/bootstrap.sh) and [seed.sh](../scripts/seed.sh) now honor an externally supplied `VAULT_ADDR`
- that keeps the legacy Docker Compose path intact while letting future hardened runs point at HTTPS explicitly

## Phase 22K: Revisit Vault Raft And Auto-Unseal

After the TLS hardening milestone, the next question was whether Vault should move immediately from single-pod `file` storage to integrated storage (Raft) with auto-unseal.

Current assessed state during this revisit:

- Kubernetes is still a single-node `k3s` cluster
- the only storage class is `local-path` with `ReadWriteOnce` local disk
- Vault is healthy over TLS, but it is still using:
  - `Storage Type = file`
  - `Seal Type = shamir`
  - manual unseal after restart
- HashiCorp's current Kubernetes guidance uses `server.ha.enabled=true` with `server.ha.raft.enabled=true` for integrated storage clusters, and expects enough nodes for the chart's pod anti-affinity to place multiple Vault pods
- HashiCorp also recommends auto-unseal for Kubernetes-based Vault servers because pod rescheduling is normal there

What this means for this repo right now:

- moving from `file` storage to Raft is the correct architectural direction
- but doing a live migration on this single-node lab would add storage-migration risk without giving real HA
- enabling chart-driven HA Raft today would immediately collide with the same anti-affinity constraint already seen during the injector rollout
- a real auto-unseal outcome also still needs an external provider, such as cloud KMS or an external transit-backed Vault cluster

So the clean recommendation for this stage is:

1. keep the now-hardened single-node TLS Vault as the current stable baseline
2. prepare the future Raft shape in repo-owned config
3. defer the live migration until the platform has the prerequisites to make it worth doing

This repo now includes a future-ready Raft values file at:

- [vault-values-raft.yaml](bootstrap/vault-values-raft.yaml)

It captures the intended next shape:

- `server.ha.enabled = true`
- `server.ha.replicas = 3`
- `server.ha.raft.enabled = true`
- TLS mounts reused from the current cert-manager-backed Vault certificate flow
- Kubernetes service registration enabled for the Raft cluster

Important operator note:

- HashiCorp documents that Raft clusters should be backed up with Vault snapshots, not ad hoc disk copies
- so when this repo eventually moves to integrated storage, the backup/restore runbooks should also grow a dedicated Vault snapshot path

Recommended prerequisites before the live Raft cutover:

1. expand the Kubernetes cluster beyond a single node
2. choose an auto-unseal provider:
   - cloud KMS
   - or a separate external transit-backed Vault cluster
3. define a tested migration plan from `file` storage to integrated storage
4. add Vault snapshot backup and restore steps to the operator runbook

With those prerequisites in place, the next live Vault milestone should be:

- replace the single-pod `file` backend with a 3-node TLS-enabled Raft cluster
- enable auto-unseal through the chosen provider
- validate cluster peer membership and snapshot-based recovery

## Phase 22L: Decide The Long-Term Role Of The Origin Adapter

After the Vault milestones, the last open architecture question in this roadmap was whether the in-cluster `opensis-origin-adapter` should remain a permanent part of the production path.

Current production request path:

- Cloudflare public edge
- `cloudflared` in the `cloudflare` namespace
- `opensis-origin-adapter`
- `opensis-ui` in the `opensis` namespace

What the adapter is doing today:

- forces a browser-like `User-Agent`
- pins `Host` to `opensis.eseosadevbox.com`
- forwards `X-Forwarded-Proto https`
- normalizes origin requests before they reach openSIS

That behavior lives in:

- [origin-adapter-configmap.yaml](platform/cloudflare/origin-adapter-configmap.yaml)
- [origin-adapter-deployment.yaml](platform/cloudflare/origin-adapter-deployment.yaml)
- [origin-adapter-service.yaml](platform/cloudflare/origin-adapter-service.yaml)

Why it exists:

- direct Cloudflare-to-Traefik and Cloudflare-to-app approaches were both brittle in this lab
- openSIS repeatedly behaved differently for non-browser-style requests before the app-side fixes were identified and patched
- the adapter became the smallest stable compatibility layer that made the public path consistently return `200`

Architectural options considered:

1. keep the adapter permanently
2. move the normalization into Traefik middleware later
3. remove the normalization entirely once the app itself no longer depends on those request-shaping quirks

Decision for this repo right now:

- keep the origin adapter as the current production baseline
- treat it as an explicit compatibility shim, not an accidental leftover
- do not remove it until a later controlled experiment proves that Traefik middleware or the app itself can absorb the same behavior safely

Why this is the right choice today:

- it is already GitOps-managed and isolated in its own namespace
- it keeps the app namespace simpler by containing the compatibility logic at the edge boundary
- the public path is stable now, and this project has already spent real effort proving that stability
- removing it now would create risk without unlocking a meaningful operational simplification yet

What a future removal path would require:

1. reproduce the current header normalization with Traefik middleware or native app fixes
2. validate browser and non-browser behavior directly through Traefik without the adapter
3. prove `200`/`302` public behavior, login stability, and smoke checks without the adapter in the path
4. only then remove the adapter manifests and simplify the Cloudflare routing target

Operational conclusion:

- for the current private local-cluster production model, the origin adapter stays
- the decision is now explicit and documented instead of remaining an open-ended temporary workaround

## Updated Remaining Roadmap

The roadmap is now in a post-publication hardening phase. The immediate roadmap items from this guide are now complete for the current single-node private-cluster model.

The next Vault milestone is explicitly gated on infrastructure prerequisites:

- move to multi-node Kubernetes
- choose an auto-unseal provider
- then perform the Raft migration with snapshot-based recovery planning

The public-edge decision for the current model is also now explicit:

- keep the origin adapter as the stable production compatibility shim until a later controlled Traefik-middleware or app-level replacement is proven
- after the app-side fixes in commits `08083d6` and `51fd6eb`, a live hot-patch validation in `opensis-dev` showed `curl`, `Blackbox Exporter`, and browser-style requests all returning `200`
- that result was then confirmed through the normal image pipeline and GitOps rollout: `opensis-dev` and `opensis` both returned `200` for browser and non-browser requests after the rebuilt UI image was pulled
- the remaining work before reconsidering adapter removal is to run a controlled edge-path experiment through Traefik and Cloudflare without the adapter in place, not to re-prove the app-level non-browser fix

## Notes For Later Production

When you move beyond a single-node learning setup, the first major changes should be:

- multi-node Kubernetes
- Vault HA with integrated Raft and auto-unseal
- TLS-hardening for Vault
- overlay-driven ingress and certificate management
- backup and restore testing before go-live

## Sources

- K3s Quick Start: https://docs.k3s.io/quick-start
- K3s Configuration Options: https://docs.k3s.io/installation/configuration
- Vault on Kubernetes: https://developer.hashicorp.com/vault/docs/deploy/kubernetes
- Vault Helm chart: https://developer.hashicorp.com/vault/docs/platform/k8s/helm
- Vault standalone TLS example: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/examples/standalone-tls
- Vault injector TLS with cert-manager: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/examples/injector-tls-cert-manager
- Vault HA with integrated storage (Raft): https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/examples/ha-with-raft
- Vault on Kubernetes deployment guide: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-raft-deployment-guide
- Vault Kubernetes auth method: https://developer.hashicorp.com/vault/docs/auth/kubernetes
- Vault Kubernetes auth bootstrap example: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/examples/kubernetes-auth
