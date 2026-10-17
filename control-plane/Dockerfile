FROM ghcr.io/vectorize-io/hindsight-control-plane:0.9.2@sha256:d9bf57083f7cb0a53ee5011bdfde6aae2490dbf5c360d2d1bff10473b45eb112

COPY control-plane-start /usr/local/bin/control-plane-start
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/control-plane-start"]
CMD []
