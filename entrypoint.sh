#!/bin/sh
# nginx on $PORT (health checks get 200), WS path proxied to xray VLESS on 127.0.0.1:10000.
set -eu

UUID="${UUID:-00000000-0000-0000-0000-000000000000}"
PORT="${PORT:-8080}"
WSPATH="${WSPATH:-/tk-rail}"
XPORT=10000

if [ "$UUID" = "00000000-0000-0000-0000-000000000000" ] || [ "$UUID" = "CHANGE_ME" ]; then
  echo "WARNING: set a real UUID env before handing out client links" >&2
fi
case "$WSPATH" in /*) ;; *) WSPATH="/$WSPATH" ;; esac

cat > /tmp/xray.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "127.0.0.1", "port": ${XPORT}, "protocol": "vless",
    "settings": { "clients": [ { "id": "${UUID}" } ], "decryption": "none" },
    "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${WSPATH}" } }
  }],
  "outbounds": [ { "protocol": "freedom" } ]
}
JSON

mkdir -p /tmp/nginx
cat > /tmp/nginx.conf <<NGX
worker_processes 1;
pid /tmp/nginx/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 1024; }
http {
  access_log off;
  client_body_temp_path /tmp/nginx/body;
  proxy_temp_path /tmp/nginx/proxy;
  fastcgi_temp_path /tmp/nginx/fastcgi;
  uwsgi_temp_path /tmp/nginx/uwsgi;
  scgi_temp_path /tmp/nginx/scgi;
  server {
    listen ${PORT} default_server;
    location = ${WSPATH} {
      proxy_pass http://127.0.0.1:${XPORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
    location / {
      default_type text/html;
      return 200 '<!doctype html><title>ok</title><p>ok</p>';
    }
  }
}
NGX

echo "starting xray on 127.0.0.1:${XPORT}, nginx on port ${PORT}, path ${WSPATH}"
/usr/local/bin/xray run -c /tmp/xray.json &
exec nginx -e /dev/stderr -c /tmp/nginx.conf -g 'daemon off;'
