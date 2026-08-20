# Production image: Flutter web UI + Node API + go2rtc + ffmpeg.
# Build from repo root:
#   docker build -f docker/Dockerfile -t luxe-knx-stack:latest .
#
# Or via compose from docker/: docker compose up -d --build

# ── Flutter web ──────────────────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS flutter
WORKDIR /src/app
COPY app/pubspec.yaml ./
RUN flutter pub get
COPY app/ ./
# Use pubspec version as APP_VERSION (no bump during image build).
RUN VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '\r')" \
  && flutter build web --release \
       --dart-define=API_BASE= \
       --dart-define=APP_VERSION="$VERSION" \
       --pwa-strategy=none \
  && printf '%s' "$VERSION" > /tmp/app_version.txt

# ── Backend TypeScript compile ───────────────────────────────────────────────
FROM node:20-alpine AS backend-build
WORKDIR /app
COPY backend/package*.json backend/tsconfig.json ./
# better-sqlite3 has no musl prebuild for current Node 20 — compile it.
RUN apk add --no-cache python3 make g++ \
  && npm ci
COPY backend/src ./src
RUN npm run build

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV WEB_ROOT=/app/web
ENV GO2RTC_AUTO_START=1
ENV GO2RTC_CONFIG_PATH=/media/go2rtc.yaml
ENV MEDIA_BASE_URL=http://127.0.0.1:1984
ENV FFMPEG_PATH=/usr/bin/ffmpeg
ENV LOG_STORE_PATH=/data/logs.db
ENV HVAC_LOCK_STORE_PATH=/data/hvac-locks.json
ENV SPOTIFY_STORE_PATH=/data/spotify.json

RUN apk add --no-cache ffmpeg tini \
  && mkdir -p /app/web /media /data

COPY --from=alexxit/go2rtc:latest /usr/local/bin/go2rtc /usr/local/bin/go2rtc

COPY backend/package*.json ./
RUN apk add --no-cache python3 make g++ \
  && npm ci --omit=dev \
  && apk del python3 make g++
COPY --from=backend-build /app/dist ./dist
COPY --from=flutter /src/app/build/web /app/web
COPY --from=flutter /tmp/app_version.txt /app/APP_VERSION
# Embed version for GET /api/version (same string as Flutter dart-define).
ENV APP_VERSION_FILE=/app/APP_VERSION

# entrypoint sets APP_VERSION from file if not already provided
COPY docker/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 4000 1984 8554 8555/tcp 8555/udp

ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
CMD ["node", "dist/index.js"]
