# Observability Stack

This folder contains monitoring and visualization tools for the openSIS stack.

## Services

### Prometheus
- **URL**: http://localhost:9090
- **Purpose**: Metrics collection and storage
- **Configuration**: `prometheus/prometheus.yml`

### Alertmanager
- **URL**: http://localhost:9093
- **Purpose**: Alert routing, grouping, silencing, and status inspection
- **Configuration**: `alertmanager/alertmanager.yml`

### Loki
- **URL**: http://localhost:3100
- **Purpose**: Centralized log storage and querying
- **Configuration**: `loki/loki-config.yml`

### Promtail
- **Purpose**: Collect Docker and host logs and ship them to Loki
- **Configuration**: `promtail/promtail-config.yml`

### Grafana
- **URL**: http://localhost:3000 or http://grafana.raysosglobal.com
- **Admin Credentials**:
  - Username: `admin`
  - Password: `${GRAFANA_ADMIN_PASSWORD:-admin}` (set in .env or defaults to 'admin')
- **Purpose**: Dashboards and visualization
- **Configuration**:
  - Datasources: `grafana/provisioning/datasources/`
  - Dashboards: `grafana/provisioning/dashboards/`
  - Custom dashboards: `grafana/dashboards/`

## Dashboards

### openSIS Stack Overview
- Stack health and probe status
- Container CPU and memory usage
- Database connections and slow queries
- Host CPU, memory, disk, and load
- openSIS/Grafana probe latency

## Access

- **Grafana**: Available at http://localhost:3000 (direct) or through Traefik at http://grafana.raysosglobal.com
- **Prometheus**: Available at http://localhost:9090
- **Alertmanager**: Available at http://localhost:9093
- **Loki**: Available at http://localhost:3100

## Environment Variables

Set these in your `.env` file:

```bash
# Grafana admin password (optional, defaults to 'admin')
GRAFANA_ADMIN_PASSWORD=your_secure_password
```
