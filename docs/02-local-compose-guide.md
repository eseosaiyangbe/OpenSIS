# 02: Local Compose Guide

This is the simplest way to run the project.

It is the best starting point if you want to:

- understand the app flow
- learn the Vault secret handoff
- avoid Kubernetes complexity at the beginning

This guide works on both:

- Linux
- macOS with Docker Desktop

## What This Stack Starts

By default, `docker compose up -d` starts:

- Vault
- Vault bootstrap
- Vault seed
- Vault agent for the app
- Vault agent for the database
- MariaDB
- openSIS UI

It does not start observability services.

Optional edge services are available behind the `edge` profile:

- Traefik
- Cloudflare Tunnel

## 1. Run The Precheck

From the repo root:

```bash
./scripts/precheck.sh
```

If this fails, fix the reported issue before continuing.

If you are on macOS:

- make sure Docker Desktop is already open
- wait until Docker Desktop shows that it is running before you continue

## 2. Start The Stack

Use the wrapper script for the most portable local start:

```bash
./scripts/compose-start.sh
```

On Linux AMD64, this uses the published `docker.io/eseosaiyangbe/opensis-ui:dev` image. On Apple Silicon/ARM64, it automatically uses `docker-compose.buildlocal.yaml` and builds `opensis-ui` locally because the published dev image does not currently include a `linux/arm64/v8` manifest.

Check status:

```bash
docker compose ps
```

## 3. Open The Services

Local URLs:

- openSIS: `http://localhost:8088`
- Vault: `http://localhost:8200`

## 4. Build The UI Locally Instead Of Pulling

If you are changing application code or the Dockerfile path:

```bash
docker compose -f docker-compose.yaml -f docker-compose.buildlocal.yaml up -d --build
or
./scripts/compose-start.sh --build-local
```

This overrides the default image pull and builds `opensis-ui` locally.

To force the published image path on a compatible platform:

```bash
./scripts/compose-start.sh --pull-image
```

## 5. Optional Edge Mode

If you want Traefik and Cloudflare Tunnel locally:

```bash
./scripts/compose-start.sh --edge
```

Only use this if you specifically need the edge path.

## 6. How Secret Delivery Works Locally

The local Compose flow is:

1. Vault starts
2. `vault-bootstrap` initializes and configures Vault
3. `vault-seed` writes the DB and app secrets
4. Vault agents render secrets into runtime volumes
5. MariaDB and openSIS start using those rendered secret files

That means your app and DB do not read raw secrets from the Compose file directly.

## 7. Useful Checks

Tail the important logs:

```bash
docker compose logs -f vault vault-bootstrap vault-seed opensis-db opensis-ui
```

Check only the app:

```bash
docker compose logs -f opensis-ui
```

Check only the database:

```bash
docker compose logs -f opensis-db
```

## 8. Common Local Commands

Stop everything:

```bash
docker compose down
or
./scripts/compose-stop.sh
```

Stop and remove volumes:

```bash
docker compose down -v
./scripts/compose-stop.sh --volumes
```

Restart only the app:

```bash
docker compose restart opensis-ui
```

Restart the full stack:

```bash
docker compose up -d
docker compose down -v
or
./scripts/compose-stop.sh
./scripts/compose-start.sh
```

## 9. Local Troubleshooting Shortlist

### Port already in use

Common symptom:

- `failed to bind host port`

Check what owns the port:

```bash
ss -ltnp | rg ':8088|:8200|:80'
```

On macOS, use:

```bash
lsof -nP -iTCP:8088 -iTCP:8200 -iTCP:80 | grep LISTEN
```

### Vault bootstrap fails

Check:

```bash
docker compose logs vault vault-bootstrap vault-seed
```

### UI is up but blank or broken

Check:

```bash
docker compose logs opensis-ui
docker compose logs opensis-db
```

If you are on macOS and something looks inconsistent after a first run:

- confirm Docker Desktop is still running
- restart the stack once
- then recheck the logs

### Build path vs pull path confusion

Default:

```bash
./scripts/compose-start.sh
```

Local build:

```bash
./scripts/compose-start.sh --build-local
```

## 10. What Success Looks Like

You are in a good state when:

- `docker compose ps` shows the app, DB, Vault, and agents running
- `http://localhost:8088` opens
- `http://localhost:8200` opens
- logs do not show repeated crash loops

On macOS, the first startup can take slightly longer than Linux because Docker Desktop needs to initialize its VM and networking layer.

## 11. Next Step

After the local stack makes sense, move to:

- [03-kubernetes-bootstrap-guide.md](03-kubernetes-bootstrap-guide.md)
