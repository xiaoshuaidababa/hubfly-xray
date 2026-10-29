# Container PaaS (Hubfly, BreezeDeploy...): nginx on $PORT answers 200 for health checks
# and forwards the WebSocket path to xray on 127.0.0.1:10000.
FROM ghcr.io/xtls/xray-core:latest AS src
FROM alpine:3.20
RUN apk add --no-cache nginx
COPY --from=src /usr/local/bin/xray /usr/local/bin/xray
COPY --chmod=755 entrypoint.sh /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
