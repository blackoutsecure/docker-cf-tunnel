# syntax=docker/dockerfile:1.8

ARG BASE_IMAGE=ghcr.io/linuxserver/baseimage-ubuntu:noble
ARG APP_VERSION=2026.10.3

FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG APP_VERSION
ARG TARGETARCH

LABEL maintainer="Blackout Secure - https://blackoutsecure.app/" \
    org.opencontainers.image.title="docker-cf-tunnel" \
    org.opencontainers.image.description="Containerized Cloudflare Tunnel (cloudflared) connector with s6 process supervision. Supports Quick Tunnels (trycloudflare.com), token-based named tunnels, and locally-managed config-file tunnels." \
    org.opencontainers.image.url="https://github.com/blackoutsecure/docker-cf-tunnel" \
    org.opencontainers.image.source="https://github.com/blackoutsecure/docker-cf-tunnel" \
    org.opencontainers.image.version="${APP_VERSION}" \
    org.opencontainers.image.licenses="MIT"

# Runtime dependencies for cloudflared and our supervisor scripts:
#   * ca-certificates -- TLS root anchors for cloudflared & the API probes
#   * curl            -- used by the healthcheck and heartbeat probes
#   * jq              -- parses /ready and /metrics JSON for the heartbeat
#   * libcap2-bin     -- setcap so cloudflared can bind low ports if asked
#   * tini-bundled by s6, no extra package needed
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        libcap2-bin \
        tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --link build/ /tmp/build/
RUN chmod +x /tmp/build/*.sh && \
    /tmp/build/install-cloudflared.sh && \
    rm -rf /tmp/build && \
    mkdir -p /tmp && chmod 1777 /tmp

COPY --link root/ /

# Defaults match cloudflared's own defaults where possible. Empty strings
# mean "unset" -- the init script treats them as not provided.
ENV HOME="/config" \
    XDG_CONFIG_HOME="/config" \
    TUNNEL_MODE="" \
    TUNNEL_URL="" \
    TUNNEL_TOKEN="" \
    TUNNEL_TOKEN_FILE="" \
    TUNNEL_NAME="" \
    TUNNEL_ID="" \
    TUNNEL_CONFIG_FILE="" \
    TUNNEL_CREDENTIALS_FILE="" \
    TUNNEL_CREDENTIALS_CONTENTS="" \
    TUNNEL_CREDENTIALS_CONTENTS_FILE="" \
    TUNNEL_ORIGIN_CERT="" \
    TUNNEL_ORIGIN_CERT_FILE="" \
    TUNNEL_HOSTNAME="" \
    TUNNEL_METRICS="0.0.0.0:2000" \
    TUNNEL_LOGLEVEL="info" \
    TUNNEL_TRANSPORT_LOGLEVEL="" \
    TUNNEL_PROTOCOL="" \
    TUNNEL_EDGE_IP_VERSION="" \
    TUNNEL_REGION="" \
    TUNNEL_RETRIES="" \
    TUNNEL_GRACE_PERIOD="30s" \
    TUNNEL_HEARTBEAT_INTERVAL="" \
    TUNNEL_HEARTBEAT_COUNT="" \
    TUNNEL_HA_CONNECTIONS="" \
    TUNNEL_POST_QUANTUM="" \
    NO_AUTOUPDATE="true" \
    EXTRA_CLOUDFLARED_ARGS="" \
    LOG_LEVEL="info" \
    EXTRA_PACKAGES="" \
    EXTRA_APT_REPOS="" \
    EXTRA_INIT_SCRIPT="" \
    HEARTBEAT_INTERVAL="120" \
    HEALTH_STALE_AFTER="120" \
    HEALTH_REQUIRE_CONNECTIONS="1" \
    READY_FAIL_THRESHOLD="3" \
    ON_NOT_READY_ACTION="restart" \
    QUICK_URL_PERSIST_FILE="/config/quick-url.txt" \
    S6_SERVICES_GRACETIME="30000" \
    S6_KILL_GRACETIME="30000"

COPY --link build/finalize.sh /tmp/finalize.sh
RUN chmod +x /tmp/finalize.sh && /tmp/finalize.sh && rm -f /tmp/finalize.sh

VOLUME ["/config"]

# Cloudflared opens the metrics endpoint a couple of seconds into startup.
# A 60s start-period covers the slowest path observed (DNS-cold, large
# config.yml, multiple ingress origins). Retries=3 tolerates brief
# api.cloudflare.com flakes once the tunnel is up.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/cf-tunnel-healthcheck
