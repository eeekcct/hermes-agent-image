#!/usr/bin/env bash
# Run only on a read-only verification runner, after the image was signed.
set -euo pipefail

: "${DIGEST:?Set DIGEST to the published multi-platform index digest}"
: "${SOURCE_SHA:?Set SOURCE_SHA to the independently trusted source commit}"
[[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]

IMAGE=ghcr.io/eeekcct/hermes-agent-image
REPOSITORY=eeekcct/hermes-agent-image
WORKFLOW="$REPOSITORY/.github/workflows/_image.yml"
BUILDER="https://github.com/$WORKFLOW@refs/heads/main"

# Review version and checksum updates together. This is the NEW verifier,
# https://github.com/slsa-framework/verifier, not the retired slsa-verifier repo.
SLSA_VERIFIER_VERSION=v0.1.1
SLSA_VERIFIER_SHA256=7053bb00052a64c77dbba4400636fd22d336c1b10aba9aac1db44744b9efba31

work_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/verify-release.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

# Preserve the certificate-backed source/signer commit and hosted-runner checks.
# gh also resolves and verifies the actual OCI index, not just a digest claim.
gh attestation verify "oci://$IMAGE@$DIGEST" \
  --repo "$REPOSITORY" \
  --signer-workflow "$WORKFLOW" \
  --signer-digest "$SOURCE_SHA" \
  --source-digest "$SOURCE_SHA" \
  --source-ref refs/heads/main \
  --deny-self-hosted-runners \
  --format json > "$work_dir/verified.json"

# Feed only a bundle already accepted by the strict gh verification above.
jq -e '.[0].attestation.bundle | select(type == "object")' \
  "$work_dir/verified.json" > "$work_dir/bundle.json"

verifier="$work_dir/slsa-verifier"
curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
  --output "$verifier" \
  "https://github.com/slsa-framework/verifier/releases/download/$SLSA_VERIFIER_VERSION/slsa-verifier-$SLSA_VERIFIER_VERSION-linux-amd64"
printf '%s  %s\n' "$SLSA_VERIFIER_SHA256" "$verifier" | sha256sum --check --strict
chmod +x "$verifier"

# This allowlist is an explicit trust decision about the reviewed reusable
# workflow. The reported level is a policy result, not a platform certification.
# Require the OVERALL exit status: a failed subject check can still print L3.
"$verifier" build \
  --require-signatures \
  --signer "sigstore::https://token.actions.githubusercontent.com::$BUILDER" \
  --param "expected_source:github.com/$REPOSITORY" \
  --param "trusted_builders:[$BUILDER]" \
  --param 'expected_branch:refs/heads/main' \
  --subject "$DIGEST" \
  --level 3 \
  --verbose \
  "$work_dir/bundle.json" | tee "$work_dir/result.txt"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### Release provenance verification passed\n\n'
    printf 'Image: `%s@%s`\n\n' "$IMAGE" "$DIGEST"
    printf 'Source and signer commit: `%s`\n\n' "$SOURCE_SHA"
    printf '```text\n'
    cat "$work_dir/result.txt"
    printf '```\n\n'
    printf 'The SLSA level is a policy result trusting the reviewed reusable workflow, not an independent certification.\n'
  } >> "$GITHUB_STEP_SUMMARY"
fi
