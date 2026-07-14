Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path "../config/house.json")) {
  Write-Host "Geen ../config/house.json — zet eerst je projectconfig klaar." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path ".env")) {
  Write-Host "Geen .env — kopieer docker/.env.example naar docker/.env en zet JWT_SECRET en MEDIA_BASE_URL." -ForegroundColor Red
  exit 1
}

Write-Host "Bouwen en starten…"
docker compose --env-file .env up -d --build
Write-Host "Klaar. API poort 4000, go2rtc 1984 (zelfde container, network_mode: host)."
