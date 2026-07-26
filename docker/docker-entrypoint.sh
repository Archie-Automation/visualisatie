#!/usr/bin/env sh
set -eu
# Prefer explicit APP_VERSION; otherwise read the bake-time file from the image.
if [ -z "${APP_VERSION:-}" ] && [ -f /app/APP_VERSION ]; then
  APP_VERSION="$(cat /app/APP_VERSION)"
  export APP_VERSION
fi
exec "$@"
