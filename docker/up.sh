#!/usr/bin/env sh
# Compatibility wrapper — prefer ../installeer.sh or ./install.sh
set -eu
cd "$(dirname "$0")"
exec ./install.sh
