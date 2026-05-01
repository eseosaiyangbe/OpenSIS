#!/bin/sh
set -eu

if [ -f /opt/opensis/secrets/db.env ]; then
  # shellcheck disable=SC1091
  . /opt/opensis/secrets/db.env
fi

: "${MYSQL_EXPORTER_USER:=opensis_exporter}"
: "${MYSQL_EXPORTER_PASSWORD:=${MYSQL_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}}"
: "${MYSQL_EXPORTER_PASSWORD:?Missing MYSQL_EXPORTER_PASSWORD}"
: "${MYSQL_EXPORTER_HOST:=opensis-db}"
: "${MYSQL_EXPORTER_PORT:=3306}"

cat > /tmp/mysqld-exporter.cnf <<EOF
[client]
host=${MYSQL_EXPORTER_HOST}
port=${MYSQL_EXPORTER_PORT}
user=${MYSQL_EXPORTER_USER}
password=${MYSQL_EXPORTER_PASSWORD}
EOF

chmod 0400 /tmp/mysqld-exporter.cnf

exec /bin/mysqld_exporter \
  --config.my-cnf=/tmp/mysqld-exporter.cnf \
  --mysqld.address=${MYSQL_EXPORTER_HOST}:${MYSQL_EXPORTER_PORT} \
  --no-collect.slave_status \
  --web.listen-address=:9104 \
  "$@"
