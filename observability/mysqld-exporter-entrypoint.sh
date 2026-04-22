#!/bin/sh
set -eu

: "${MYSQL_EXPORTER_USER:=opensis_exporter}"
: "${MYSQL_EXPORTER_PASSWORD:?Missing MYSQL_EXPORTER_PASSWORD}"

cat > /tmp/mysqld-exporter.cnf <<EOF
[client]
host=opensis-db
port=3306
user=${MYSQL_EXPORTER_USER}
password=${MYSQL_EXPORTER_PASSWORD}
EOF

chmod 0400 /tmp/mysqld-exporter.cnf

exec /bin/mysqld_exporter \
  --config.my-cnf=/tmp/mysqld-exporter.cnf \
  --mysqld.address=opensis-db:3306 \
  --no-collect.slave_status \
  --web.listen-address=:9104 \
  "$@"
