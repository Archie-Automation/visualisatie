FROM debian:bookworm-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    asterisk \
    asterisk-modules \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /etc/asterisk /var/run/asterisk /var/log/asterisk

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5060/udp 8088 8089 5038

ENTRYPOINT ["/entrypoint.sh"]
