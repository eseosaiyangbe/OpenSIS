# Traefik Bootstrap

This repo keeps Traefik as the intended in-cluster ingress standard for the public Cloudflare edge path.

## Why Traefik Here

- Cloudflare handles the public edge
- Traefik handles in-cluster ingress routing
- `cloudflared` can target Traefik by service DNS inside the cluster

## Current State

The current live cluster still uses the `nginx` ingress class.

Traefik is being prepared deliberately so the cutover can happen cleanly instead of breaking the currently healthy `opensis-dev` path.

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
