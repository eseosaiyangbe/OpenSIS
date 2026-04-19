FROM hashicorp/vault:1.15

USER root

# Only install what is required
RUN apk add --no-cache jq

# Copy bootstrap script and policies
COPY scripts/bootstrap.sh /bootstrap.sh
COPY vault-bootstrap/policies /policies

RUN chmod +x /bootstrap.sh

# Drop privileges to match Vault runtime user
USER 1000

ENTRYPOINT ["/bin/sh", "-c", "/bootstrap.sh"]