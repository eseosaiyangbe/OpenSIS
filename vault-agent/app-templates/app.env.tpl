{{- $env := env "APP_ENV" -}}
{{- with secret (printf "kv/%s/opensis-app" $env) -}}
{{- $data := .Data.data -}}
MYSQL_DATABASE={{ $data.MYSQL_DATABASE }}
MYSQL_USER={{ $data.MYSQL_USER }}
MYSQL_PASSWORD={{ $data.MYSQL_PASSWORD }}
DB_HOST={{ $data.DB_HOST }}
DB_PORT={{ $data.DB_PORT }}
{{- end -}}