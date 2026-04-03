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

This repo now includes a starter config at [k8s/bootstrap/k3s/config.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/k3s/config.yaml).

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

This repo now includes a starter values file at [k8s/bootstrap/vault-values.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault-values.yaml).

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

- [k8s/base/opensis-ui/deployment.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-ui/deployment.yaml)

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
curl -I -H 'Host: opensis.raysosglobal.com' http://192.168.2.132
```

In our run, the ingress initially returned the default `404 Not Found` from `ingress-nginx` because the ingress resource had no class and the controller was not claiming it correctly.

The fix was to set:

```yaml
spec:
  ingressClassName: nginx
```

That change now exists in [k8s/base/opensis-ui/ingress.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-ui/ingress.yaml).

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

Right now [k8s/base/opensis-ui/ingress.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-ui/ingress.yaml) references the secret `opensis-ui-tls`, but that secret does not exist yet. That is why cert-manager is the next step in the journey.

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

4. `curl http://opensis.raysosglobal.com` returned `530`
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

This repo includes a starter issuer manifest at [k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml).

Apply it:

```bash
kubectl apply -f k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml
kubectl get clusterissuer
```

The ingress is already prepared to use that issuer:

- [k8s/base/opensis-ui/ingress.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-ui/ingress.yaml)

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

- [k8s/overlays/dev](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/dev)
- [k8s/overlays/prod](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod)

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

- [k8s/base/networking/default-deny.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/networking/default-deny.yaml)
- [k8s/base/networking/opensis-ui-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/networking/opensis-ui-policy.yaml)
- [k8s/base/networking/opensis-db-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/networking/opensis-db-policy.yaml)

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

- [.github/workflows/dockerhub-opensis-ui.yml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/.github/workflows/dockerhub-opensis-ui.yml)

The supporting notes live at:

- [IMAGE_WORKFLOW.md](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/IMAGE_WORKFLOW.md)

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

- [configmap.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-db-backup/configmap.yaml)
- [cronjob.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-db-backup/cronjob.yaml)
- [pvc.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-db-backup/pvc.yaml)
- [serviceaccount.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-db-backup/serviceaccount.yaml)
- [opensis-db-backup-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/networking/opensis-db-backup-policy.yaml)

The Vault starter policy files live at:

- [opensis-db-backup-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-db-backup-policy.hcl)
- [opensis-db-backup-dev-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-db-backup-dev-policy.hcl)

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

- [tests/k8s/backup-run.sh](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/tests/k8s/backup-run.sh)
- [tests/k8s/backup-inspect.sh](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/tests/k8s/backup-inspect.sh)
- [tests/k8s/backup-delete.sh](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/tests/k8s/backup-delete.sh)

## Phase 20A: Add Observability Foundation

After the DB backup layer was validated, the next roadmap item became observability.

The first observability slice added in this repo is the foundation layer:

- Prometheus
- Grafana
- node-exporter
- kube-state-metrics

Those manifests now live under:

- [k8s/base/observability/prometheus](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/prometheus)
- [k8s/base/observability/grafana](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/grafana)
- [k8s/base/observability/node-exporter](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/node-exporter)
- [k8s/base/observability/kube-state-metrics](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/kube-state-metrics)

The supporting network policy lives at:

- [observability-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/networking/observability-policy.yaml)

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

- [k8s/base/observability/blackbox-exporter](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/blackbox-exporter)
- [k8s/base/observability/alertmanager](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/alertmanager)
- [k8s/base/observability/mysqld-exporter](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/mysqld-exporter)

The Prometheus configuration was expanded to scrape the new targets and send alerts to Alertmanager through:

- [k8s/base/observability/prometheus/configmap.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/prometheus/configmap.yaml)

The additional observability network policy layer now lives at:

- [k8s/base/networking/observability-expansion-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/networking/observability-expansion-policy.yaml)

The `mysqld-exporter` Vault starter policy files now live at:

- [k8s/bootstrap/vault/opensis-mysqld-exporter-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-mysqld-exporter-policy.hcl)
- [k8s/bootstrap/vault/opensis-mysqld-exporter-dev-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-mysqld-exporter-dev-policy.hcl)

The Alertmanager Slack integration files now live at:

- [k8s/base/observability/alertmanager/configmap.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/alertmanager/configmap.yaml)
- [k8s/base/observability/alertmanager/deployment.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/alertmanager/deployment.yaml)
- [k8s/base/observability/alertmanager/serviceaccount.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/alertmanager/serviceaccount.yaml)
- [k8s/overlays/dev/alertmanager-deployment-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/dev/alertmanager-deployment-patch.yaml)

The Alertmanager Vault starter policy files now live at:

- [k8s/bootstrap/vault/opensis-alertmanager-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-alertmanager-policy.hcl)
- [k8s/bootstrap/vault/opensis-alertmanager-dev-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-alertmanager-dev-policy.hcl)

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
  SLACK_WEBHOOK_URL='https://hooks.slack.com/services/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'

vault kv put kv/production/alertmanager-slack \
  SLACK_WEBHOOK_URL='https://hooks.slack.com/services/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'

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

- [k8s/base/observability/mysqld-exporter/configmap.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/mysqld-exporter/configmap.yaml)
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

1. [k8s/base/opensis-ui/deployment.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-ui/deployment.yaml) now generates `/var/www/openSIS/Data.php` from the Vault-rendered `/run/secrets/app.env` before Apache starts
2. [k8s/base/opensis-db/configmap.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/opensis-db/configmap.yaml) now wraps MariaDB startup with a small grant-reconciliation step that re-applies the application user privileges for the bootstrap DB and common openSIS database names such as `opensis` and `openSIS` whenever they exist

A second runtime polish was also added to the UI deployment so Kubernetes probes send a browser-like `User-Agent` instead of the default `kube-probe/...` string. This matters because openSIS only executes some DB work when the user agent looks like a browser.

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

- [k8s/gitops/argocd/project.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/gitops/argocd/project.yaml)
- [k8s/gitops/argocd/opensis-dev-application.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/gitops/argocd/opensis-dev-application.yaml)
- [k8s/gitops/argocd/opensis-prod-application.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/gitops/argocd/opensis-prod-application.yaml)
- [k8s/gitops/README.md](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/gitops/README.md)

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

- [k8s/overlays/prod/opensis-ui-ingress-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/opensis-ui-ingress-patch.yaml)
- [k8s/overlays/prod/prometheus-configmap-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/prometheus-configmap-patch.yaml)
- [k8s/overlays/prod/prometheus-deployment-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/prometheus-deployment-patch.yaml)
- [k8s/overlays/prod/prometheus-pvc-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/prometheus-pvc-patch.yaml)
- [k8s/overlays/prod/grafana-deployment-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/grafana-deployment-patch.yaml)
- [k8s/overlays/prod/grafana-pvc-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/prod/grafana-pvc-patch.yaml)

The most important production-specific changes were:

1. Prometheus storage was increased to `20Gi`, retention was set to `15d`, and CPU/memory requests and limits were raised to more realistic production values.
2. Grafana storage was increased to `5Gi`, and Grafana CPU/memory requests and limits were raised above the dev defaults.
3. The production ingress host and the production blackbox HTTP probe target were both changed from the placeholder `opensis.example.com` to the real hostname `opensis.raysosglobal.com`.
4. Grafana admin credentials were removed from inline manifest defaults and moved to Vault so they follow the same secret-delivery model as the rest of the stack.

The Grafana Vault move added these repo pieces:

- [k8s/base/observability/grafana/serviceaccount.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/grafana/serviceaccount.yaml)
- [k8s/base/observability/grafana/deployment.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/base/observability/grafana/deployment.yaml)
- [k8s/overlays/dev/grafana-deployment-patch.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/overlays/dev/grafana-deployment-patch.yaml)
- [k8s/bootstrap/vault/opensis-grafana-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-grafana-policy.hcl)
- [k8s/bootstrap/vault/opensis-grafana-dev-policy.hcl](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/vault/opensis-grafana-dev-policy.hcl)

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
- the production ingress host is `opensis.raysosglobal.com`.
- the production blackbox HTTP probe checks `https://opensis.raysosglobal.com`.
- Prometheus and Grafana have production-sized persistence and resources rather than inheriting only the base defaults.

## Phase 22A: Prepare Cloudflare And Traefik Edge Publication

To move the stack toward real public reachability, the next milestone prepared Cloudflare Tunnel and Traefik in the repo without breaking the currently healthy `nginx`-based dev ingress.

The main repo additions in this phase are:

- [k8s/platform/cloudflare/kustomization.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/kustomization.yaml)
- [k8s/platform/cloudflare/namespace.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/namespace.yaml)
- [k8s/platform/cloudflare/serviceaccount.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/serviceaccount.yaml)
- [k8s/platform/cloudflare/deployment.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/deployment.yaml)
- [k8s/platform/cloudflare/networkpolicy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/networkpolicy.yaml)
- [k8s/platform/cloudflare/secret.example.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/secret.example.yaml)
- [k8s/platform/cloudflare/README.md](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/platform/cloudflare/README.md)
- [k8s/bootstrap/traefik/values.yaml](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/traefik/values.yaml)
- [k8s/bootstrap/traefik/README.md](/home/theinventor/Desktop/devops/devopseasylearning/OpenSIS/k8s/bootstrap/traefik/README.md)

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

- Cloudflare provides the public edge for `opensis.raysosglobal.com`
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
kubectl kustomize k8s/overlays/prod | grep -nE 'kind: Ingress|ingressClassName: traefik|opensis.raysosglobal.com'
```

Expected result:

- the `cloudflare` platform component renders cleanly
- the Argo CD project and applications render cleanly, including `opensis-cloudflare`
- the production ingress renders with:
  - `ingressClassName: traefik`
  - host `opensis.raysosglobal.com`

Cloudflare dashboard setup for the live cutover:

1. create a named tunnel in Cloudflare
2. add the public hostname:
   - `opensis.raysosglobal.com`
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
curl -k -I https://opensis.raysosglobal.com
```

Final outcome of the reconciliation:

- `opensis-prod` moved from `OutOfSync` to `Synced`
- the public URL `https://opensis.raysosglobal.com` returned `HTTP/2 200` again
- the current immutable prod image remained `docker.io/eseosaiyangbe/opensis-ui:git-efd83e6`
- `dev` and `prod` no longer compete for the same kube-state-metrics cluster-scoped RBAC objects

## Environment Summary

Current environment intent is now:

- `dev` is the stable local-learning environment at `https://opensis.dev.local`
- `dev` stays on `nginx` ingress for predictable browser access
- `dev` tracks the CI-backed image stream `docker.io/eseosaiyangbe/opensis-ui:main`
- `prod` is the public-facing environment at `https://opensis.raysosglobal.com`
- `prod` is pinned to the immutable image `docker.io/eseosaiyangbe/opensis-ui:git-efd83e6`
- `prod` uses Traefik plus Cloudflare Tunnel, with the in-cluster origin adapter normalizing public requests before they reach openSIS
- `prod` now uses unique kube-state-metrics cluster-scoped RBAC names so Argo CD can keep `dev` and `prod` synced independently

Promotion rule:

- validate behavior in `dev` first
- promote `prod` only by changing the immutable `git-<sha>` tag in `k8s/overlays/prod/kustomization.yaml`
- verify the live public URL after each promotion

## Updated Remaining Roadmap

The roadmap is now in a post-publication hardening phase. The next live milestone is:

1. continue with restore testing
2. harden Vault TLS
3. revisit the later Vault Raft/auto-unseal work
4. decide whether to keep the origin adapter permanently or fold that normalization into a more deliberate edge layer later

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
- Vault Kubernetes auth method: https://developer.hashicorp.com/vault/docs/auth/kubernetes
- Vault Kubernetes auth bootstrap example: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/examples/kubernetes-auth
