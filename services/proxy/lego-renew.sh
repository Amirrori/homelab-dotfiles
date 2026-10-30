#!/bin/sh
# Obtain/renew the single LE cert (name = first domain) via Porkbun DNS-01.
# Managed by hand. Extra args are passed to lego.
exec /usr/local/bin/lego run --accept-tos --dns porkbun \
  --env-file /etc/lego/porkbun.env --path /var/lib/lego --account-id proxy \
  --dns.resolvers 1.1.1.1:53 --log.format text \
  --deploy-hook /usr/local/sbin/lego-deploy-nginx.sh \
  --force-cert-domains \
  -d music.example.com \
  -d torrent.example.com \
  -d soulseek.example.com \
  -d lidarr.example.com \
  -d soularr.example.com \
  -d panel.example.com \
  -d wings.example.com \
  -d presence.example.com \
  -d adguard.example.com \
  -d dns.example.com \
  "$@"
