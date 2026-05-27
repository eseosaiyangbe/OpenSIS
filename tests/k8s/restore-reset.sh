#!/usr/bin/env sh
set -eu

NAMESPACE="${NAMESPACE:-opensis-dev}"
DB_POD="${DB_POD:-opensis-db-0}"

kubectl exec -n "$NAMESPACE" "$DB_POD" -- sh -eu -c '
  . /opt/opensis/secrets/db.env
  : "${MYSQL_ROOT_PASSWORD:?Missing MYSQL_ROOT_PASSWORD}"

  pick_db() {
    for candidate in opensis openSIS "${MYSQL_DATABASE:-}"; do
      [ -n "$candidate" ] || continue
      if ! mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -Nse "SHOW DATABASES" | grep -qx "$candidate"; then
        continue
      fi
      if mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -Nse "SELECT 1 FROM information_schema.tables WHERE table_schema = \"$candidate\" AND table_name = \"app\" LIMIT 1" | grep -qx 1; then
        echo "$candidate"
        return 0
      fi
    done

    for candidate in opensis openSIS "${MYSQL_DATABASE:-}"; do
      [ -n "$candidate" ] || continue
      if mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -Nse "SHOW DATABASES" | grep -qx "$candidate"; then
        echo "$candidate"
        return 0
      fi
    done

    return 1
  }

  target_db="$(pick_db)"
  : "${target_db:?Unable to determine restore target database}"
  echo "Resetting database ${target_db} before restore"
  mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`${target_db}\`; CREATE DATABASE \`${target_db}\`;"
'
