# Global base (ABI safety)
ARG PHP_IMAGE=php:8.2-apache-bookworm
FROM ${PHP_IMAGE} AS base


# ==============================
# Stage 1 — Builder
# ==============================
FROM base AS builder

# Build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    $PHPIZE_DEPS \
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
    opcache \
 && pecl install redis \
 && docker-php-ext-enable redis

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

ARG APP_VERSION=dev
ARG VCS_REF=unknown

LABEL org.opencontainers.image.title="openSIS UI" \
      org.opencontainers.image.description="openSIS Apache/PHP runtime image" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

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

# Apache configuration
COPY docker/apache/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY docker/apache/security-hardening.conf /etc/apache2/conf-available/security-hardening.conf

# Apache configuration (safe + compatible)
RUN a2enmod rewrite headers \
 && a2dismod mpm_event \
 && a2enmod mpm_prefork \
 && a2enconf security-hardening

# Permissions
RUN chown -R www-data:www-data /var/www/openSIS \
 && find /var/www/openSIS -type d -exec chmod 755 {} \; \
 && find /var/www/openSIS -type f -exec chmod 644 {} \;

# Vault Entrypoint Wrapper
COPY scripts/docker-entrypoint-vault.sh /usr/local/bin/docker-entrypoint-vault.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-vault.sh

ENV APP_SECRETS_FILE=/run/secrets/app.env \
    APP_SECRETS_WAIT_TIMEOUT=60

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-vault.sh"]
CMD ["apache2-foreground"]

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost/ || exit 1

EXPOSE 80
