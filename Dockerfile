# syntax=docker/dockerfile:1
FROM nousresearch/hermes-agent:v0.23.0@sha256:adb7890916de63245523492be8f68f9d2095fecbec4e2a6dab7960381f0fc002

USER root
WORKDIR /opt/hermes

ARG TARGETARCH
ARG GH_VERSION=2.103.3
ARG GH_ASSET_ID_AMD64=679195621
ARG GH_ASSET_ID_ARM64=679195636
ARG GH_SHA256_AMD64=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d
ARG GH_SHA256_ARM64=ee32df2323c8847f5fac6cb6b4b69ca75828e9329a8f22f677021f7b3306ce63

RUN apt-get -o Acquire::Retries=3 update \
 && apt-get -o Acquire::Retries=3 install -y --no-install-recommends libopus0 \
 && rm -rf /var/lib/apt/lists/*

# Use GitHub's release binary rather than a third-party CLI image.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) checksum="${GH_SHA256_AMD64}"; asset_id="${GH_ASSET_ID_AMD64}" ;; \
      arm64) checksum="${GH_SHA256_ARM64}"; asset_id="${GH_ASSET_ID_ARM64}" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    archive="gh_${GH_VERSION}_linux_${TARGETARCH}"; \
    if ! curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 180 \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${archive}.tar.gz" \
      -o /tmp/gh.tar.gz; then \
      curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 180 \
        -H "Accept: application/octet-stream" \
        "https://api.github.com/repos/cli/cli/releases/assets/${asset_id}" \
        -o /tmp/gh.tar.gz; \
    fi; \
    printf '%s  %s\n' "$checksum" /tmp/gh.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/gh.tar.gz -C /tmp "${archive}/bin/gh"; \
    install -m 0755 "/tmp/${archive}/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh.tar.gz "/tmp/${archive}"; \
    gh --version

COPY --chmod=0755 scripts/build-dependencies.sh /usr/local/libexec/build-hermes-dependencies
RUN /usr/local/libexec/build-hermes-dependencies

ARG VCS_REF=unknown
LABEL org.opencontainers.image.source="https://github.com/eeekcct/hermes-agent-image" \
      org.opencontainers.image.description="Hermes Agent with GitHub CLI, Opus and Edge TTS" \
      org.opencontainers.image.revision="${VCS_REF}"

# Keep the upstream root entrypoint: it prepares the volume and drops privileges
# to the hermes user before starting the supervised gateway/dashboard.
