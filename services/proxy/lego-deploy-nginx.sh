#!/bin/sh
# Called by lego after a cert is created/renewed. Managed by hand.
set -eu
src=/var/lib/lego/certificates
dst=/etc/nginx/certs
install -d -m 700 -o root -g root "$dst"
for crt in "$src"/*.crt; do
  case "$crt" in *.issuer.crt) continue ;; esac
  name=$(basename "$crt" .crt)
  install -m 644 -o root -g root "$crt" "$dst/$name.crt"
  install -m 600 -o root -g root "$src/$name.key" "$dst/$name.key"
done
if systemctl is-active -q nginx; then nginx -t -q && systemctl reload nginx; fi
logger -t lego-deploy "certs deployed to $dst"
