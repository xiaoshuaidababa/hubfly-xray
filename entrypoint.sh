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
    "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${WSPATH}" } },
    "sniffing": { "enabled": true, "destOverride": ["tls", "quic"], "routeOnly": true }
  }],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ],
  "routing": { "domainStrategy": "IPIfNonMatch", "rules": [
    { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" },
    { "type": "field", "ip": ["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.168.0.0/16","198.18.0.0/15","224.0.0.0/4","240.0.0.0/4","::1/128","fc00::/7","fe80::/10"], "outboundTag": "block" },
    { "type": "field", "domain": ["regexp:\\\\.internal$","regexp:\\\\.local$","domain:metadata.google.internal"], "outboundTag": "block" },
    { "type": "field", "port": "25,465,587", "outboundTag": "block" }
  ]}
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
  server_tokens off;
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
    location = / {
      default_type text/html;
      return 200 '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Field Notes</title></head><body><h1>Field Notes</h1><p>Personal notes. Nothing to see here yet.</p></body></html>';
    }
    location / { return 404; }
  }
}
NGX
echo "starting nginx on ${PORT}"
exec nginx -p "$W" -e stderr -c "$W/nginx.conf" -g 'daemon off;'
