FROM debian:bookworm-slim

# policy-rc.d: Debian postinst mag Asterisk niet via systemd starten in Docker
# (dat laat `apt-get install asterisk` anders falen → hele compose-update stuk).
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
  && chmod +x /usr/sbin/policy-rc.d \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    asterisk \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /etc/asterisk /var/run/asterisk /var/log/asterisk

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5060/udp 8088 8089 5038

ENTRYPOINT ["/entrypoint.sh"]
