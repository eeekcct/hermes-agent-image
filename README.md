# hermes-agent-image

A Hermes Agent container image with GitHub CLI, Opus, Edge TTS, local Whisper speech recognition, and Dex dashboard authentication.
Supports linux/amd64 and linux/arm64.

## Publishing

The **Build** workflow builds and tests pull requests without publishing,
and smoke-tests the release verifier installation with read-only permissions.
The **Build and push** workflow publishes after changes to the Dockerfile,
build script, build context rules, or publishing workflows are merged into main.
It can also be run manually from main.

After the first publish, set the package visibility to **Public** in GitHub Packages.
Images are published as `ghcr.io/eeekcct/hermes-agent-image:sha-<commit SHA>` and `latest`.
Use a commit SHA tag or image digest for deployments.

Published images include BuildKit-generated SPDX SBOMs for both architectures.
Build and release are managed by `.github/workflows/_image.yml`, a reusable
workflow with no caller-supplied build commands, image digests, or runner inputs.
It follows GitHub's [SLSA v1 Build Level 3 guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating).

- `_build.yml` runs Dockerfile builds and runtime smoke tests on fresh
  GitHub-hosted amd64/arm64 VMs. These jobs have no OIDC or attestation permission.
- Release builds do not import or export persistent Actions build caches.
  The publish export reuses only that job's own BuildKit cache after its test.
  Pull requests use a separate `pr-image-*` cache and read-only token permissions.
- `_image.yml` assembles the index using the two image index digests returned
  by this run, preserving their SBOMs. Mutable architecture tags are not inputs.
- A fresh signing VM, without source checkout or application/test execution,
  uses GitHub's official `actions/attest` to sign the final index digest and
  publish provenance to GitHub and GHCR.
- A separate read-only verification VM runs `gh attestation verify` to check
  the index digest, reusable signer workflow, signer/source commit, main ref,
  and hosted runner. It has no OIDC, attestation-write, or package-write permission.
- The same VM checks the verified bundle with the new
  [SLSA Verifier](https://github.com/slsa-framework/verifier), requiring signatures,
  the expected signer, source repository, main branch, and image digest, with
  the reviewed `_image.yml` workflow explicitly trusted as the builder.
  The verifier version and SHA-256 are pinned in `_image.yml`.
  The SHA-pinned official
  [`slsa-framework/actions/install/verifier`](https://github.com/slsa-framework/actions/tree/v0.2.0/install/verifier)
  action installs the CLI and verifies its release provenance. An additional
  checksum check retains the exact binary pin before the image policy check.
  Verification remains in named workflow steps without project script files
  or a source checkout.
- Only after both verifiers succeed does a separate promotion job update `latest`.
  The Actions summary includes the image digest, source commit, level, and check results.

The signed subject is the multi-platform index, whose immutable descriptors
bind the amd64/arm64 images and SBOMs. It is not a separate signature for every
base image or dependency. Architecture/commit tags can exist if a later
attestation or verification step fails; `latest` is promoted only on success.
Pull request builds never invoke the signing workflow.
The overall exit status gates promotion, including when a failed verifier still
prints `SLSA Level: 3`. The workflow never accepts a numeric level or a `PASS`
string by itself.

### Verify a released image

Authenticate with `gh auth login` and `docker login ghcr.io`. Use the index
digest from the release and a commit you have independently reviewed and trust:

```sh
IMAGE=ghcr.io/eeekcct/hermes-agent-image
DIGEST='sha256:<released-index-digest>'
TRUSTED_COMMIT='<reviewed-40-character-commit>'

gh attestation verify "oci://$IMAGE@$DIGEST" \
  --repo eeekcct/hermes-agent-image \
  --signer-workflow eeekcct/hermes-agent-image/.github/workflows/_image.yml \
  --signer-digest "$TRUSTED_COMMIT" \
  --source-digest "$TRUSTED_COMMIT" \
  --source-ref refs/heads/main \
  --deny-self-hosted-runners
```

Replace the placeholder values before running. To verify the attestation bundle
stored in GHCR instead of retrieving it from GitHub, add `--bundle-from-oci`.
Do not derive `TRUSTED_COMMIT` solely from an untrusted attestation. Workflow
changes must be reviewed: the local reusable workflow is versioned with the
source commit, and verification pins that version. Pin deployments by digest.

Inspect the SBOM inventory with Docker Buildx:

```sh
docker buildx imagetools inspect ghcr.io/eeekcct/hermes-agent-image:latest \
  --format '{{json .SBOM}}'
```

This is a configuration targeting SLSA Build Level 3, not an independent
certification. The verifier's level is a policy result based on trusting the
reviewed reusable workflow; it is not an independent audit of builder isolation.
SLSA assesses the build
process and provenance integrity; it does not guarantee vulnerability-free
application code or dependencies. The SBOM is BuildKit metadata, not a
GitHub-signed SBOM attestation, and no vulnerability scan is added here.

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

The [Dex dashboard auth plugin](https://github.com/eeekcct/hermes-dex-auth-plugin) is bundled at the commit pinned in the Dockerfile.
Configure `dashboard.oauth.dex` in your Hermes configuration to activate it.
For a confidential Dex client, supply `HERMES_DEX_CLIENT_SECRET` at runtime.

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
Renovate is configured in `renovate.json5`. It proposes updates to the base image,
GitHub Actions, GitHub CLI versions and checksums for both architectures, and the
SLSA Verifier version and binary checksum in both workflows. The verifier pairs
are updated together in a separate PR group from GitHub CLI and GitHub Actions.

When reviewing SLSA Verifier updates, check the official release and the paired
version and SHA-256 changes in `.github/workflows/_image.yml` and the
`.github/workflows/build.yml` installer smoke test. Keep each pair adjacent for
Renovate, and preserve the existing `gh` certificate checks and fail-closed
verifier exit-status checks.
