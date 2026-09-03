# Build a release APK for tablet sideload / GitHub rolling release `android-latest`.
# Push naar main doet hetzelfde in GitHub Actions (zelfde pubspec-versie als de server).
# Usage:
#   .\build_release_apk.ps1
#   .\build_release_apk.ps1 -ApiBase http://192.168.1.50:4000
#   .\build_release_apk.ps1 -Publish

param(
    [string]$ApiBase = "http://192.168.1.50:4000",
    [switch]$Publish
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

if (-not $Publish) {
    Write-Host "Tablet-banner 'Installeren' vereist upload naar GitHub:"
    Write-Host "  .\build_release_apk.ps1 -Publish"
    Write-Host "Eerste installatie: adb install -r `"$apk`""
    exit 0
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) ontbreekt. Installeer gh en log in, daarna -Publish opnieuw."
}

$tag = "android-latest"
$existing = gh release view $tag 2>$null
if ($LASTEXITCODE -eq 0 -and $existing) {
    Write-Host "Release $tag bijwerken naar $version ..."
    gh release edit $tag --title $version --prerelease --notes "Tablet-APK $version"
    gh release upload $tag $apk --clobber
} else {
    Write-Host "Release $tag aanmaken ($version) ..."
    gh release create $tag $apk --prerelease --title $version --notes "Tablet-APK $version"
}

Write-Host "Geplaatst op GitHub release $tag ($version). NUC: git pull + ./installeer.sh (of Server bijwerken). Tablet toont daarna Installeren."
