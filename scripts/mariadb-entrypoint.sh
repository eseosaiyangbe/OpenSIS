#!/usr/bin/env bash
set -e

SECRETS_FILE="/run/secrets/db.env"

until [ -s "$SECRETS_FILE" ]; do
  sleep 2
done

set -a
. "$SECRETS_FILE"
set +a

exec docker-entrypoint.sh mysqld