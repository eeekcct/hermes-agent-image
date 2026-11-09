# hermes-agent-image

A Hermes Agent container image with GitHub CLI, Opus, Edge TTS, and local Whisper speech recognition.
Supports linux/amd64 and linux/arm64.

## Publishing

The **Build** workflow builds and tests pull requests without publishing.
The **Build and push** workflow publishes after changes to the Dockerfile,
build script, build context rules, or publishing workflows are merged into main.
It can also be run manually from main.

After the first publish, set the package visibility to **Public** in GitHub Packages.
Images are published as `ghcr.io/eeekcct/hermes-agent-image:sha-<commit SHA>` and `latest`.
Use a commit SHA tag or image digest for deployments.

Published images include a BuildKit SPDX SBOM (detected software inventory) and
`mode=max` provenance (build inputs and recipe) for both architectures. They are
attached to the GHCR image index and retained in the multi-platform tags.

The workflow smoke-tests a locally loaded image, then exports the cached build
directly to GHCR with attestations. It checks that the published image's config
digest matches the tested image, and requires both attestation types for each
architecture before updating `latest`. A mismatch fails the release; the
architecture/commit tags may already exist, but `latest` is not promoted.
Pull request builds test locally without publishing attestations.

To check a published image (Docker Buildx and Python 3 required):

```sh
python3 scripts/verify-attestations.py \
  ghcr.io/eeekcct/hermes-agent-image:latest \
  --platform amd64 --platform arm64
```

Attestations provide inventory and build metadata; this does not add a
cryptographic publisher signature or perform vulnerability scanning. `mode=max`
includes build argument values, so credentials must use BuildKit secret mounts,
never build arguments.

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

Whisper model files are downloaded on first use and are not bundled in the image.

## Building locally

```sh
docker buildx build --load -t hermes-agent-image:local .
docker run --rm -i --user 10000:10000 \
  -e HOME=/tmp/hermes-image-check -e HERMES_HOME=/tmp/hermes-image-check \
  --entrypoint /bin/sh hermes-agent-image:local -s < scripts/smoke-test.sh
```

When upgrading Hermes, update the base image and digest in the Dockerfile and
check `scripts/build-dependencies.sh` against the new upstream Dockerfile.
Renovate proposes updates to the base image, GitHub Actions, and GitHub CLI
versions and checksums for both architectures.
