FROM hashicorp/vault:1.15

USER root

RUN apk add --no-cache jq

COPY scripts/seed.sh /seed.sh

RUN chmod +x /seed.sh

USER 1000

ENTRYPOINT ["/bin/sh", "-c", "/seed.sh"]