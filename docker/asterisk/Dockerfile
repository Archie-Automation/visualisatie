FROM ubuntu:24.04

# Asterisk zit in Ubuntu universe, niet in main. De officiële image heeft
# universe niet op elke snapshot aan staan; zonder dit faalt de image-build
# en blijft poort 5060 dicht terwijl de app-update toch "gelukt" is.
# policy-rc.d: postinst mag systemd niet starten in Docker.
ENV DEBIAN_FRONTEND=noninteractive
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
  && chmod +x /usr/sbin/policy-rc.d \
  && if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
       sed -i '/^Components: /{ /universe/! s/$/ universe/ }' /etc/apt/sources.list.d/ubuntu.sources; \
     fi \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    asterisk \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /etc/asterisk /var/run/asterisk /var/log/asterisk

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5060/udp 8088 8089 5038

ENTRYPOINT ["/entrypoint.sh"]
