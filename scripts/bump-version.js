#!/usr/bin/env node
/**
 * Bumps the build number in app/pubspec.yaml and prints the new version.
 * Format: "0.1.0+N" — only the build counter (N) is incremented each build.
 * The semantic version (0.1.0) is only changed manually.
 *
 * Usage: node scripts/bump-version.js
 * Output: "0.1.0+42"  (just the version string, for shell capture)
 */

const fs = require('fs');
const path = require('path');

const pubspecPath = path.join(__dirname, '..', 'app', 'pubspec.yaml');
let content = fs.readFileSync(pubspecPath, 'utf8');

const match = content.match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)/m);
if (!match) {
  process.stderr.write('ERROR: Could not parse version in pubspec.yaml\n');
  process.exit(1);
}

const semver = match[1];
const build  = parseInt(match[2], 10) + 1;
const newVersion = `${semver}+${build}`;

content = content.replace(
  /^version:\s*.+/m,
  `version: ${newVersion}`
);

fs.writeFileSync(pubspecPath, content, 'utf8');
process.stdout.write(newVersion);
