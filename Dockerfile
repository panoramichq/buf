# syntax=docker/dockerfile:1.0.0-experimental

FROM golang:1.14.6 as basego

# ------------------------------------------------

FROM basego as workspace

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

FROM workspace as buf_builder

COPY cmd ./cmd
COPY internal ./internal
RUN go build -ldflags "-s -w" -trimpath -o /go/bin/buf ./cmd/buf

# ------------------------------------------------

FROM basego as mypy_builder

#RUN go env -w GO111MODULE=on && go mod init .
#RUN go get -d -v github.com/dropbox/mypy-protobuf@v1.13
#RUN go build -o ${GOPATH}/bin/protoc-gen-mypy -v github.com/dropbox/mypy-protobuf/go/src/protoc-gen-mypy

RUN go get -v github.com/dropbox/mypy-protobuf/go/src/protoc-gen-mypy

# ------------------------------------------------

FROM python:3.8-buster as grpc_python_builder

## https://github.com/grpc/grpc/issues/15675
## Will be available as ${GRPC_DIR}/bins/opt/grpc_python_plugin binary
RUN GRPC_DIR=/opt/grpc && \
    git clone --recursive --depth 1 \
        --branch v1.31.0 \
        https://github.com/grpc/grpc.git ${GRPC_DIR} && \
    cd ${GRPC_DIR} && \
    make grpc_python_plugin

# ------------------------------------------------

FROM python:3.8-buster as protoc_builder
# matching version of protoc shipped with GRPC v1.31.0
# which is latest version available as published python module
ENV PROTOC_VERSION=3.12.2
RUN wget \
        https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip \
        -O /tmp/protoc.zip \
    && unzip /tmp/protoc.zip -d /opt/protoc \
    && chmod 755 /opt/protoc/bin/protoc

# ------------------------------------------------

# TODO: rethink using python as base. Need to add NodeJS (for typescript) and Java plugins for protoc.
FROM python:3.8-slim

# may need git for some of buf or protoc functionality
#RUN --mount=target=/var/lib/apt/lists,type=cache \
#    --mount=target=/var/cache/apt,type=cache \
#    apt-get update \
#    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
#        git

COPY --from=protoc_builder /opt/protoc /usr/local

COPY --from=buf_builder /go/bin/buf /usr/local/bin/buf
COPY --from=mypy_builder /go/bin/protoc-gen-mypy /usr/local/bin/protoc-gen-mypy
COPY --from=grpc_python_builder /opt/grpc/bins/opt/grpc_python_plugin /usr/local/bin/grpc_python_plugin


ENTRYPOINT ["/usr/local/bin/buf"]
