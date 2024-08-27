ARG ALPINE_VERSION=3.19
ARG GOLANG_VERSION=1.23

FROM --platform=${BUILDPLATFORM:-linux/amd64} golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} as builder

RUN apk add --update --no-cache git

COPY . /app

WORKDIR /app/cmd/swgp-go

ARG TARGETARCH TARGETOS

RUN \
  --mount=type=cache,target=/root/.cache/go-build \
  --mount=type=cache,target=/go/pkg \
  CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
  go build -ldflags="-w -s" -o /usr/bin/swgp-go main.go

FROM --platform=${TARGETPLATFORM:-linux/amd64} alpine:${ALPINE_VERSION}

# Install openssl
RUN apk add --no-cache openssl

COPY --from=builder /usr/bin/swgp-go /usr/bin/
COPY --from=builder /app/docs/client.example.json /etc/swgp-go/client.example.json
COPY --from=builder /app/docs/server.example.json /etc/swgp-go/server.example.json

RUN chmod +x /usr/bin/swgp-go

# Generate and print PROXY_PSK if not provided
RUN if [ -z "$PROXY_PSK" ]; then \
        export PROXY_PSK=$(openssl rand -base64 32); \
        echo "Generated PROXY_PSK: $PROXY_PSK"; \
    fi && \
    echo "$PROXY_PSK" > /tmp/proxy_psk.txt

CMD if [ "$MODE" = "client" ]; then \
        cp /etc/swgp-go/client.example.json /etc/swgp-go/config.json && \
        PROXY_PSK=$(cat /tmp/proxy_psk.txt) && \
        sed -i "s|\"proxyPSK\": \".*\"|\"proxyPSK\": \"$PROXY_PSK\"|" /etc/swgp-go/config.json && \
        sed -i "s|\"proxyEndpoint\": \".*\"|\"proxyEndpoint\": \"$PROXY_ENDPOINT\"|" /etc/swgp-go/config.json; \
    elif [ "$MODE" = "server" ]; then \
        cp /etc/swgp-go/server.example.json /etc/swgp-go/config.json && \
        PROXY_PSK=$(cat /tmp/proxy_psk.txt) && \
        sed -i "s|\"proxyPSK\": \".*\"|\"proxyPSK\": \"$PROXY_PSK\"|" /etc/swgp-go/config.json && \
        sed -i "s|\"wgEndpoint\": \".*\"|\"wgEndpoint\": \"$WG_ENDPOINT\"|" /etc/swgp-go/config.json; \
    fi && \
    /usr/bin/swgp-go -confPath /etc/swgp-go/config.json -logLevel info