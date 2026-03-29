{{- $env := env "APP_ENV" -}}
{{- with secret (printf "kv/%s/opensis-db" $env) -}}
{{- $data := .Data.data -}}
MYSQL_ROOT_PASSWORD={{ $data.MYSQL_ROOT_PASSWORD }}
MYSQL_DATABASE={{ $data.MYSQL_DATABASE }}
MYSQL_USER={{ $data.MYSQL_USER }}
MYSQL_PASSWORD={{ $data.MYSQL_PASSWORD }}
{{- end -}}