log_level = "info"

exit_after_auth = false

retry {
  num_retries = -1
}

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/vault/approle/role_id"
      secret_id_file_path = "/vault/approle/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/.vault-token"
      mode = 0600
    }
  }
}

template_config {
  static_secret_render_interval = "5m"
}

template {
  source      = "/vault/templates/db.env.tpl"
  destination = "/vault/secrets/db.env"
  perms       = 0640
  error_on_missing_key = true
}