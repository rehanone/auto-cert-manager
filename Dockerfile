FROM alpine:3

ARG CERTBOT_VERSION=5.1.0
ARG PYTHON_VERSION=3.14

# set version label
ARG BUILD_DATE
ARG VERSION

LABEL build_version="auto-cert-manager version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="Rehan Mahmood (@rehanone)"

VOLUME /certs
VOLUME /etc/letsencrypt


# Install system dependencies.
RUN apk add --update --no-cache \
    # To generate config files and install certbot plugins:
    python3>=${PYTHON_VERSION} \
    # To generate and renew TLS certificate:
    certbot>=${CERTBOT_VERSION} \
    # Install Certbot Cloudflare Plugin:
    certbot-dns-cloudflare>=${CERTBOT_VERSION} \
    # Install Certbot Linode Plugin:
    certbot-dns-linode>=${CERTBOT_VERSION} \
    # Install Python dependencies:
    py3-jinja2 \
    # Install openssl:
    openssl \
    # Install bash:
    bash

# Certbot dns plugin secerts file
RUN mkdir -p /credentials && touch /credentials/dns-creds.ini
RUN chmod 0600 /credentials/*.ini

# Add crontab
ADD crontab /etc/crontabs
RUN crontab /etc/crontabs/crontab

COPY ./scripts/ /scripts
RUN chmod -R +x /scripts/

ENTRYPOINT ["/scripts/entrypoint.sh"]
