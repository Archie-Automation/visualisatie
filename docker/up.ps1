# Compatibility: same as install.sh (PowerShell).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "Docker ontbreekt." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path ".env")) {
  Write-Host "Geen .env — kopieer docker/.env.example naar docker/.env en zet JWT_SECRET." -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path "../config", "./go2rtc", "./data" | Out-Null

if (-not (Test-Path "../config/house.json")) {
  if (-not (Test-Path "../config/house.empty.json")) {
    Write-Host "Geen config/house.empty.json." -ForegroundColor Red
    exit 1
  }
  Copy-Item "../config/house.empty.json" "../config/house.json"
  Write-Host "Leeg huis aangemaakt: config/house.json (login admin/admin)"
} else {
  Write-Host "Bestaande config/house.json behouden."
}

Write-Host "Bouwen en starten…"
docker compose --env-file .env up -d --build
Write-Host "Klaar. App/API: http://<server-ip>:4000/  |  curl http://127.0.0.1:4000/api/version"
