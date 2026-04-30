# syntax=docker/dockerfile:1.7

# Prebuilt upstream image: no source checkout and no git pull needed.
FROM ghcr.io/openclaw/openclaw:2026.4.27@sha256:3134a35220d503a67d3de12ee63bc6dfaf171425c0d7d75034636a09c81babd3

USER root

# Optional Tailscale install (enabled by default for Railway deployments).
ARG OPENCLAW_INSTALL_TAILSCALE="1"
RUN if [ "$OPENCLAW_INSTALL_TAILSCALE" = "1" ]; then \
  curl -fsSL https://tailscale.com/install.sh | sh; \
  fi

# Optional system packages to bake at build time.
# Example: --build-arg OPENCLAW_DOCKER_APT_PACKAGES="ffmpeg jq"
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
  fi

# Optional skill binaries to bake into the image.
# Example:
# --build-arg OPENCLAW_GOGCLI_URL=https://github.com/steipete/gogcli/releases/download/vX.Y.Z/gogcli_linux_amd64.tar.gz
# --build-arg OPENCLAW_GOPLACES_URL=https://github.com/steipete/goplaces/releases/download/vX.Y.Z/goplaces_linux_amd64.tar.gz
# --build-arg OPENCLAW_WACLI_URL=https://github.com/steipete/wacli/releases/download/vX.Y.Z/wacli-linux-amd64.tar.gz
ARG OPENCLAW_GOGCLI_URL=""
ARG OPENCLAW_GOPLACES_URL=""
ARG OPENCLAW_WACLI_URL=""
RUN set -eu; \
  if [ -n "$OPENCLAW_GOGCLI_URL" ]; then \
    curl -fsSL "$OPENCLAW_GOGCLI_URL" | tar -xzO gog > /usr/local/bin/gog; \
    chmod +x /usr/local/bin/gog; \
  fi; \
  if [ -n "$OPENCLAW_GOPLACES_URL" ]; then \
    curl -fsSL "$OPENCLAW_GOPLACES_URL" | tar -xzO goplaces > /usr/local/bin/goplaces; \
    chmod +x /usr/local/bin/goplaces; \
  fi; \
  if [ -n "$OPENCLAW_WACLI_URL" ]; then \
    curl -fsSL "$OPENCLAW_WACLI_URL" | tar -xzO wacli > /usr/local/bin/wacli; \
    chmod +x /usr/local/bin/wacli; \
  fi

# Railway runtime defaults: keep container stateless; persist everything under /data.
ENV OPENCLAW_GATEWAY_PORT=8080
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json
ENV OPENCLAW_PLUGIN_STAGE_DIR=/data/plugin-runtime-deps
ENV TAILSCALE_STATE_DIR=/data/tailscale
ENV TAILSCALE_SOCKET=/var/run/tailscale/tailscaled.sock
ENV OPENCLAW_DISABLE_BONJOUR=1
ENV NODE_ENV=production

COPY <<'EOF' /usr/local/bin/start-railway.sh
#!/bin/sh
set -eu

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR" "$OPENCLAW_PLUGIN_STAGE_DIR" "$TAILSCALE_STATE_DIR" /var/run/tailscale

# Start tailscaled in userspace mode when available.
if command -v tailscaled >/dev/null 2>&1; then
  echo "Starting tailscaled..."
  tailscaled \
    --state="$TAILSCALE_STATE_DIR/tailscaled.state" \
    --socket="$TAILSCALE_SOCKET" \
    --tun=userspace-networking >/tmp/tailscaled.log 2>&1 &

  # Wait briefly for tailscaled socket readiness.
  i=0
  while [ "$i" -lt 20 ]; do
    if tailscale --socket="$TAILSCALE_SOCKET" status >/dev/null 2>&1; then
      break
    fi
    i=$((i + 1))
    sleep 0.5
  done

  if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "Authenticating with Tailscale..."
    tailscale --socket="$TAILSCALE_SOCKET" up \
      --authkey="$TAILSCALE_AUTHKEY" \
      --hostname="${TAILSCALE_HOSTNAME:-openclaw-railway}" \
      --accept-routes || echo "Warning: tailscale up failed; continuing without tailnet routing"
  else
    echo "TAILSCALE_AUTHKEY not set; tailscaled running without auth"
  fi

  tailscale --socket="$TAILSCALE_SOCKET" status || true
fi

exec node /app/openclaw.mjs gateway --allow-unconfigured --bind lan --port "${OPENCLAW_GATEWAY_PORT:-8080}"
EOF
RUN chmod +x /usr/local/bin/start-railway.sh

EXPOSE 8080

HEALTHCHECK --interval=3m --timeout=10s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["/usr/local/bin/start-railway.sh"]
