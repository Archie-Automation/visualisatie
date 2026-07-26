#!/usr/bin/env sh
# Starthulp vanaf de map van het project (Proxmox / Ubuntu).
# Gebruik:  chmod +x installeer.sh && ./installeer.sh
set -eu
cd "$(dirname "$0")/docker"
exec ./install.sh
