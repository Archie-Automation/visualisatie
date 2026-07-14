#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"

if ! test -f ../config/house.json; then
  echo "Geen ../config/house.json — zet eerst je projectconfig klaar." >&2
  exit 1
fi

if ! test -f .env; then
  echo "Geen .env hier — kopieer docker/.env.example naar docker/.env en zet minstens JWT_SECRET en MEDIA_BASE_URL." >&2
  exit 1
fi

echo "Bouwen en starten (kan even duren)…"
docker compose --env-file .env up -d --build

echo "Klaar. API: http://<server-ip>:4000  |  go2rtc: poort 1984 (zelfde container)"
echo "Status:  curl -s http://127.0.0.1:4000/api/health"
