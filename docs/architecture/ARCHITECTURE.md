# OpenSIS Platform Architecture

![OpenSIS platform architecture](opensis-platform-architecture.png)

This document is the architecture design of record for the Secure OpenSIS Platform: a legacy application wrapped with modern delivery, secrets, observability, and recovery, without rewriting the application. The image above is rendered from the Mermaid source in this file, so the picture and the source never drift apart. The repository's Architecture Reference (`docs/06-architecture-reference.md`) remains the deep dive for traffic flow, secrets flow, and design decisions.

## The design in one paragraph

openSIS Classic, a PHP and Apache monolith, runs on Kubernetes behind Cloudflare Tunnel and Traefik ingress. It was not rewritten. HashiCorp Vault is the secret source of truth, and the Vault Agent Injector renders four credential sets (database root password, application database password, database exporter password, Grafana administrator password) into the files the legacy application expects at startup, so credentials never appear in Git or plain manifests. MariaDB holds the data, with a database exporter feeding Prometheus, and backup jobs paired with a documented restore procedure that has been executed, not only configured. Delivery runs four lanes: validate; publish to Docker Hub with immutable git-sha tags, SBOM, Trivy, and Cosign signing; smoke verification of the public dev edge; and a manual, held prod promotion, with Argo CD applications for dev and prod. Validation is the live audit (39 of 39 checks, Phase 6 lab audit), the Vault unavailable drill, and post restart recovery verification in the order reachability, database health, Vault state. Vault is a startup dependency by design: explicit, monitored, and drilled.

## Architecture diagram, Mermaid source

```mermaid
flowchart TB
    User["User"]
    Operator["Operator"]

    subgraph Edge["Edge and ingress"]
        CF["Cloudflare Tunnel<br/>opensis.eseosadevbox.com"]
        Traefik["Traefik ingress"]
    end

    subgraph Cluster["Kubernetes on k3s, OpenSIS workload"]
        subgraph App["Application, not rewritten"]
            Agent["Vault Agent Injector<br/>Renders secrets as files<br/>the legacy app expects"]
            UI["openSIS Classic<br/>PHP and Apache workload"]
            Agent -->|"rendered credentials<br/>at startup"| UI
        end

        subgraph Data["Data"]
            MariaDB["MariaDB<br/>Student information data"]
            Exporter["Database exporter<br/>Metrics for MariaDB"]
            Backup["Backup jobs<br/>Documented restore<br/>procedure, executed"]
            MariaDB --> Exporter
            MariaDB --> Backup
        end

        subgraph Obs["Observability, shared platform stack"]
            Prom["Prometheus<br/>Application and<br/>database metrics"]
            Grafana["Grafana<br/>Dashboards"]
            Alerts["Alerting<br/>Through the platform stack"]
        end

        UI --> MariaDB
    end

    subgraph Secrets["Secrets, Vault first"]
        Vault["HashiCorp Vault<br/>Source of truth"]
        Creds["Four credential sets<br/>Database root, application<br/>database, exporter,<br/>Grafana administrator"]
        Vault --> Creds
        Creds --> Agent
    end

    subgraph Delivery["Delivery, four lanes"]
        Git["Git repository<br/>Kustomize overlays<br/>Dev, staging, production<br/>style configuration"]
        CI["Validate, publish to Docker Hub<br/>Immutable git-sha tags, SBOM,<br/>Trivy, Cosign signing"]
        Smoke["Smoke dev public<br/>Verifies the live dev edge"]
        Promote["Promote prod<br/>Manual, held contract"]
        ArgoCD["Argo CD<br/>Dev and prod applications"]
        Git --> CI
        CI --> ArgoCD
        ArgoCD --> Cluster
        Smoke --> CF
        Promote --> ArgoCD
    end

    subgraph Validation["Validation and recovery"]
        Audit["OpenSIS live audit<br/>39 of 39, Phase 6 lab audit"]
        Drill["Vault unavailable drill<br/>Impact observed,<br/>recovery verified"]
        Recovery["Post restart recovery<br/>Reachability, database<br/>health, Vault state"]
        Audit --> UI
        Audit --> MariaDB
        Audit --> Vault
        Drill --> Vault
        Recovery --> Cluster
    end

    User --> CF
    CF --> Traefik
    Traefik --> UI
    UI -->|"application and<br/>database telemetry"| Prom
    Exporter --> Prom
    Prom --> Grafana
    Prom --> Alerts
    Grafana --> Operator
    Alerts --> Operator
```

## Flow diagram: secret delivery and recovery, Mermaid source

```mermaid
flowchart LR
    subgraph SecretFlow["Secret flow, every startup"]
        A["Workload starts"] --> B["Vault Agent authenticates<br/>to Vault"]
        B --> C["Agent renders templates<br/>Four credential sets"]
        C --> D["Application starts with<br/>credentials that never<br/>appear in Git"]
    end

    subgraph RecoveryFlow["Recovery flow"]
        E["Restore MariaDB<br/>from backup"] --> F["Restart the workload"]
        F --> G["Validate reachability"]
        G --> H["Validate database health"]
        H --> I["Validate Vault state"]
        I --> J["Declare recovery"]
    end
```

## Notes

- The application itself is the existing open source openSIS Classic. Credit for the application belongs to its authors; the engineering recorded here is the platform wrapper, secrets, delivery, observability, and recovery work.
- This is a lab environment deployment. Production style configuration is a configuration model, not a claim of production use by a school or institution.
- Live application: `https://opensis.eseosadevbox.com`.
