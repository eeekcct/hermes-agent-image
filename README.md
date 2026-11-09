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

Published images include BuildKit-generated SPDX SBOMs for both architectures.
The workflow smoke-tests a locally loaded image, then publishes the cached build
directly to GHCR with `sbom: true`. The multi-platform index retains those SBOMs.

GitHub's official `actions/attest` generates signed SLSA provenance for the final
multi-platform index and publishes it to GitHub and GHCR. Only after attestation
succeeds is that digest promoted to `latest`. Architecture/commit tags can exist
if a later publishing or attestation step fails. Pull request builds test locally
without publishing images or attestations.

Verify signed provenance with the GitHub CLI (authenticate with `gh auth login`
first):

```sh
gh attestation verify oci://ghcr.io/eeekcct/hermes-agent-image:latest \
  --repo eeekcct/hermes-agent-image
```

Inspect the SBOM inventory with Docker Buildx:

```sh
docker buildx imagetools inspect ghcr.io/eeekcct/hermes-agent-image:latest \
  --format '{{json .SBOM}}'
```

The SBOM is BuildKit metadata, not a GitHub-signed SBOM attestation. The signed
provenance identifies the GitHub workflow and source that published the index;
it is separate from BuildKit's detailed `mode=max` provenance. Neither performs
vulnerability scanning.

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
