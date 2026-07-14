# Production image: API + ingebouwde go2rtc + ffmpeg (één container op de server).
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
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
RUN npm ci --omit=dev
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
