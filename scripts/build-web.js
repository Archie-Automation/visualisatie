#!/usr/bin/env node
/**
 * Bumps the build number, then runs flutter build web with APP_VERSION set.
 * Replaces the inline flutter commands in package.json so the version is
 * always embedded in the compiled JS bundle.
 *
 * Usage (via package.json):
 *   node scripts/build-web.js            → normal build
 *   node scripts/build-web.js --phone    → add --pwa-strategy=none
 */

const { execSync } = require('child_process');
const path = require('path');

const isPhone = process.argv.includes('--phone');

// 1. Bump build number and capture new version string.
const version = execSync(`node "${path.join(__dirname, 'bump-version.js')}"`)
  .toString()
  .trim();

process.stdout.write(`Building version ${version}...\n`);

// 2. Run flutter build web with version embedded.
const pwaFlag = isPhone ? ' --pwa-strategy=none' : '';
const cmd =
  `flutter build web --dart-define=API_BASE= --dart-define=APP_VERSION=${version} --release${pwaFlag}`;

execSync(cmd, {
  cwd: path.join(__dirname, '..', 'app'),
  stdio: 'inherit',
});
