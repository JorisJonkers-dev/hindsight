FROM ghcr.io/vectorize-io/hindsight-api:0.9.2@sha256:7b14a1f4062252992d0176758753615e0a2071d9a269995be007be223ab01812

COPY hindsight-start /usr/local/bin/hindsight-start
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/hindsight-start"]
