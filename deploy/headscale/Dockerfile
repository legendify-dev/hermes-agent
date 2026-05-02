FROM debian:13-slim

ARG HEADSCALE_VERSION=0.23.0
ARG TARGETARCH=amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl && \
    curl -fsSL "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_${TARGETARCH}.deb" \
        -o /tmp/headscale.deb && \
    dpkg -i /tmp/headscale.deb && \
    rm /tmp/headscale.deb && \
    apt-get purge -y curl && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

COPY config.yaml /etc/headscale/config.tmpl.yaml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
