# Traefik Bootstrap

This repo keeps Traefik as the intended in-cluster ingress standard for the public Cloudflare edge path.

At the workspace level, Traefik is now the preferred ingress direction for the broader Kubernetes migration story as well.

## Why Traefik Here

- Cloudflare handles the public edge
- Traefik handles in-cluster ingress routing
- `cloudflared` can target Traefik by service DNS inside the cluster

## Current State

Some older workload docs in the monorepo still reference `nginx` ingress examples.
Treat those as transitional materials, not as the current platform direction.

Traefik is the intended ingress standard going forward, and any remaining NGINX references should be read as historical or workload-local learning content until they are fully aligned.

## Suggested Install Shape

Namespace:

```bash
kubectl create namespace traefik
```

Helm values file:

- `k8s/bootstrap/traefik/values.yaml`

Suggested install command:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik   -n traefik   -f k8s/bootstrap/traefik/values.yaml
```

## Safe Cutover Sequence

1. install Traefik and confirm the `traefik` ingress class exists
2. update the application ingress manifests to use `traefik`
3. verify in-cluster routing before introducing Cloudflare Tunnel traffic
4. create the Cloudflare tunnel public hostname `opensis.raysosglobal.com`
5. point the tunnel to the Traefik service
