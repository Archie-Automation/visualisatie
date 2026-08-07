# Build a release APK for tablet sideload / GitHub Release asset.
# Usage:
#   .\build_release_apk.ps1
#   .\build_release_apk.ps1 -ApiBase http://192.168.1.50:4000

param(
    [string]$ApiBase = "http://192.168.1.20:4000"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$line = Get-Content -Path "pubspec.yaml" | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if (-not $line) {
    throw "version: niet gevonden in pubspec.yaml"
}
$version = ($line -replace '^version:\s*', '').Trim()
if (-not $version) {
    throw "lege version in pubspec.yaml"
}

Write-Host "Building APK version $version (API_BASE=$ApiBase) ..."
flutter pub get
flutter build apk --release `
    --dart-define="APP_VERSION=$version" `
    --dart-define="API_BASE=$ApiBase"

$apk = Join-Path $PSScriptRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    throw "APK niet gevonden: $apk"
}

Write-Host ""
Write-Host "Klaar: $apk"
Write-Host "Upload dit bestand als asset bij GitHub Release-tag die bij $version past (bijv. v$($version.Split('+')[0]))."
Write-Host "Eerste installatie: adb install -r `"$apk`""
