# hermes-agent-image

A Hermes Agent container image with GitHub CLI, Opus, and Edge TTS.
Supports linux/amd64 and linux/arm64.

## Publishing

Manually run the **Build image** workflow with `publish` enabled.
Publishing is only available from the main branch.
After the first publish, set the package visibility to **Public** in GitHub Packages.

Images are published as `ghcr.io/eeekcct/hermes-agent-image:sha-<commit SHA>` and `latest`.
Use a commit SHA tag or image digest for deployments.

## Usage

```sh
docker run -it --rm \
  -v hermes-data:/opt/data \
  ghcr.io/eeekcct/hermes-agent-image:latest setup
```

```sh
docker run -d --name hermes \
  -v hermes-data:/opt/data \
  ghcr.io/eeekcct/hermes-agent-image:latest gateway run
```

See the [official Hermes documentation](https://hermes-agent.nousresearch.com/docs/user-guide/docker) for configuration and authentication.

## Building locally

```sh
docker buildx build --load -t hermes-agent-image:local .
docker run --rm --user 10000:10000 \
  -e HOME=/tmp/hermes-image-check -e HERMES_HOME=/tmp/hermes-image-check \
  --entrypoint /usr/local/libexec/hermes-image-smoke-test \
  hermes-agent-image:local
```

When upgrading Hermes, update the base image and digest in the Dockerfile and
check `scripts/build-dependencies.sh` against the new upstream Dockerfile.
When upgrading GitHub CLI, update the SHA256 checksums for both architectures.
