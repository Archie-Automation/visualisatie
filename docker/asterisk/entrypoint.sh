#!/bin/sh
set -eu
# Asterisk leest /etc/asterisk; Archie schrijft dezelfde files via bind-mount.
mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk /var/lib/asterisk
echo "Archie VoIP: wachten op pjsip.conf in /etc/asterisk ..."
i=0
while [ ! -f /etc/asterisk/pjsip.conf ]; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then
    echo "Nog geen pjsip.conf — backend schrijft die bij starten/opslaan."
    i=0
  fi
  sleep 2
done
echo "pjsip.conf aanwezig — Asterisk starten"
exec asterisk -f
