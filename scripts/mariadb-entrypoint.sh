#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE="/run/secrets/db.env"

until [ -s "$SECRETS_FILE" ]; do
  sleep 2
done

set -a
# shellcheck source=/dev/null
. "$SECRETS_FILE"
set +a

sql_escape_string() {
  printf "%s" "$1" | sed "s/'/''/g"
}

sql_escape_identifier() {
  printf "%s" "$1" | sed "s/\`/\`\`/g"
}

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
      local db_sql app_user_sql app_password_sql grant_sql
      db_sql="$(sql_escape_identifier "$db")"
      app_user_sql="$(sql_escape_string "$app_user")"
      app_password_sql="$(sql_escape_string "$app_password")"
      grant_sql="$(printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'%%' IDENTIFIED BY '%s'; FLUSH PRIVILEGES;" "$db_sql" "$app_user_sql" "$app_password_sql")"

      echo "[mariadb-entrypoint] Ensuring grants for ${app_user} on ${db}.*"
      mysql -u root -p"$root_password" -e "$grant_sql"
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
