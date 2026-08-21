#!/usr/bin/env sh
set -eu
# Prefer explicit APP_VERSION; otherwise read the bake-time file from the image.
if [ -z "${APP_VERSION:-}" ] && [ -f /app/APP_VERSION ]; then
  APP_VERSION="$(cat /app/APP_VERSION)"
  export APP_VERSION
fi

# Spotify rejects http://192.168.x redirect URIs. A self-signed HTTPS listener
# on the LAN IP lets the browser return to the NUC after login.
export HTTPS_PORT="${HTTPS_PORT:-4443}"
export TLS_CERT_PATH="${TLS_CERT_PATH:-/data/certs/tls.crt}"
export TLS_KEY_PATH="${TLS_KEY_PATH:-/data/certs/tls.key}"
HOST="$(printf '%s' "${PUBLIC_API_BASE:-}" | sed -n 's#^https\?://\([^:/]*\).*#\1#p')"
if [ -z "$HOST" ] || [ "$HOST" = "127.0.0.1" ] || [ "$HOST" = "localhost" ]; then
  HOST="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
fi
if [ -n "$HOST" ] && [ "$HOST" != "127.0.0.1" ] && [ "$HOST" != "localhost" ]; then
  if [ -z "${PUBLIC_API_BASE:-}" ]; then
    export PUBLIC_API_BASE="http://${HOST}:4000"
  fi
  mkdir -p "$(dirname "$TLS_CERT_PATH")"
  case "$HOST" in
    *[a-zA-Z]*) SAN="DNS:${HOST}" ;;
    *) SAN="IP:${HOST}" ;;
  esac
  GEN=1
  if [ -f "$TLS_CERT_PATH" ] && [ -f "$TLS_KEY_PATH" ]; then
    if openssl x509 -in "$TLS_CERT_PATH" -noout -text 2>/dev/null | grep -F -q "$HOST"; then
      GEN=0
    fi
  fi
  if [ "$GEN" = 1 ]; then
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
      -keyout "$TLS_KEY_PATH" -out "$TLS_CERT_PATH" -days 825 \
      -subj "/CN=${HOST}" \
      -addext "subjectAltName=${SAN}"
  fi
else
  unset HTTPS_PORT
fi

exec "$@"
