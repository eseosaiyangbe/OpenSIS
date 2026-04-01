# Cloudflare Tunnel

This layer prepares a dedicated `cloudflare` namespace for `cloudflared`.

It is intentionally separate from the `opensis` workload namespace.

## Design Intent

- Cloudflare provides the public edge for `opensis.raysosglobal.com`
- Traefik remains the in-cluster ingress controller
- `cloudflared` runs inside Kubernetes and connects outward to Cloudflare
- the tunnel should target Traefik once Traefik is installed and cut over

## Files

- `namespace.yaml`: dedicated `cloudflare` namespace
- `serviceaccount.yaml`: service account for `cloudflared`
- `deployment.yaml`: token-based `cloudflared` Deployment
- `networkpolicy.yaml`: egress only to DNS and outbound HTTPS
- `secret.example.yaml`: example tunnel-token Secret

## Prepare The Tunnel Token Secret

Create the real Secret from the example after you create a named tunnel in Cloudflare:

```bash
cp k8s/platform/cloudflare/secret.example.yaml /tmp/cloudflared-tunnel.yaml
# edit /tmp/cloudflared-tunnel.yaml and replace the token value
kubectl apply -f /tmp/cloudflared-tunnel.yaml
```

## Apply The Namespace And Deployment

```bash
kubectl apply -k k8s/platform/cloudflare
```

## Safe Cutover Note

Do not route public traffic to the tunnel yet unless Traefik is installed and the application ingress has been intentionally cut over from the current `nginx` ingress class during the live cutover.
