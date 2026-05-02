#!/bin/sh
# Render config from template by substituting env vars, then exec headscale.
# Required:  SERVER_URL  (e.g. https://hermes-headscale.up.railway.app)
# Optional:  LISTEN_ADDR (default 0.0.0.0:8080)
#            BASE_DOMAIN (default hermes.internal)
set -e

: "${SERVER_URL:?SERVER_URL must be set}"
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0:8080}"
BASE_DOMAIN="${BASE_DOMAIN:-hermes.internal}"

mkdir -p /var/lib/headscale /var/run/headscale /etc/headscale

sed -e "s|\${SERVER_URL}|${SERVER_URL}|g" \
    -e "s|\${LISTEN_ADDR}|${LISTEN_ADDR}|g" \
    -e "s|\${BASE_DOMAIN}|${BASE_DOMAIN}|g" \
    /etc/headscale/config.tmpl.yaml > /etc/headscale/config.yaml

exec headscale "$@"
