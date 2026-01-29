FROM docker.1ms.run/oven/bun:latest AS builder
ENV HTTP_PROXY="http://pac.router.easyops.local:8118"
ENV HTTPS_PROXY="http://pac.router.easyops.local:8118"

WORKDIR /build
COPY web/package.json .
COPY web/bun.lock .
RUN rm -rf ~/.bun/install/cache && bun install
COPY ./web .
COPY ./VERSION .
RUN DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) bun run build

FROM docker.1ms.run/golang:alpine AS builder2
ENV GO111MODULE=on CGO_ENABLED=0
ENV HTTP_PROXY="http://pac.router.easyops.local:8118"
ENV HTTPS_PROXY="http://pac.router.easyops.local:8118"

ARG TARGETOS
ARG TARGETARCH
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}
ENV GOEXPERIMENT=greenteagc

WORKDIR /build

ADD go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=builder /build/dist ./web/dist
RUN go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api

FROM docker.1ms.run/debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata libasan8 wget \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

COPY --from=builder2 /build/new-api /
EXPOSE 3000
WORKDIR /data
ENTRYPOINT ["/new-api"]
