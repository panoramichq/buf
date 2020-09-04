image:
	DOCKER_BUILDKIT=1 docker build . \
		-t operam/buf:latest

# see Dockerfile for versioning chain and specific version pick reasons
PROTOC_VERSION?=3.12.2
BUF_VERSION?=v0.21.0
VERSION:=${BUF_VERSION}-${PROTOC_VERSION}
image.push: image
	docker tag operam/buf:latest operam/buf:${VERSION}
	docker push operam/buf:latest
	docker push operam/buf:${VERSION}
