FROM ubuntu:24.04

# Debian Bookworm heeft geen Asterisk-pakket. Ubuntu 24.04 universe wel (20 LTS).
# policy-rc.d: postinst mag systemd niet starten in Docker.
ENV DEBIAN_FRONTEND=noninteractive
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
  && chmod +x /usr/sbin/policy-rc.d \
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
