#!/bin/bash
set -euo pipefail

# Install the cloudflared static binary to /usr/local/bin/cloudflared.
#
# Cloudflared is a single statically-linked Go binary; we pull the
# release artifact directly from the upstream GitHub release rather than
# installing the .deb (the .deb pulls in a systemd unit and post-install
# scriptlets we never use, and the raw binary is more portable across
# base-image refreshes).
ARCH=""
case "${TARGETARCH}" in
    amd64) ARCH="amd64" ;;
    arm64) ARCH="arm64" ;;
    arm)   ARCH="arm" ;;
    *)     echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;;
esac

DEST="/usr/local/bin/cloudflared"
URL="https://github.com/cloudflare/cloudflared/releases/download/${APP_VERSION}/cloudflared-linux-${ARCH}"

echo "Downloading cloudflared v${APP_VERSION} for linux-${ARCH}..."
curl -fsSL --retry 3 --retry-delay 5 -o "${DEST}" "${URL}"
chmod 0755 "${DEST}"

# Smoke-test the binary so a corrupted download fails the build, not the
# user's first start.
if ! "${DEST}" --version >/dev/null 2>&1; then
    echo "ERROR: cloudflared binary failed --version smoke test"
    exit 1
fi

INSTALLED_VERSION="$("${DEST}" --version 2>/dev/null | head -n1 || echo unknown)"

# Allow cloudflared to bind low ports (rarely needed because the tunnel
# is outbound-only, but harmless and matches the upstream .deb's
# behaviour for the `cloudflared tunnel ingress` direct-listen modes).
setcap 'cap_net_bind_service=+ep' "${DEST}" 2>/dev/null || true

# Stamp build metadata into the image so the runtime banner can show it.
mkdir -p /etc/cf-tunnel
cat > /etc/cf-tunnel/build-info << EOF
APP_VERSION=${APP_VERSION}
TUNNEL_ARCH=${ARCH}
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
INSTALLED_VERSION=${INSTALLED_VERSION}
EOF
chmod 0644 /etc/cf-tunnel/build-info

echo "cloudflared installed: ${INSTALLED_VERSION} (linux-${ARCH}) -> ${DEST}"
