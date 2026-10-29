#!/bin/sh
# nginx on $PORT (health checks get 200), WS path proxied to xray VLESS on 127.0.0.1:10000.
# Works on read-only root filesystems / random UIDs: picks the first writable dir.
set -u

UUID="${UUID:-00000000-0000-0000-0000-000000000000}"
PORT="${PORT:-8080}"
WSPATH="${WSPATH:-/tk-rail}"
XPORT=10000
case "$WSPATH" in /*) ;; *) WSPATH="/$WSPATH" ;; esac

W=""
for d in /tmp /dev/shm /run /var/tmp "$HOME"; do
  if [ -n "$d" ] && mkdir -p "$d/hx" 2>/dev/null && touch "$d/hx/.w" 2>/dev/null; then W="$d/hx"; break; fi
done
echo "id: $(id) workdir: ${W:-none} port: ${PORT} path: ${WSPATH}"

XCFG=$(cat <<JSON
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
)
# xray reads its config from stdin, no file needed
printf '%s' "$XCFG" | /usr/local/bin/xray run -c stdin: &

if [ -z "$W" ]; then echo "no writable dir; nginx cannot start" >&2; wait; exit 1; fi
mkdir -p "$W/body" "$W/proxy" "$W/fastcgi" "$W/uwsgi" "$W/scgi" "$W/logs"
NGXUSER=""
[ "$(id -u)" = "0" ] && NGXUSER="user root root;"
cat > "$W/nginx.conf" <<NGX
${NGXUSER}
worker_processes 1;
pid ${W}/nginx.pid;
error_log stderr warn;
events { worker_connections 1024; }
http {
  access_log off;
  client_body_temp_path ${W}/body;
  proxy_temp_path ${W}/proxy;
  fastcgi_temp_path ${W}/fastcgi;
  uwsgi_temp_path ${W}/uwsgi;
  scgi_temp_path ${W}/scgi;
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
echo "starting nginx on ${PORT}"
exec nginx -p "$W" -e stderr -c "$W/nginx.conf" -g 'daemon off;'
