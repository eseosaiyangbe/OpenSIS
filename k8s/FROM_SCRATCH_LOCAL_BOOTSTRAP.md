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

This repo now includes a starter config at [k8s/bootstrap/k3s/config.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/bootstrap/k3s/config.yaml).

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

This repo now includes a starter values file at [k8s/bootstrap/vault-values.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/bootstrap/vault-values.yaml).

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
  MYSQL_USER="opensis_user" \
  MYSQL_PASSWORD="change-me" \
  DB_HOST="opensis-db.opensis.svc.cluster.local" \
  DB_PORT="3306"
```

DB secret:

```bash
vault kv put kv/production/opensis-db \
  MYSQL_ROOT_PASSWORD="change-me-root" \
  MYSQL_DATABASE="opensis" \
  MYSQL_USER="opensis_user" \
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

- [k8s/base/opensis-ui/deployment.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/opensis-ui/deployment.yaml)

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

That change now exists in [k8s/base/opensis-ui/ingress.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/opensis-ui/ingress.yaml).

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

Right now [k8s/base/opensis-ui/ingress.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/opensis-ui/ingress.yaml) references the secret `opensis-ui-tls`, but that secret does not exist yet. That is why cert-manager is the next step in the journey.

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

This repo includes a starter issuer manifest at [k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml).

Apply it:

```bash
kubectl apply -f k8s/bootstrap/cert-manager/selfsigned-clusterissuer.yaml
kubectl get clusterissuer
```

The ingress is already prepared to use that issuer:

- [k8s/base/opensis-ui/ingress.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/opensis-ui/ingress.yaml)

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

After cert-manager is working, the next clean step is to separate local-learning behavior from production intent with Kustomize overlays.

This repo now includes:

- [k8s/overlays/dev/kustomization.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/overlays/dev/kustomization.yaml)
- [k8s/overlays/prod/kustomization.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/overlays/prod/kustomization.yaml)
- [k8s/overlays/README.md](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/overlays/README.md)

The `dev` overlay currently changes:

- namespace to `opensis-dev`
- `APP_ENV` to `dev`
- Vault roles and paths to `opensis-app-dev` / `opensis-db-dev`
- ingress host to `opensis.dev.local`
- issuer to `local-selfsigned`
- DB storage and resource sizes for a smaller lab footprint
- app image to `opensis-ui:dev`

### Prepare Vault for the dev overlay

The `dev` overlay is not just a namespace change. It assumes separate Vault roles, secret paths, and service-account bindings.

Create the namespace and service accounts:

```bash
kubectl create namespace opensis-dev
kubectl create serviceaccount opensis-ui -n opensis-dev
kubectl create serviceaccount opensis-db -n opensis-dev
kubectl get serviceaccount -n opensis-dev
```

Inside the Vault pod, create the dev policies:

```bash
cat <<'EOF' > /tmp/opensis-app-dev-policy.hcl
path "kv/data/dev/opensis-app" {
  capabilities = ["read"]
}
EOF

vault policy write opensis-app-dev /tmp/opensis-app-dev-policy.hcl
```

```bash
cat <<'EOF' > /tmp/opensis-db-dev-policy.hcl
path "kv/data/dev/opensis-db" {
  capabilities = ["read"]
}
EOF

vault policy write opensis-db-dev /tmp/opensis-db-dev-policy.hcl
```

Create the dev roles:

```bash
vault write auth/kubernetes/role/opensis-app-dev \
  bound_service_account_names=opensis-ui \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-app-dev \
  ttl=1h
```

```bash
vault write auth/kubernetes/role/opensis-db-dev \
  bound_service_account_names=opensis-db \
  bound_service_account_namespaces=opensis-dev \
  policies=opensis-db-dev \
  ttl=1h
```

Seed the dev secrets:

```bash
vault kv put kv/dev/opensis-app \
  MYSQL_DATABASE="opensis_dev" \
  MYSQL_USER="opensis_rw" \
  MYSQL_PASSWORD="change-me-dev" \
  DB_HOST="opensis-db.opensis-dev.svc.cluster.local" \
  DB_PORT="3306"
```

```bash
vault kv put kv/dev/opensis-db \
  MYSQL_ROOT_PASSWORD="change-me-root-dev" \
  MYSQL_DATABASE="opensis_dev" \
  MYSQL_USER="opensis_rw" \
  MYSQL_PASSWORD="change-me-dev"
```

### Apply the dev overlay

```bash
kubectl apply -k k8s/overlays/dev
kubectl get pods -n opensis-dev
kubectl get svc -n opensis-dev
kubectl get ingress -n opensis-dev
kubectl get certificate -n opensis-dev
```

Test the dev ingress locally:

```bash
curl -I -H 'Host: opensis.dev.local' http://192.168.2.132
```

In our run, the dev ingress became available and returned:

- `308 Permanent Redirect`

That confirmed the `dev` overlay routing and TLS secret wiring were correct.

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
kubectl delete pod -n opensis-dev -l app=opensis-ui
kubectl delete pod -n opensis-dev -l app=opensis-db
kubectl get pods -n opensis-dev -w
```

Success signal:

- recreated pods showed `vault-agent-init`
- `vault.hashicorp.com/agent-inject-status: injected`
- `/run/secrets` was mounted
- the `opensis-ui` pod became `Ready`

### Current result

At the end of the dev overlay test:

- `opensis-dev` namespace is working
- dev-specific Vault roles and secret paths are working
- dev ingress is working
- dev TLS secret is issued by cert-manager
- the overlay model itself is validated

This makes the next step much safer: shaping the `prod` overlay deliberately instead of treating it as theory only.

## Phase 17: Add and Validate NetworkPolicy

After the overlays were in place, the next roadmap item was `NetworkPolicy`.

The goal of this first policy layer is modest and intentional:

- default deny inside the application namespace
- only allow ingress to `opensis-ui` from `ingress-nginx`
- only allow ingress to `opensis-db` from `opensis-ui`
- only allow the egress paths the app and DB need right now

This repo now includes:

- [k8s/base/networking/default-deny.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/networking/default-deny.yaml)
- [k8s/base/networking/opensis-ui-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/networking/opensis-ui-policy.yaml)
- [k8s/base/networking/opensis-db-policy.yaml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/k8s/base/networking/opensis-db-policy.yaml)

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

Apply the policies by applying the overlay again:

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

## Updated Remaining Roadmap

At this point, the completed milestones are:

1. base cluster bootstrap
2. Vault integration
3. cert-manager
4. overlays
5. NetworkPolicy

The remaining roadmap items are now:

1. pin app images in a real registry workflow
2. add DB backups
3. add observability as a separate layer
4. then revisit the `prod` overlay and shape it more deliberately

## Phase 18: Pin App Images In A Real Registry Workflow

After the networking layer was validated, the next roadmap item became the image workflow.

For this repo, the chosen direction is:

- GitHub Actions for build automation
- Docker Hub as the image registry

This keeps the local learning path simple while giving the project a real promotion path for later environments.

The workflow now lives at:

- [.github/workflows/dockerhub-opensis-ui.yml](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/.github/workflows/dockerhub-opensis-ui.yml)

The supporting notes live at:

- [IMAGE_WORKFLOW.md](/home/theinventor/Desktop/devops/devopseasylearning/Dev_test2/IMAGE_WORKFLOW.md)

Set these in your GitHub repository before using the workflow:

- repository variable: `DOCKERHUB_USERNAME`
- repository variable: `DOCKERHUB_REPOSITORY`
- repository secret: `DOCKERHUB_TOKEN`

The workflow publishes:

- branch tags
- git SHA tags prefixed with `git-`
- release tags like `v1.0.0`

The workflow intentionally avoids `latest`.

### Current overlay state

- `dev` still uses the local-learning image tag `opensis-ui:dev`
- `prod` now points at a Docker Hub-shaped placeholder image path

Before using the `prod` overlay for real, replace:

- `docker.io/eseosaiyangbe/opensis-ui:v1.0.0`

with the exact tag you actually publish.

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
