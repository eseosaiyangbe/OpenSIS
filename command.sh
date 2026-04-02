 #Create Network
 docker network create opensis-network
 
 
 ===================================================================================================
 #BACKEND
 ===================================================================================================
 #This Command Create a Maria DB For This Project And Was Added November 2, 2025 by Raymond
 docker run -d \
  --name opensis-db \
  --network opensis-network \
  --restart unless-stopped \
  -e MYSQL_ROOT_PASSWORD=Raymond@123 \
  -e MYSQL_DATABASE=opensis \
  -e MYSQL_USER=opensis_rw \
  -e MYSQL_PASSWORD='Op3nS!S' \
  -p 3304:3306 \
  -v $(pwd)/MYSQL/mysql-config/strict_mode.cnf:/etc/mysql/conf.d/strict-mode.cnf \
  mariadb:10.5


  #Run This To Exec Into opensis-db
  docker exec -it opensis-db bash

  #Run
  mysql -u  root -p

  #Enter Password
  Raymond@123

  #Run The Following to Grant Privilege To opensis_rw User Created 
DROP DATABASE IF EXISTS opensis;
CREATE DATABASE opensis DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON opensis.* TO 'opensis_rw'@'%' IDENTIFIED BY 'Op3nS!S';
FLUSH PRIVILEGES;

=========================================================================================
#FRONTEND
=========================================================================================

#Run the following
docker build -t opensis-ui .
docker run -d --name opensis-ui --network opensis-network -p 8080:80 opensis-ui

#Test Your Application
localhost:8080


======================================================================================================
#Production Grade - Docker Compose
======================================================================================================

#Save as docker-compose.ymal
services:
  opensis-db:
    image: mariadb:10.5
    container_name: opensis-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: Raymond@123
      MYSQL_DATABASE: opensis
      MYSQL_USER: opensis_rw
      MYSQL_PASSWORD: Op3nS!S
    ports:
      - "3304:3306"
    volumes:
      - db_data:/var/lib/mysql
      - ./MYSQL/mysql-config/strict_mode.cnf:/etc/mysql/conf.d/strict-mode.cnf:ro
    networks:
      - opensis-network

  opensis-ui:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: opensis-ui
    restart: unless-stopped
    depends_on:
      - opensis-db
    ports:
      - "8080:80"
    networks:
      - opensis-network

networks:
  opensis-network:
    external: true  # reuse the pre-created network

volumes:
  db_data:
    driver: local



    #OR (Preferred by me)

services:
  opensis-db:
    image: mariadb:10.5
    container_name: opensis-db
    restart: unless-stopped
    env_file: [.env.db]
    ports: ["3304:3306"]
    volumes:
      - db_data:/var/lib/mysql
      - ./MYSQL/mysql-config/strict_mode.cnf:/etc/mysql/conf.d/strict-mode.cnf:ro
      - ./MYSQL/mysql-init:/docker-entrypoint-initdb.d:ro
    networks: [opensis-network]
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -p\"$$MYSQL_ROOT_PASSWORD\" --silent"]
      interval: 5s
      timeout: 3s
      retries: 10

  opensis-ui:
    build: { context: ., dockerfile: Dockerfile }
    container_name: opensis-ui
    restart: unless-stopped
    depends_on:
      opensis-db:
        condition: service_healthy
    env_file: [.env.ui]
    ports: ["8080:80"]
    networks: [opensis-network]

networks:
  opensis-network:
    external: true

volumes:
  db_data:
    driver: local 


#Run This To Exec Into opensis-db
docker exec -it opensis-db bash

#Run
mysql -u  root -p

#Enter Password
Raymond@123

#Run The Following to Grant Privilege To opensis_rw User Created 
DROP DATABASE IF EXISTS opensis;
CREATE DATABASE opensis DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON opensis.* TO 'opensis_rw'@'%' IDENTIFIED BY 'Op3nS!S';
FLUSH PRIVILEGES;


#Test Your Application
localhost:8080



======================================================================================================
#NOTE TO BE EXPERIMENT BY ME
======================================================================================================
FROM php:8.2-apache

# Install system packages needed to compile PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    libldap2-dev \
    libzip-dev \
    libxml2-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libonig-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Enable required PHP extensions
# - mysqli: MySQLi driver
# - pdo_mysql: PDO driver for MySQL (needed by installer / DB layer)
# - ldap: LDAP support (openSIS can integrate LDAP)
# - zip:   zip handling
# - xml:   XML parsing
# - mbstring: multibyte string handling
RUN docker-php-ext-install mysqli pdo_mysql ldap zip xml mbstring

# Clone openSIS code into /var/www/openSIS
WORKDIR /var/www
RUN git clone https://github.com/OS4ED/openSIS-Classic.git -b V9.2 openSIS \
    && chown -R www-data:www-data /var/www/openSIS

# Point Apache's DocumentRoot at /var/www/openSIS instead of /var/www/html
RUN sed -i 's|/var/www/html|/var/www/openSIS|g' /etc/apache2/sites-available/000-default.conf

# Optional but recommended: enable Apache mod_rewrite (often needed for PHP apps)
RUN a2enmod rewrite

# Make sure perms are good for Apache/PHP runtime
WORKDIR /var/www/openSIS
RUN chown -R www-data:www-data /var/www/openSIS \
 && find /var/www/openSIS -type d -exec chmod 755 {} \; \
 && find /var/www/openSIS -type f -exec chmod 644 {} \;

EXPOSE 80

# php:8.2-apache already has:
# CMD ["apache2-foreground"]
# so the container stays in the foreground and doesn't immediately exit










FROM php:8.2-apache

# Install system packages needed to compile PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    libldap2-dev \
    libzip-dev \
    libxml2-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Enable required PHP extensions
RUN docker-php-ext-install mysqli pdo_mysql ldap zip xml mbstring

# Get openSIS code
WORKDIR /var/www
RUN git clone https://github.com/OS4ED/openSIS-Classic.git -b V9.2 openSIS

# Point Apache DocumentRoot at /var/www/openSIS instead of /var/www/html
RUN sed -i 's|/var/www/html|/var/www/openSIS|g' /etc/apache2/sites-available/000-default.conf && \
    sed -i 's|DocumentRoot /var/www/openSIS|DocumentRoot /var/www/openSIS\n\t<Directory /var/www/openSIS>\n\t\tAllowOverride All\n\t\tRequire all granted\n\t</Directory>|' /etc/apache2/sites-available/000-default.conf

# Enable rewrite module
RUN a2enmod rewrite

# Fix perms so Apache (www-data) can read/write where needed
WORKDIR /var/www/openSIS
RUN chown -R www-data:www-data /var/www/openSIS && \
    find /var/www/openSIS -type d -exec chmod 755 {} \; && \
    find /var/www/openSIS -type f -exec chmod 644 {} \;

EXPOSE 80

# php:8.2-apache image already ends with:
# CMD ["apache2-foreground"]





build: { context: ., dockerfile: Dockerfile }
container_name: opensis-ui






#######
this Dockerfile Works but with few security issues
#######

############################################
# Global base (ABI safety)
############################################
ARG PHP_IMAGE=php:8.2-apache-bookworm
FROM ${PHP_IMAGE} AS base


############################################
# Stage 1 — Builder
############################################
FROM base AS builder

ARG APP_ENV=dev
ENV APP_ENV=${APP_ENV}

# Build dependencies (compile-time only)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap2-dev \
    libzip-dev \
    libxml2-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Compile PHP extensions
RUN docker-php-ext-install \
    mysqli \
    pdo_mysql \
    ldap \
    zip \
    xml \
    mbstring \
    opcache

# PHP configuration (environment-specific)
RUN mkdir -p /build/php

COPY docker/php/dev.ini     /build/php/dev.ini
COPY docker/php/staging.ini /build/php/staging.ini
COPY docker/php/prod.ini    /build/php/prod.ini

RUN case "$APP_ENV" in \
      dev)     cp /build/php/dev.ini     /usr/local/etc/php/conf.d/99-app.ini ;; \
      staging) cp /build/php/staging.ini /usr/local/etc/php/conf.d/99-app.ini ;; \
      *)       cp /build/php/prod.ini    /usr/local/etc/php/conf.d/99-app.ini ;; \
    esac

# Application
WORKDIR /var/www/openSIS
COPY app/ .

RUN chown -R www-data:www-data /var/www/openSIS


############################################
# Stage 2 — Runtime
############################################
FROM base

ARG APP_ENV=dev
ENV APP_ENV=${APP_ENV}

# Runtime-only system libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap-2.5-0 \
    libzip4 \
    libpng16-16 \
    libxml2 \
    libonig5 \
    libcurl4 \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions and config
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=builder /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

# Application
COPY --from=builder /var/www/openSIS /var/www/openSIS

# Disable installer outside dev
RUN if [ "$APP_ENV" != "dev" ]; then \
        rm -rf /var/www/openSIS/install ; \
    fi

# Apache configuration
RUN sed -i 's|/var/www/html|/var/www/openSIS|g' /etc/apache2/sites-available/000-default.conf \
 && a2enmod rewrite \
 && a2dismod mpm_event \
 && a2enmod mpm_prefork \
 && printf '<Directory /var/www/openSIS>\n\
    AllowOverride All\n\
    Require all granted\n\
    DirectoryIndex index.php\n\
</Directory>\n' >> /etc/apache2/apache2.conf

# Permissions
RUN chown -R www-data:www-data /var/www/openSIS \
 && find /var/www/openSIS -type d -exec chmod 755 {} \; \
 && find /var/www/openSIS -type f -exec chmod 644 {} \;

# Healthcheck (minimal, deterministic)
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD php -r "exit(0);" || exit 1

# Runtime user
USER www-data

EXPOSE 80
################




#work state of my opensis project


services:

  vault:
    image: hashicorp/vault:1.15
    container_name: vault
    restart: unless-stopped
    user: "1000:1000"

    entrypoint: ["vault"]
    command: ["server", "-config=/vault/config/vault.hcl"]

    cap_add:
      - IPC_LOCK

    ports:
      - "127.0.0.1:8200:8200"

    volumes:
      - ./vault/config:/vault/config:ro
      - vault_data:/vault/data

    healthcheck:
      test: ["CMD-SHELL", "VAULT_ADDR=http://127.0.0.1:8200 vault status >/dev/null 2>&1"]
      interval: 20s
      timeout: 5s
      retries: 5
      start_period: 30s

    networks:
      - backend-network
      - frontend-network


  vault-agent-db:
    image: hashicorp/vault:1.15
    container_name: vault-agent-db
    restart: unless-stopped
    user: "1000:1000"

    entrypoint: ["vault"]
    command: ["agent", "-config=/vault/agent/agent-db.hcl"]

    cap_add:
      - IPC_LOCK

    depends_on:
      vault:
        condition: service_healthy

    environment:
      APP_ENV: ${APP_ENV}

    volumes:
      - ./vault-agent/db-config:/vault/agent:ro
      - ./vault-agent/db-templates:/vault/templates:ro
      - ./vault-agent/db-approle:/vault/approle
      - ./vault-agent/db-secrets:/vault/secrets

    networks:
      - backend-network


  vault-agent-app:
    image: hashicorp/vault:1.15
    container_name: vault-agent-app
    restart: unless-stopped
    user: "1000:1000"

    entrypoint: ["vault"]
    command: ["agent", "-config=/vault/agent/agent-app.hcl"]

    cap_add:
      - IPC_LOCK

    depends_on:
      vault:
        condition: service_healthy

    environment:
      APP_ENV: ${APP_ENV}

    volumes:
      - ./vault-agent/app-config:/vault/agent:ro
      - ./vault-agent/app-templates:/vault/templates:ro
      - ./vault-agent/app-approle:/vault/approle
      - ./vault-agent/app-secrets:/vault/secrets

    networks:
      - backend-network


  opensis-db:
    image: mariadb:10.11.7
    container_name: opensis-db
    restart: unless-stopped

    depends_on:
      vault-agent-db:
        condition: service_started

    entrypoint: ["/usr/local/bin/mariadb-entrypoint.sh"]

    volumes:
      - db_data:/var/lib/mysql
      - ./MYSQL/mysql-config/strict_mode.cnf:/etc/mysql/conf.d/strict_mode.cnf:ro
      - ./scripts/mariadb-entrypoint.sh:/usr/local/bin/mariadb-entrypoint.sh:ro
      - ./vault-agent/db-secrets:/run/secrets:ro

    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 --silent"]
      interval: 10s
      timeout: 5s
      retries: 5

    networks:
      - backend-network


  opensis-ui:
    build:
      context: .
      dockerfile: Dockerfile
    image: opensis-ui:dev
    container_name: opensis-ui
    restart: unless-stopped

    depends_on:
      opensis-db:
        condition: service_healthy
      vault-agent-app:
        condition: service_started

    entrypoint: ["/usr/local/bin/docker-entrypoint-vault.sh"]

    volumes:
      - ./vault-agent/app-secrets:/run/secrets:ro

    expose:
      - "80"

    ports:
      - "8080:80"

    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=frontend-network"
      - "traefik.http.routers.opensis.rule=Host(`opensis.raysosglobal.com`)"
      - "traefik.http.routers.opensis.entrypoints=web"
      - "traefik.http.services.opensis.loadbalancer.server.port=80"

    networks:
      - frontend-network
      - backend-network


  traefik:
    image: traefik:v3.6.1
    container_name: traefik
    restart: unless-stopped

    command:
      - "--providers.docker=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=frontend-network"
      - "--entrypoints.web.address=:80"

    ports:
      - "80:80"

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

    networks:
      - frontend-network


  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped

    command: tunnel --no-autoupdate run

    environment:
      - TUNNEL_TOKEN=eyJhIjoiZjA2ZTUwMGMxMDQ0MGZiMmYyZjRmNzY3YTk3NzFmNTUiLCJ0IjoiMTY4Yjc3MzAtYmEzNi00MmJkLWE2YTctZjE4MjFkYWZjYjA1IiwicyI6Ill6TXpOelUzTmpjdFpEY3pNQzAwTVRkbExXRXlZVEV0TmpZM09XRmhPV1UzTkRFMSJ9

    depends_on:
      - traefik

    networks:
      - frontend-network


networks:
  frontend-network:
    driver: bridge

  backend-network:
    driver: bridge
    internal: true


volumes:
  db_data:
  vault_data:





  if [ -f /vault/data/root_token ]; then
  echo "Vault already bootstrapped."
  exit 0
fi


#stable_3 working Dockerfile
# Global base (ABI safety)
ARG PHP_IMAGE=php:8.2-apache-bookworm
FROM ${PHP_IMAGE} AS base


# ==============================
# Stage 1 — Builder
# ==============================
FROM base AS builder

# Build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap2-dev \
    libzip-dev \
    libxml2-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Compile PHP extensions (openSIS compatible set)
RUN docker-php-ext-install \
    mysqli \
    pdo_mysql \
    ldap \
    zip \
    xml \
    mbstring \
    opcache

# PHP base configuration (single immutable config)
COPY docker/php/base.ini /usr/local/etc/php/conf.d/00-base.ini

# Application
WORKDIR /var/www/openSIS
COPY app/ .

RUN chown -R www-data:www-data /var/www/openSIS


# ==============================
# Stage 2 — Runtime
# ==============================
FROM base

# Runtime libraries only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap-2.5-0 \
    libzip4 \
    libpng16-16 \
    libxml2 \
    libonig5 \
    libcurl4 \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions and config
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=builder /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

# Application
COPY --from=builder /var/www/openSIS /var/www/openSIS

# Apache configuration (safe + compatible)
RUN sed -i 's|/var/www/html|/var/www/openSIS|g' /etc/apache2/sites-available/000-default.conf \
 && a2enmod rewrite headers \
 && a2dismod mpm_event \
 && a2enmod mpm_prefork \
 && printf '<Directory /var/www/openSIS>\n\
    AllowOverride All\n\
    Require all granted\n\
    DirectoryIndex index.php\n\
</Directory>\n' >> /etc/apache2/apache2.conf

# Apache hardening
RUN printf 'ServerTokens Prod\n\
ServerSignature Off\n' \
>> /etc/apache2/conf-available/security-hardening.conf \
 && a2enconf security-hardening

# Permissions
RUN chown -R www-data:www-data /var/www/openSIS \
 && find /var/www/openSIS -type d -exec chmod 755 {} \; \
 && find /var/www/openSIS -type f -exec chmod 644 {} \;

# Vault Entrypoint Wrapper
COPY scripts/docker-entrypoint-vault.sh /usr/local/bin/docker-entrypoint-vault.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-vault.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-vault.sh"]
CMD ["apache2-foreground"]

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost/ || exit 1

EXPOSE 80






["CMD-SHELL", "nc -z 127.0.0.1 8200"]