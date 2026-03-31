#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE="/run/secrets/db.env"

until [ -s "$SECRETS_FILE" ]; do
  sleep 2
done

set -a
. "$SECRETS_FILE"
set +a

reconcile_grants() {
  local root_password="${MYSQL_ROOT_PASSWORD:?Missing MYSQL_ROOT_PASSWORD}"
  local app_user="${MYSQL_USER:?Missing MYSQL_USER}"
  local app_password="${MYSQL_PASSWORD:?Missing MYSQL_PASSWORD}"
  local bootstrap_db="${MYSQL_DATABASE:-}"

  local candidates=()
  if [ -n "$bootstrap_db" ]; then
    candidates+=("$bootstrap_db")
  fi
  candidates+=("opensis" "openSIS")

  local db
  for db in "${candidates[@]}"; do
    [ -n "$db" ] || continue

    if mysql -u root -p"$root_password" -Nse "SHOW DATABASES LIKE '$db'" | grep -qx "$db"; then
      echo "[mariadb-entrypoint] Ensuring grants for ${app_user} on ${db}.*"
      mysql -u root -p"$root_password" <<SQL
GRANT ALL PRIVILEGES ON \
\\`${db//\`/\`\`}\\`.* TO '${app_user}'@'%' IDENTIFIED BY '${app_password//\'/\'\'}';
FLUSH PRIVILEGES;
SQL
    fi
  done
}

/usr/local/bin/docker-entrypoint.sh mysqld &
pid=$!

for _ in $(seq 1 60); do
  if mysqladmin ping -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" --silent >/dev/null 2>&1; then
    reconcile_grants || true
    break
  fi
  sleep 2
done

wait "$pid"
