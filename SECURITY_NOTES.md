# Security Notes

## Vault Secret Flow

This stack uses Vault in two stages:

1. `vault-bootstrap`
- initializes and unseals Vault if needed
- creates the AppRoles used by the runtime agents
- writes `role_id` and `secret_id` into Docker-managed runtime volumes

2. `vault-agent-app` and `vault-agent-db`
- authenticate to Vault with AppRole
- render `app.env` and `db.env` from Vault templates
- write those rendered files into shared runtime secret volumes

3. `opensis-ui` and `opensis-db`
- read the rendered files from `/run/secrets`
- do not depend on plaintext secret files in the repo workspace

## Why It Works This Way

The goal is to keep live secret material out of the project directory.

What is intentionally no longer stored in the repo tree:
- rendered `app.env`
- rendered `db.env`
- AppRole `role_id`
- AppRole `secret_id`

What still exists only at runtime:
- AppRole files in Docker-managed runtime volumes
- rendered app/db secret files in shared runtime volumes

## Current Security Posture

Better than before:
- live rendered secret files are no longer written under `./vault-agent/...`
- AppRole files are no longer written under `./vault-agent/...`
- the repo workspace no longer acts as secret storage

Important remaining risk:
- credentials that previously existed in plaintext should still be treated as exposed until rotated

## Operational Summary

From an operator point of view, nothing special changes:

- start Vault and the stack
- `vault-bootstrap` prepares AppRole credentials
- `vault-agent-*` renders runtime secret files
- the app and database read those files from `/run/secrets`

## Portability Notes

This design is reproducible for Docker Compose because it is declared in `docker-compose.yaml`. The default Compose path now pulls the UI from `docker.io/eseosaiyangbe/opensis-ui:dev`, while `docker-compose.buildlocal.yaml` is available when you explicitly want to build the UI locally.

It is not a Kubernetes-native design as-is. In Kubernetes, the equivalent pattern would usually be implemented with:
- Vault Agent Injector
- projected volumes
- Kubernetes Secrets or external secret sync patterns
