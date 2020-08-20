# syntax=docker/dockerfile:1.0.0-experimental

FROM golang:1.15.0 as workspace

ARG PROJECT=buf
ARG GO_MODULE=github.com/bufbuild/buf

ENV \
  CACHE_BASE=/cache/$PROJECT \
  GO111MODULE=on \
  GOPRIVATE=$GO_MODULE \
  GOPATH=/cache/$PROJECT/Linux/x86_64/go \
  GOBIN=/cache/$PROJECT/Linux/x86_64/bin \
  PATH=/cache/$PROJECT/Linux/x86_64/bin:${PATH}

WORKDIR /workspace

RUN --mount=target=/var/lib/apt/lists,type=cache \
    --mount=target=/var/cache/apt,type=cache \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        unzip

COPY go.mod go.sum /workspace/
RUN go mod download
COPY make /workspace/make
COPY Makefile /workspace/
RUN make dockerdeps

# ------------------------------------------------

FROM workspace as builder

COPY cmd ./cmd
COPY internal ./internal
RUN go build -ldflags "-s -w" -trimpath -o /go/bin/buf ./cmd/buf


ENV PROTOC_VERSION=3.13.0
RUN wget \
        https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip \
        -O /tmp/protoc.zip \
    && unzip /tmp/protoc.zip -d /opt/protoc \
    && chmod 755 /opt/protoc/bin/protoc


# ------------------------------------------------

# TODO: rethink using python as base. Need to add NodeJS (for typescript) and Java plugins for protoc.
FROM python:3.8-buster

RUN --mount=target=/var/lib/apt/lists,type=cache \
    --mount=target=/var/cache/apt,type=cache \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git

COPY --from=builder /go/bin/buf /usr/local/bin/buf
COPY --from=builder /opt/protoc /usr/local/

RUN pip install \
    --no-cache-dir \
    "betterproto[compiler]" \
    mypy-protobuf

ENTRYPOINT ["/usr/local/bin/buf"]
