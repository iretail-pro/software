# The iRetail PRO demo: every pilot store in one container (README, "The
# demo"). Its context is put together by scripts/demo-context.sh: the
# release's node binary, the gateway and its emulators, the back office's
# and the register's browser builds, deploy's pilots and load-pilot.py.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-17 redis-server nginx python3 tini ca-certificates tzdata libstdc++6 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --home /var/lib/iretail --create-home iretail \
 && mkdir -p /run/iretail-demo/nginx-body /run/iretail-demo/nginx-proxy /var/lib/iretail-demo
ARG TARGETARCH
COPY bin/${TARGETARCH}/ /usr/local/bin/
COPY web/ /srv/web/
COPY pilots/ /srv/demo/pilots/
COPY load-pilot.py run.py nginx.conf nginx.conf.template gateway.yaml index.html devices.html /srv/demo/
ENV LANG=C.UTF-8
EXPOSE 8080-8088 50051
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/srv/demo/run.py"]
