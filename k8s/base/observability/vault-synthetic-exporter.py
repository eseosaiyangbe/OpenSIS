#!/usr/bin/env python3
import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://vault:8200").rstrip("/")
APP_ENV = os.environ.get("APP_ENV", "dev")
LISTEN_PORT = int(os.environ.get("PORT", "9105"))
VAULT_K8S_ROLE = os.environ.get("VAULT_K8S_ROLE", "").strip()
VAULT_K8S_TOKEN_FILE = os.environ.get(
    "VAULT_K8S_TOKEN_FILE",
    "/var/run/secrets/kubernetes.io/serviceaccount/token",
)

CHECKS = (
    {
        "name": "opensis-app",
        "path": f"kv/data/devops-easy-learning/opensis/{APP_ENV}/app",
        "approle_dir": "/vault/approle-app",
    },
    {
        "name": "opensis-db",
        "path": f"kv/data/devops-easy-learning/opensis/{APP_ENV}/db",
        "approle_dir": "/vault/approle-db",
    },
)


def request_json(method, path, body=None, token=None, timeout=5):
    data = None
    headers = {"Accept": "application/json"}

    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    if token:
        headers["X-Vault-Token"] = token

    request = urllib.request.Request(
        f"{VAULT_ADDR}/v1/{path.lstrip('/')}",
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = response.read().decode("utf-8")
            return response.status, json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        payload = error.read().decode("utf-8")
        try:
            parsed = json.loads(payload) if payload else {}
        except json.JSONDecodeError:
            parsed = {"error": payload}
        return error.code, parsed
    except Exception as error:
        return 0, {"error": str(error)}


def read_file(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def approle_login(approle_dir):
    try:
        role_id = read_file(os.path.join(approle_dir, "role_id"))
        secret_id = read_file(os.path.join(approle_dir, "secret_id"))
    except OSError as error:
        return False, "", f"approle credential read failed for {approle_dir}: {error}"

    status, payload = request_json(
        "POST",
        "auth/approle/login",
        {"role_id": role_id, "secret_id": secret_id},
    )

    token = payload.get("auth", {}).get("client_token")
    if status == 200 and token:
        return True, token, ""

    return False, "", payload.get("errors", payload.get("error", "approle login failed"))


def kubernetes_login():
    try:
        jwt = read_file(VAULT_K8S_TOKEN_FILE)
    except OSError as error:
        return False, "", f"kubernetes auth token read failed: {error}"

    status, payload = request_json(
        "POST",
        "auth/kubernetes/login",
        {"role": VAULT_K8S_ROLE, "jwt": jwt},
    )

    token = payload.get("auth", {}).get("client_token")
    if status == 200 and token:
        return True, token, ""

    return False, "", payload.get("errors", payload.get("error", "kubernetes login failed"))


def check_vault_health():
    status, payload = request_json("GET", "sys/health")
    initialized = bool(payload.get("initialized"))
    sealed = bool(payload.get("sealed", True))
    healthy_status = status in (200, 429)

    return {
        "up": 1 if healthy_status else 0,
        "initialized": 1 if initialized else 0,
        "sealed": 1 if sealed else 0,
        "unsealed": 1 if initialized and not sealed and healthy_status else 0,
        "status_code": status,
    }


def check_secret_read(check):
    if VAULT_K8S_ROLE:
        login_ok, token, login_error = kubernetes_login()
    else:
        login_ok, token, login_error = approle_login(check["approle_dir"])

    if not login_ok:
        return {
            "success": 0,
            "status_code": 0,
            "error": str(login_error),
        }

    status, payload = request_json("GET", check["path"], token=token)
    has_data = bool(payload.get("data", {}).get("data"))

    return {
        "success": 1 if status == 200 and has_data else 0,
        "status_code": status,
        "error": "" if status == 200 and has_data else str(payload.get("errors", payload.get("error", "secret read failed"))),
    }


def collect_metrics():
    now = int(time.time())
    health = check_vault_health()
    lines = [
        "# HELP opensis_vault_health_status Vault API is reachable, initialized, and unsealed.",
        "# TYPE opensis_vault_health_status gauge",
        f"opensis_vault_health_status {health['unsealed']}",
        "# HELP opensis_vault_api_up Vault API health endpoint responded with an acceptable status.",
        "# TYPE opensis_vault_api_up gauge",
        f"opensis_vault_api_up {health['up']}",
        "# HELP opensis_vault_sealed Vault sealed status from sys/health.",
        "# TYPE opensis_vault_sealed gauge",
        f"opensis_vault_sealed {health['sealed']}",
        "# HELP opensis_vault_health_status_code Vault sys/health HTTP status code.",
        "# TYPE opensis_vault_health_status_code gauge",
        f"opensis_vault_health_status_code {health['status_code']}",
        "# HELP opensis_vault_secret_read_success OpenSIS Vault secret path is readable through its AppRole.",
        "# TYPE opensis_vault_secret_read_success gauge",
        "# HELP opensis_vault_secret_read_status_code HTTP status code for each OpenSIS Vault secret read.",
        "# TYPE opensis_vault_secret_read_status_code gauge",
    ]

    for check in CHECKS:
        result = check_secret_read(check)
        labels = f'secret="{check["name"]}",path="{check["path"]}"'
        lines.append(f"opensis_vault_secret_read_success{{{labels}}} {result['success']}")
        lines.append(f"opensis_vault_secret_read_status_code{{{labels}}} {result['status_code']}")

    lines.extend(
        [
            "# HELP opensis_vault_synthetic_check_timestamp_seconds Last synthetic Vault check time.",
            "# TYPE opensis_vault_synthetic_check_timestamp_seconds gauge",
            f"opensis_vault_synthetic_check_timestamp_seconds {now}",
            "",
        ]
    )
    return "\n".join(lines)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        body = collect_metrics().encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


def main():
    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"opensis-vault-synthetic-exporter listening on {LISTEN_PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
