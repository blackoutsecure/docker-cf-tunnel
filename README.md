# docker-cf-tunnel

[![Docker Pulls](https://img.shields.io/docker/pulls/blackoutsecure/cf-tunnel.svg?logo=docker)](https://hub.docker.com/r/blackoutsecure/cf-tunnel)
[![Docker Image Size](https://img.shields.io/docker/image-size/blackoutsecure/cf-tunnel/latest?logo=docker)](https://hub.docker.com/r/blackoutsecure/cf-tunnel)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-cloudflare%2Fcloudflared-orange?logo=cloudflare)](https://github.com/cloudflare/cloudflared)
[![Made by BlackoutSecure](https://img.shields.io/badge/made%20by-BlackoutSecure-1f1f1f?style=flat-square)](https://github.com/blackoutsecure)

> **TL;DR** — A LinuxServer.io-style container that runs the upstream
> [`cloudflared`](https://github.com/cloudflare/cloudflared) connector under
> s6 process supervision. Supports three tunnel modes:
>
> - **`quick`**  — zero-auth, ephemeral `*.trycloudflare.com` URL
> - **`token`** — named tunnel managed via the Cloudflare Zero Trust dashboard
> - **`config`** — locally-managed named tunnel via `config.yml`
>
> _The packaging source is public at
> [`blackoutsecure/docker-cf-tunnel`](https://github.com/blackoutsecure/docker-cf-tunnel).
> Published images remain available on
> [Docker Hub](https://hub.docker.com/r/blackoutsecure/cf-tunnel)._

## Overview

This image packages [`cloudflared`](https://github.com/cloudflare/cloudflared) — the
Cloudflare Tunnel connector daemon — into a hardened multi-arch container suitable
for production deployments on Docker, Docker Compose, Kubernetes, and Balena IoT
fleets.

It is built from the
[`linuxserver/baseimage-ubuntu:noble`](https://github.com/linuxserver/docker-baseimage-ubuntu)
base, runs `cloudflared` under [s6-overlay](https://github.com/just-containers/s6-overlay)
process supervision as the unprivileged `abc` user (uid 911), and ships with a
`/ready`-driven `HEALTHCHECK`, periodic health-heartbeat banners, and a prominent
log banner that surfaces the assigned `*.trycloudflare.com` URL when running in
quick mode.

This is an **unofficial community container**. It is not affiliated with
Cloudflare, Inc. or LinuxServer.io. The bundled `cloudflared` binary is
distributed under the [Apache License 2.0](https://github.com/cloudflare/cloudflared/blob/master/LICENSE);
the container packaging in this repository is MIT-licensed.

## Table of Contents

- [Quick Start](#quick-start)
  - [Mode 1: Quick Tunnel (zero auth)](#mode-1-quick-tunnel-zero-auth)
  - [Mode 2: Token-managed Named Tunnel](#mode-2-token-managed-named-tunnel)
  - [Mode 3: Locally-managed Config Tunnel](#mode-3-locally-managed-config-tunnel)
- [Image Availability](#image-availability)
- [About cloudflared](#about-cloudflared)
- [Supported Architectures](#supported-architectures)
- [Usage](#usage)
- [Parameters](#parameters)
- [Configuration](#configuration)
- [Privileges Required by Feature](#privileges-required-by-feature)
- [User / Group Identifiers](#user--group-identifiers)
- [Application Setup](#application-setup)
- [Quick Tunnel URL Discovery](#quick-tunnel-url-discovery)
- [Health Monitoring](#health-monitoring)
- [Troubleshooting](#troubleshooting)
- [Release & Versioning](#release--versioning)
- [Support & Getting Help](#support--getting-help)
- [References](#references)
- [License](#license)

## Quick Start

### Mode 1: Quick Tunnel (zero auth)

Expose any HTTP service on a randomly-assigned `*.trycloudflare.com` URL with
no Cloudflare account required. Useful for demos, webhooks during development,
and one-off remote access.

```bash
docker run -d \
  --name cf-tunnel \
  -e TZ=Etc/UTC \
  -e TUNNEL_MODE=quick \
  -e TUNNEL_URL=http://host.docker.internal:8080 \
  --security-opt no-new-privileges=true \
  blackoutsecure/cf-tunnel:latest
```

The assigned URL appears in the container logs as a clearly-marked banner and
is also persisted to `/config/quick-url.txt` for scripted access:

```text
========================================================================
  CLOUDFLARE QUICK TUNNEL URL
  ------------------------------------------------------------------
  https://random-words-1234.trycloudflare.com
  ------------------------------------------------------------------
  Persisted to: /config/quick-url.txt
  This URL is EPHEMERAL and changes every container restart.
========================================================================
```

> **Heads-up**: quick tunnels are ephemeral. The hostname changes every time
> the container restarts and Cloudflare may rate-limit heavy production usage.
> For a stable URL, use **`token`** or **`config`** mode below.

### Mode 2: Token-managed Named Tunnel

The recommended production mode. Create a tunnel from the Cloudflare Zero Trust
dashboard, copy the long token shown after `cloudflared service install`, and
hand it to the container.

1. Sign in at <https://one.dash.cloudflare.com/>
2. Navigate to **Networks → Tunnels → Create a tunnel**
3. Choose **Cloudflared** as the connector
4. Name the tunnel and click **Save tunnel**
5. Copy the token from the displayed install command — the long
   `eyJh...` string after `--token`
6. Configure public hostnames and ingress rules in the dashboard
7. Run the container:

```bash
docker run -d \
  --name cf-tunnel \
  -e TZ=Etc/UTC \
  -e TUNNEL_MODE=token \
  -e TUNNEL_TOKEN=eyJhIjoiNzQyMzAyMjE... \
  --security-opt no-new-privileges=true \
  --restart unless-stopped \
  blackoutsecure/cf-tunnel:latest
```

All routing, access policies, WARP routing, and ingress configuration live in
the dashboard — the container is stateless across restarts.

### Mode 3: Locally-managed Config Tunnel

The GitOps mode. Tunnel definition lives in a `config.yml` checked in (or
Ansible-managed) alongside the credentials JSON file generated by
`cloudflared tunnel create`. See
[Configuration → Mode 3](#mode-3-locally-managed-config-tunnel-deep-dive)
below for the full setup walkthrough.

```bash
# Layout:
#   ./cloudflared/
#     ├── cert.pem                       # from `cloudflared tunnel login`
#     ├── 6ff42ae2-765d-4adf-8112-31c55c7551ee.json    # from `tunnel create`
#     └── config.yml

docker run -d \
  --name cf-tunnel \
  -e TZ=Etc/UTC \
  -e TUNNEL_MODE=config \
  -e TUNNEL_NAME=my-prod-tunnel \
  -v "$PWD/cloudflared:/config:ro" \
  --security-opt no-new-privileges=true \
  --restart unless-stopped \
  blackoutsecure/cf-tunnel:latest
```

## Image Availability

| Registry  | Repository                              | URL                                                    |
| --------- | --------------------------------------- | ------------------------------------------------------ |
| Docker Hub | `blackoutsecure/cf-tunnel`             | <https://hub.docker.com/r/blackoutsecure/cf-tunnel>    |
| Balena    | block: `blackoutsecure/cf-tunnel`      | use via `balena push <fleet>` or `balena.yml` block reference |

> Source code and packaging issues are public at
> [`blackoutsecure/docker-cf-tunnel`](https://github.com/blackoutsecure/docker-cf-tunnel).
> The Docker Hub image name remains `blackoutsecure/cf-tunnel`.

### Available Tags

| Tag                | Description                                                        |
| ------------------ | ------------------------------------------------------------------ |
| `latest`           | Latest published release; tracks the most recent `cloudflared` upstream |
| `2026.10.3`        | Specific upstream `cloudflared` version (recommended for production) |
| `2026.10`          | Latest patch within the `2026.10.x` minor line                     |
| `2026`             | Latest release within the `2026.x.y` major-year line               |
| `<version>-<ref>`  | Build pinned to a specific git ref of the cf-tunnel packaging      |
| `sha-<short_sha>`  | Build pinned to a specific git commit of the cf-tunnel packaging   |

Multi-arch manifests are published — the same tag works on both `linux/amd64`
and `linux/arm64`.

## About cloudflared

Cloudflare Tunnel (formerly Argo Tunnel) creates a secure, outbound-only
connection from your origin to Cloudflare's network. No inbound ports need to
be opened, no public IP is required, and no DNS records have to point at your
private network. Public hostnames terminated on the Cloudflare edge route
through the tunnel to whatever services you've published.

`cloudflared` is the connector daemon. Cloudflare publishes a single statically-
linked Go binary; this image wraps that binary in s6-overlay, adds the three
operating modes detailed above, and publishes the result as a multi-arch
container image.

Upstream documentation: <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>

## Supported Architectures

| Architecture | Tag suffix         | Build runner                |
| ------------ | ------------------ | --------------------------- |
| `amd64`      | `amd64-latest`     | `ubuntu-latest`             |
| `arm64`      | `arm64v8-latest`   | `ubuntu-latest-arm64` (native) |

ARM 64-bit images are built natively on GitHub-hosted ARM runners (no QEMU
emulation).

## Usage

### docker-compose (recommended, [click here for more info](https://docs.linuxserver.io/general/docker-compose))

```yaml
version: '2.4'

services:
  cf-tunnel:
    image: docker.io/blackoutsecure/cf-tunnel:latest
    container_name: cf-tunnel
    environment:
      TZ: Etc/UTC
      TUNNEL_MODE: token
      TUNNEL_TOKEN: ${CF_TUNNEL_TOKEN}      # supply via .env or Compose secrets
    security_opt:
      - no-new-privileges=true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
      - DAC_OVERRIDE
      - FOWNER
    tmpfs:
      - /run:exec,size=16m
      - /tmp:exec,size=16m
      - /var/log:size=16m
    restart: unless-stopped
```

### docker-cli ([click here for more info](https://docs.docker.com/engine/reference/commandline/cli/))

```bash
docker run -d \
  --name cf-tunnel \
  --restart unless-stopped \
  -e TZ=Etc/UTC \
  -e TUNNEL_MODE=token \
  -e TUNNEL_TOKEN=eyJhIjoiNzQyMzAyMjE... \
  --security-opt no-new-privileges=true \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE --cap-add FOWNER \
  --tmpfs /run:exec,size=16m \
  --tmpfs /tmp:exec,size=16m \
  --tmpfs /var/log:size=16m \
  blackoutsecure/cf-tunnel:latest
```

### Balena Deployment

This image is published as a Balena block. Reference it from your
`docker-compose.yml`:

```yaml
services:
  cf-tunnel:
    image: bh.cr/blackoutsecure/cf-tunnel
    environment:
      TUNNEL_MODE: token
      TUNNEL_TOKEN: ${CF_TUNNEL_TOKEN}
    labels:
      io.balena.features.supervisor-api: '1'
    restart: unless-stopped
```

Or push the source repository directly with `balena push <your-fleet>` after
cloning. See [`balena.yml`](balena.yml) for the supported device types.

### docker-compose with Docker Secrets

Recommended for production token storage:

```yaml
version: '3.8'

services:
  cf-tunnel:
    image: docker.io/blackoutsecure/cf-tunnel:latest
    environment:
      TZ: Etc/UTC
      TUNNEL_MODE: token
      TUNNEL_TOKEN_FILE: /run/secrets/cf_tunnel_token
    secrets:
      - cf_tunnel_token
    restart: unless-stopped

secrets:
  cf_tunnel_token:
    file: ./secrets/tunnel-token.txt
```

## Parameters

### Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `TZ` | `Etc/UTC` | Timezone (see TZ database) |
| `TUNNEL_MODE` | _auto_ | Tunnel mode: `quick` \| `token` \| `config`. Auto-detected from other vars when unset (token > config > quick) |
| `LOG_LEVEL` | `info` | Container init script log verbosity (separate from `TUNNEL_LOGLEVEL`) |
| `PUID` | `1000` | User ID for `/config` ownership (LSIO base image) |
| `PGID` | `1000` | Group ID for `/config` ownership (LSIO base image) |

#### Quick mode

| Variable | Default | Description |
| --- | --- | --- |
| `TUNNEL_URL` | _required_ | URL of the upstream service to expose, e.g. `http://app:8080` or `tcp://db:5432` |
| `QUICK_URL_PERSIST_FILE` | `/config/quick-url.txt` | Where the assigned `*.trycloudflare.com` URL is persisted |

#### Token mode

| Variable | Default | Description |
| --- | --- | --- |
| `TUNNEL_TOKEN` | _required_ | Tunnel token from Cloudflare Zero Trust dashboard |
| `TUNNEL_TOKEN_FILE` | _empty_ | Path to file containing the token (Docker secrets / K8s projected volumes) |

#### Config mode

| Variable | Default | Description |
| --- | --- | --- |
| `TUNNEL_CONFIG_FILE` | _auto_ | Path to cloudflared `config.yml` (auto-detected from `/config/config.yml` or `/config/config.yaml`) |
| `TUNNEL_NAME` | _empty_ | Tunnel name (overrides `tunnel:` key in config.yml) |
| `TUNNEL_ID` | _empty_ | Tunnel UUID (overrides `tunnel:` key in config.yml) |
| `TUNNEL_CREDENTIALS_FILE` | _from config.yml_ | Path to credentials JSON file (overrides `credentials-file:` in config.yml) |
| `TUNNEL_CREDENTIALS_CONTENTS` | _empty_ | Inline credentials JSON content; written to `TUNNEL_CREDENTIALS_FILE` or `/config/<id>.json` |
| `TUNNEL_CREDENTIALS_CONTENTS_FILE` | _empty_ | Path to a file containing the credentials JSON (Docker secrets) |
| `TUNNEL_ORIGIN_CERT` | _empty_ | Path to `cert.pem` (only required for `cloudflared tunnel create/route/delete`, not `run`) |
| `TUNNEL_ORIGIN_CERT_FILE` | _empty_ | Path to a file containing `cert.pem` (Docker secrets) |

#### cloudflared runtime tunables

| Variable | Default | Description |
| --- | --- | --- |
| `TUNNEL_LOGLEVEL` | `info` | cloudflared log level: `debug` \| `info` \| `warn` \| `error` \| `fatal` |
| `TUNNEL_TRANSPORT_LOGLEVEL` | _empty_ | Transport-layer log level (passed as `--transport-loglevel`) |
| `TUNNEL_METRICS` | `0.0.0.0:2000` | Bind address for metrics; exposes `/ready` (healthcheck) and `/metrics` (Prometheus) |
| `TUNNEL_PROTOCOL` | _cloudflared default (auto)_ | Edge transport: `auto` \| `http2` \| `quic` |
| `TUNNEL_EDGE_IP_VERSION` | _cloudflared default (auto)_ | Edge IP family: `auto` \| `4` \| `6` |
| `TUNNEL_REGION` | _empty_ | Restrict tunnel to a Cloudflare region (e.g. `us`) |
| `TUNNEL_RETRIES` | _cloudflared default_ | Max retries before declaring a tunnel down |
| `TUNNEL_GRACE_PERIOD` | `30s` | Time cloudflared waits for in-flight requests on shutdown |
| `TUNNEL_HA_CONNECTIONS` | _cloudflared default (4)_ | Number of HA edge connections |
| `TUNNEL_HEARTBEAT_INTERVAL` | _cloudflared default_ | Interval between heartbeats sent to the edge |
| `TUNNEL_HEARTBEAT_COUNT` | _cloudflared default_ | Heartbeats missed before edge connection is recycled |
| `TUNNEL_POST_QUANTUM` | _empty_ | Set to `true` to enable post-quantum (Kyber768) key exchange |
| `EXTRA_CLOUDFLARED_ARGS` | _empty_ | Extra CLI args appended to the cloudflared invocation (power-user escape hatch) |
| `NO_AUTOUPDATE` | `true` | Disable cloudflared's self-update (always recommended; we manage versions via image tags) |

#### Customization hooks

| Variable | Default | Description |
| --- | --- | --- |
| `EXTRA_PACKAGES` | _empty_ | Space-separated apt packages installed at startup as root (escape hatch; for repeated use build a custom image; incompatible with `read_only: true`) |
| `EXTRA_APT_REPOS` | _empty_ | Semicolon-separated apt sources lines added before installing `EXTRA_PACKAGES` |
| `EXTRA_INIT_SCRIPT` | _empty_ | Path inside container to a shell script (typically bind-mounted) run as root before cloudflared starts |

#### Health & heartbeat

| Variable | Default | Description |
| --- | --- | --- |
| `HEARTBEAT_INTERVAL` | `120` | Seconds between health-heartbeat banners (clamped to >= 30) |
| `HEALTH_STALE_AFTER` | `120` | Seconds before the Docker `HEALTHCHECK` reports unhealthy if the online sentinel goes stale |
| `HEALTH_REQUIRE_CONNECTIONS` | `1` | Minimum ready edge connections required for the `HEALTHCHECK` to pass |

#### s6 / shutdown

| Variable | Default | Description |
| --- | --- | --- |
| `S6_SERVICES_GRACETIME` | `30000` | s6 service shutdown gracetime (ms) — must allow time for cloudflared to drain (`TUNNEL_GRACE_PERIOD`) |
| `S6_KILL_GRACETIME` | `30000` | s6 hard-kill gracetime (ms); keep aligned with `stop_grace_period` in compose |

### Storage Mounts

| Mount path | Purpose | Required for |
| --- | --- | --- |
| `/config` | Persistent state: `config.yml`, credentials JSON, `cert.pem`, `quick-url.txt` | config mode (recommended); quick mode only for URL persistence |

`token` mode keeps no on-disk state and does not require any volume.

## Configuration

### Mode 1: Quick Tunnel deep-dive

In quick mode, cloudflared connects to Cloudflare's `argotunnel` edge and is
assigned a random `*.trycloudflare.com` hostname. The tunnel proxies traffic
to whatever URL you set in `TUNNEL_URL`.

```yaml
services:
  cf-tunnel:
    image: blackoutsecure/cf-tunnel:latest
    environment:
      TUNNEL_MODE: quick
      TUNNEL_URL: http://app:8080
    volumes:
      - cf-tunnel-config:/config       # only needed for quick-url.txt persistence
    restart: unless-stopped

  app:
    image: nginx:alpine
    expose: ["8080"]

volumes:
  cf-tunnel-config:
```

cloudflared accepts a wide range of URL schemes for `--url`:

- `http://host:port` / `https://host:port` — most common
- `tcp://host:port` — bare TCP forwarding (e.g. databases)
- `ssh://host:port` — SSH proxying
- `rdp://host:port` — RDP proxying
- `unix:/path/to/socket` — UNIX socket
- `unix+tls:/path/to/socket` — UNIX socket over TLS

The assigned URL is logged exactly once when first available, and persisted
to `/config/quick-url.txt`:

```bash
docker exec cf-tunnel cat /config/quick-url.txt
# https://random-words-1234.trycloudflare.com
```

### Mode 2: Token-managed Named Tunnel deep-dive

Token tunnels are managed entirely from the Cloudflare Zero Trust dashboard.
The container holds only the token; everything else (hostnames, ingress,
access policies, WARP routing) is dashboard-driven.

**Step-by-step setup**:

1. Sign in to the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks → Tunnels → Create a tunnel**
3. Choose **Cloudflared** as the connector type and click **Next**
4. Give the tunnel a name (e.g. `home-prod`) and click **Save tunnel**
5. On the **Install and run a connector** screen, copy the long token from the
   suggested install command. It's the `eyJ...` argument after `--token`.
6. Click **Next** to configure **Public Hostnames**:
   - Subdomain: `home`
   - Domain: pick from your zone list
   - Service Type: `HTTP` / `HTTPS` / `TCP` / `SSH` / etc.
   - URL: `app:8080` (cloudflared resolves this from inside the container's network)
7. (Optional) Configure **Private Networks** for WARP routing.
8. Click **Save tunnel**.

Then deploy:

```yaml
services:
  cf-tunnel:
    image: blackoutsecure/cf-tunnel:latest
    environment:
      TUNNEL_MODE: token
      TUNNEL_TOKEN: eyJhIjoiNzQyMzAyMjE...
    restart: unless-stopped

  app:
    image: nginx:alpine
    expose: ["8080"]
```

To rotate the token: regenerate it in the dashboard, update the env var, and
`docker compose up -d`. The previous token continues to authenticate any other
connectors of the same tunnel until you remove them from the dashboard.

### Mode 3: Locally-managed Config Tunnel deep-dive

The classic config-file workflow. Useful for GitOps deployments where
`config.yml` and the credentials JSON are tracked in a private repository or
managed by Ansible / Puppet / etc.

**One-time bootstrap (run cloudflared on a workstation)**:

```bash
# 1. Authenticate to your Cloudflare account.
#    Opens a browser for you to pick a zone and writes ~/.cloudflared/cert.pem.
cloudflared tunnel login

# 2. Create the tunnel. Writes ~/.cloudflared/<UUID>.json (the credentials).
cloudflared tunnel create my-prod-tunnel
# Tunnel credentials written to /home/you/.cloudflared/6ff42ae2-765d-4adf-8112-31c55c7551ee.json

# 3. Route DNS hostnames to the tunnel.
cloudflared tunnel route dns my-prod-tunnel home.example.com

# 4. Write a config.yml (next to the credentials JSON).
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: my-prod-tunnel
credentials-file: /config/6ff42ae2-765d-4adf-8112-31c55c7551ee.json

ingress:
  - hostname: home.example.com
    service: http://app:8080
  - hostname: ssh.example.com
    service: ssh://bastion:22
  - service: http_status:404
EOF
```

**Deploy the container**:

```bash
# Mount the ~/.cloudflared directory at /config (read-only is fine).
docker run -d \
  --name cf-tunnel \
  -e TZ=Etc/UTC \
  -e TUNNEL_MODE=config \
  -e TUNNEL_NAME=my-prod-tunnel \
  -v ~/.cloudflared:/config:ro \
  --restart unless-stopped \
  blackoutsecure/cf-tunnel:latest
```

Or with compose + secrets:

```yaml
services:
  cf-tunnel:
    image: blackoutsecure/cf-tunnel:latest
    environment:
      TUNNEL_MODE: config
      TUNNEL_NAME: my-prod-tunnel
      TUNNEL_CREDENTIALS_CONTENTS_FILE: /run/secrets/tunnel_credentials
    configs:
      - source: tunnel_config
        target: /config/config.yml
    secrets:
      - tunnel_credentials
    restart: unless-stopped

configs:
  tunnel_config:
    file: ./cloudflared/config.yml

secrets:
  tunnel_credentials:
    file: ./cloudflared/6ff42ae2-765d-4adf-8112-31c55c7551ee.json
```

> **Important**: in the `config.yml` use the absolute path that the
> credentials file will have **inside the container**, not the host path.

### Using Docker Secrets (`_FILE` variables)

For every secret-bearing variable the image accepts a `_FILE` companion that
reads the value from a file. This is the recommended pattern for Docker
Compose secrets and Kubernetes projected volumes:

| Variable | `_FILE` companion | Notes |
| --- | --- | --- |
| `TUNNEL_TOKEN` | `TUNNEL_TOKEN_FILE` | Token mode |
| `TUNNEL_CREDENTIALS_CONTENTS` | `TUNNEL_CREDENTIALS_CONTENTS_FILE` | Inline credentials JSON content |
| `TUNNEL_ORIGIN_CERT` | `TUNNEL_ORIGIN_CERT_FILE` | cert.pem contents |

When both are supplied, the direct variable wins.

## Privileges Required by Feature

### Minimum baseline (default config, no opt-in features)

```yaml
security_opt:
  - no-new-privileges=true
cap_drop: [ALL]
cap_add:
  - CHOWN          # LSIO baseimage owns /config to PUID/PGID
  - SETUID         # s6-setuidgid drops cloudflared to abc
  - SETGID
  - DAC_OVERRIDE   # init writes to /run/cf-tunnel
  - FOWNER         # init chowns sentinel + state files
```

cloudflared itself needs **no Linux capabilities** at runtime — it dials out
to Cloudflare's edge over HTTPS/QUIC and proxies traffic in user space.

### Per-feature privilege matrix

| Feature                    | Add capabilities  | Bind mounts | `read_only:` | `--user` non-root | Notes |
| -------------------------- | ----------------- | ----------- | ------------ | ----------------- | ----- |
| Default (token / quick)    | _baseline_        | _none_      | yes          | yes (911:911)     | Container is fully stateless; minimal attack surface |
| Config mode (read-only)    | _baseline_        | `/config:ro`| yes          | yes               | `config.yml` + credentials baked in via bind mount |
| Quick-URL persistence      | _baseline_        | `/config:rw`| no           | yes               | Needs writable `/config` to persist `quick-url.txt` |
| `EXTRA_PACKAGES`           | _baseline_        | _none_      | **no**       | **no** (root)     | apt requires writable `/var/lib/apt`; refused under read-only |
| Bind low ports (rare)      | + `NET_BIND_SERVICE` | _none_   | yes          | _depends_         | Only relevant if `EXTRA_CLOUDFLARED_ARGS` makes cloudflared bind <1024 directly |

## User / Group Identifiers

The container starts as root, then drops cloudflared to the LinuxServer.io
`abc` user (uid 911, gid 911) via `s6-setuidgid`. Standard LSIO PUID/PGID
remapping is supported:

```yaml
environment:
  PUID: 1000     # owner of /config
  PGID: 1000
```

Files in `/config` are chowned to `PUID:PGID` during the init step. This
matters when you bind-mount a host directory and want to preserve ownership
for tools running outside the container.

## Application Setup

### Operating modes summary

| Mode | TUNNEL_MODE | Required | Stable URL | Stateless restarts | Use case |
| ---- | ----------- | -------- | ---------- | ------------------ | -------- |
| Quick | `quick` | `TUNNEL_URL` | No (changes per restart) | Yes | Demos, dev webhooks, ad-hoc sharing |
| Token | `token` | `TUNNEL_TOKEN` | Yes (dashboard-managed) | Yes | Production with dashboard ingress management |
| Config | `config` | config.yml + credentials JSON | Yes (DNS-routed) | Yes (config persisted) | GitOps, CLI-driven workflows |

### Custom packages and init scripts

For one-off customization without rebuilding the image:

```yaml
environment:
  EXTRA_PACKAGES: "iputils-ping traceroute"
  EXTRA_INIT_SCRIPT: "/config/init.d/preflight.sh"
volumes:
  - ./init.d:/config/init.d:ro
```

`EXTRA_PACKAGES` validates each package name against `^[a-z0-9][a-z0-9+.\-]+$`
to prevent shell injection and refuses to run when the rootfs is read-only.
`EXTRA_INIT_SCRIPT` refuses world-writable scripts.

For repeated use, build a custom image:

```dockerfile
FROM blackoutsecure/cf-tunnel:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
        iputils-ping traceroute && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

### Running as a non-root user (LSIO `--user`)

```yaml
services:
  cf-tunnel:
    image: blackoutsecure/cf-tunnel:latest
    user: "911:911"           # LSIO non-root opt-in
    read_only: true
    tmpfs:
      - /run:exec,size=16m,uid=911,gid=911
      - /tmp:exec,size=16m,uid=911,gid=911
      - /var/log:size=16m,uid=911,gid=911
    environment:
      TUNNEL_MODE: token
      TUNNEL_TOKEN_FILE: /run/secrets/tunnel_token
    secrets:
      - tunnel_token
```

Caveats with `--user`:

- `PUID` / `PGID` are ignored
- `EXTRA_PACKAGES` is ignored (apt requires root)
- `/run` tmpfs **must** be owned by the chosen uid (s6-overlay requirement)

## Quick Tunnel URL Discovery

When `TUNNEL_MODE=quick`, the heartbeat service:

1. Polls cloudflared's `/metrics` endpoint and the local log stream looking for
   `https://*.trycloudflare.com` URLs
2. On first detection, emits a clearly-marked banner to stdout
3. Writes the URL to `${QUICK_URL_PERSIST_FILE}` (default `/config/quick-url.txt`)

For automation (Compose health gates, CI smoke tests, etc.):

```bash
# Wait for the URL to appear (up to 60s), then read it.
for i in $(seq 1 30); do
  url="$(docker exec cf-tunnel cat /config/quick-url.txt 2>/dev/null)"
  if [ -n "${url}" ]; then
    echo "${url}"
    break
  fi
  sleep 2
done
```

## Health Monitoring

### Docker HEALTHCHECK

The image's built-in `HEALTHCHECK` runs every 30s and reports healthy iff
**all** of:

1. The `cloudflared` process is alive
2. cloudflared's `/ready` endpoint returns HTTP 200 with at least
   `${HEALTH_REQUIRE_CONNECTIONS}` (default 1) ready edge connections
3. The `/run/cf-tunnel/online` sentinel — refreshed by the heartbeat service
   every successful `/ready` probe — has an mtime within `${HEALTH_STALE_AFTER}`
   seconds (default 120)

```bash
docker inspect --format '{{.State.Health.Status}}' cf-tunnel
# healthy
```

### Heartbeat banners

Every `${HEARTBEAT_INTERVAL}` seconds (default 120, clamped to >=30) the
heartbeat service emits a one-line summary:

```text
2026-05-13T12:00:42Z *** HEALTH HEARTBEAT *** mode=token ready_connections=4 ha_connections=4 active_streams=0 total_requests=128 uptime=2h13m05s
```

Heartbeat lines are easy to grep for in log aggregators:

```bash
docker logs cf-tunnel 2>&1 | grep "HEALTH HEARTBEAT"
```

### Auto-recovery

cloudflared maintains its own automatic reconnect loop to the Cloudflare edge
(QUIC/HTTP2 with retries and backoff). On hard failures (auth error, unknown
tunnel, invalid token) cloudflared exits non-zero and s6's `finish` script
delays five seconds before restart to avoid CrashLoopBackoff-style busy loops.

### s6 Service Supervision

The image runs four s6 longrun/oneshot services:

| Service | Type | Purpose |
| --- | --- | --- |
| `init-custom` | oneshot | Optional EXTRA_PACKAGES / EXTRA_INIT_SCRIPT hook |
| `init-cf-tunnel-config` | oneshot | Validate `TUNNEL_MODE`, resolve secrets, materialize state |
| `svc-cf-tunnel` | longrun | The `cloudflared` daemon (the actual tunnel) |
| `svc-cf-tunnel-logs` | longrun | Heartbeat + quick-URL extractor |

## Troubleshooting

### Container won't start or exits immediately

```bash
docker logs cf-tunnel
```

Most common causes:

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `No TUNNEL_MODE set and no auto-detect signals found` | None of `TUNNEL_TOKEN`, `TUNNEL_URL`, `TUNNEL_CONFIG_FILE`, or `/config/config.yml` is present | Set `TUNNEL_MODE` explicitly or supply one of the trigger vars |
| `TUNNEL_MODE=token requires TUNNEL_TOKEN` | Token mode without a token | Provide `TUNNEL_TOKEN=...` or `TUNNEL_TOKEN_FILE=/run/secrets/...` |
| `TUNNEL_TOKEN_FILE=... is not readable` | The mounted secrets file is not readable by the container's effective uid | `chmod 0644` on the host, or set `mode: 0644` in the Compose secret config |
| `TUNNEL_CREDENTIALS_FILE='...' is not readable by abc (uid 911)` | Credentials JSON has wrong ownership | `chown 911:911` on the host file, or `chmod 0644` |
| Exits silently with no error after a few seconds | Invalid token (auth fail) | Cloudflared logs the auth error at `info`; raise `TUNNEL_LOGLEVEL=debug` |

### Tunnel shows as "Down" in the Cloudflare dashboard

```bash
# Confirm cloudflared has at least one ready edge connection.
docker exec cf-tunnel curl -s http://127.0.0.1:2000/ready
# {"status":200,"readyConnections":4,...}
```

If `readyConnections=0`, check egress connectivity to Cloudflare. Common
causes: outbound TCP/443 or UDP/7844 blocked by an upstream firewall; strict
egress proxies that don't grok QUIC. Try `TUNNEL_PROTOCOL=http2` to disable
QUIC.

### Quick-URL doesn't appear in logs

```bash
# The URL is logged once and persisted to /config/quick-url.txt.
# If the persist file isn't there, the heartbeat service hasn't seen it yet.
docker exec cf-tunnel cat /config/quick-url.txt 2>/dev/null
docker exec cf-tunnel curl -s http://127.0.0.1:2000/metrics | grep -i trycloudflare
```

If `/metrics` doesn't show the URL, cloudflared may have failed to negotiate
the quick tunnel — check upstream connectivity (see above).

### High CPU usage

cloudflared QUIC connections can be CPU-intensive on first connect. Steady-
state CPU should be near zero (<1% on amd64) outside of active proxied traffic.
If steady-state CPU is high:

- Drop to HTTP/2: `TUNNEL_PROTOCOL=http2`
- Lower the heartbeat frequency: `HEARTBEAT_INTERVAL=300`
- Disable post-quantum: ensure `TUNNEL_POST_QUANTUM` is unset

## Release & Versioning

Image versions track the upstream `cloudflared` calver release (e.g.
`2026.10.3`). The release pipeline:

1. **`upstream-release-monitor.yml`** — runs on cron every 6 hours; polls
   `cloudflare/cloudflared`'s `/releases/latest` and writes
   [`.github/upstream/cloudflared.json`](.github/upstream/cloudflared.json)
   when the tracked metadata diverges. It explicitly dispatches the publish
   workflow with `publish=true` and the release workflow after pushing the
   metadata commit; pushes made with `GITHUB_TOKEN` do not trigger workflows.
2. **`publish.yml`** — builds multi-arch images on `push:main` and
   PR `pull_request`. Pull requests and manual runs default to build-only;
   pushes to `main` and manual runs with `publish=true` publish to Docker Hub.
   Balena publishing runs only when its namespace and API token are configured.
3. **`release.yml`** — triggered by the upstream monitor or by a manual
   GitHub Release. Tags and pushes versioned image tags
   (`2026.10.3`, `2026.10`, `2026`, `latest`) and writes release notes.

The Dockerfile's `APP_VERSION` build arg defaults to `2026.10.3`. CI reads
`.github/upstream/cloudflared.json` and overrides that default on every build.
To reproduce a later CI build locally, pass
`--build-arg APP_VERSION="$(jq -r .version .github/upstream/cloudflared.json)"`.

### Repository automation setup

Configure these repository or organization secrets for the new repository;
credentials are not copied from the previous repository:

- `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`: required to publish images and
  update the Docker Hub description. The token needs write access to
  `blackoutsecure/cf-tunnel`.
- `DOCKERHUB_NAMESPACE`: optional repository variable, with the same-named
  legacy secret also supported. Defaults to `blackoutsecure`.
- `BALENA_API_TOKEN`: optional Balena publishing credential. To enable Balena,
  also set the `BALENA_NAMESPACE` variable (or legacy `BALENA_USERNAME`
  secret). If neither is configured, Balena publishing is explicitly skipped;
  partial configuration fails preflight.

The upstream monitor uses the repository's `GITHUB_TOKEN` with `contents: write`
and `actions: write` to commit metadata and dispatch workflows. Repository rules
must permit the bot's metadata and Balena-version commits to `main`.
No personal access token is required by these workflows.

Builds use GitHub-hosted `ubuntu-latest` and `ubuntu-24.04-arm` runners; no
private-organization runner label is required. Third-party actions are pinned
to immutable commit SHAs.

## Support & Getting Help

- **Issues / bug reports**: <https://github.com/blackoutsecure/docker-cf-tunnel/issues>
- **Cloudflare Tunnel docs**: <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>
- **Cloudflare Community**: <https://community.cloudflare.com/c/cloudflare-zero-trust>
- **cloudflared upstream issues**: <https://github.com/cloudflare/cloudflared/issues>

For container packaging issues, please open a GitHub issue in
[`blackoutsecure/docker-cf-tunnel`](https://github.com/blackoutsecure/docker-cf-tunnel).
For cloudflared
application bugs (auth failures, edge connectivity, QUIC bugs), please report
upstream after confirming the issue reproduces with the same cloudflared
version outside this container.

## References

### Project Resources

- Source repository: <https://github.com/blackoutsecure/docker-cf-tunnel>
- Docker Hub image: <https://hub.docker.com/r/blackoutsecure/cf-tunnel>
- Maintainer: [Blackout Secure](https://blackoutsecure.app)

### Upstream & Related

- `cloudflare/cloudflared`: <https://github.com/cloudflare/cloudflared>
- Cloudflare Tunnel documentation: <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>
- Cloudflare Zero Trust dashboard: <https://one.dash.cloudflare.com/>
- LinuxServer.io baseimage: <https://github.com/linuxserver/docker-baseimage-ubuntu>
- s6-overlay: <https://github.com/just-containers/s6-overlay>
- Balena docs: <https://docs.balena.io/>

## License

This container packaging is released under the [MIT License](LICENSE).

The bundled `cloudflared` binary is the property of Cloudflare, Inc. and is
licensed under the [Apache License 2.0](https://github.com/cloudflare/cloudflared/blob/master/LICENSE).
