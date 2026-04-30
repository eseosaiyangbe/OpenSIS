# Cloudflare Tunnel

This layer prepares a dedicated `cloudflare` namespace for `cloudflared` and is intended to be managed through Argo CD.

It is intentionally separate from the `opensis` workload namespace.

## Design Intent

- Cloudflare provides the public edge for `opensis.raysosglobal.com`
- Traefik remains the in-cluster ingress controller for the public path
- `cloudflared` runs inside Kubernetes and connects outward to Cloudflare
- the tunnel token is stored in Vault instead of a plain Kubernetes Secret
- in this single-node lab, the tunnel should target Traefik through its NodePort instead of the ClusterIP Service
- the tunnel should never point directly at the app pod

## Files

- `namespace.yaml`: dedicated `cloudflare` namespace
- `serviceaccount.yaml`: service account for `cloudflared`
- `deployment.yaml`: Vault-injected `cloudflared` Deployment with readiness/liveness probes
- `networkpolicy.yaml`: egress only to Vault, DNS, Cloudflare edge, Traefik, and the Traefik NodePort used in this single-node lab
- `secret.example.yaml`: legacy fallback example only; Vault is the preferred path

## Cloudflare Dashboard Setup

Create a named tunnel in the Cloudflare dashboard and add this public hostname:

- hostname: `opensis.raysosglobal.com`
- service: `http://<NODE_IP>:30621`

Use the Kubernetes node IP for `<NODE_IP>`. In this single-node k3s lab, `cloudflared` could not reliably reach the Traefik ClusterIP Service, but it could reach Traefik cleanly through the NodePort. You can discover the values with:

```bash
kubectl get nodes -o wide
kubectl get svc -n traefik
```

That keeps Cloudflare pointed at Traefik instead of a specific app pod while matching the network path that actually works in this lab.

## Vault Setup

Seed the tunnel token in Vault:

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside Vault:

```bash
vault kv put kv/production/cloudflare \
  TUNNEL_TOKEN='replace-with-your-cloudflare-tunnel-token'
```

Load the policy into Vault:

```bash
kubectl cp k8s/bootstrap/vault/opensis-cloudflare-policy.hcl vault/vault-0:/tmp/opensis-cloudflare-policy.hcl
kubectl exec -it -n vault vault-0 -- /bin/sh
```

Inside Vault:

```bash
vault policy write opensis-cloudflare /tmp/opensis-cloudflare-policy.hcl

vault write auth/kubernetes/role/opensis-cloudflare \
  bound_service_account_names=cloudflared \
  bound_service_account_namespaces=cloudflare \
  policies=opensis-cloudflare \
  ttl=1h
```

## Apply Through GitOps

The namespace-scoped platform component is tracked by the Argo CD application `opensis-cloudflare`.

Apply or refresh the Argo CD objects:

```bash
kubectl apply -k k8s/gitops/argocd
kubectl annotate application opensis-cloudflare -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

Then validate:

```bash
kubectl get applications.argoproj.io -n argocd
kubectl get all -n cloudflare
kubectl logs -n cloudflare deploy/cloudflared --tail=100
```

## Safe Cutover Note

Do not expect public traffic to work until all of these are true:

- Traefik is installed
- the production ingress is intentionally bound to `traefik`
- the Cloudflare dashboard hostname is mapped to the Traefik NodePort origin for this single-node lab
- Vault contains the real tunnel token at `kv/production/cloudflare`
- the `opensis-cloudflare` pod is healthy in the `cloudflare` namespace
