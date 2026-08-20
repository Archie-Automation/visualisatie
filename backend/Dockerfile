# Production API-only image (zonder Flutter web).
# Volledige stack (UI + API + go2rtc): gebruik docker/Dockerfile vanaf repo-root
#   docker compose -f docker/docker-compose.yml up -d --build
#
# Dit bestand blijft nuttig voor API-only builds / CI zonder Flutter SDK.
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json tsconfig.json ./
# better-sqlite3 has no musl prebuild for current Node 20 — compile it.
RUN apk add --no-cache python3 make g++ \
  && npm ci
COPY src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

# ffmpeg: nodig voor go2rtc-bronnen met "ffmpeg:rtsp://..."
# tini: netjes afsluiten wanneer Node go2rtc-child beëindigt
RUN apk add --no-cache ffmpeg tini

COPY --from=alexxit/go2rtc:latest /usr/local/bin/go2rtc /usr/local/bin/go2rtc

COPY package*.json ./
RUN apk add --no-cache python3 make g++ \
  && npm ci --omit=dev \
  && apk del python3 make g++
COPY --from=build /app/dist ./dist

RUN mkdir -p /media

# Standaard: backend start go2rtc zelf (geen tweede container).
ENV GO2RTC_AUTO_START=1
ENV GO2RTC_CONFIG_PATH=/media/go2rtc.yaml
ENV MEDIA_BASE_URL=http://127.0.0.1:1984
ENV FFMPEG_PATH=/usr/bin/ffmpeg

EXPOSE 4000 1984 8554 8555/tcp 8555/udp

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/index.js"]
