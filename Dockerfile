# syntax=docker/dockerfile:1
FROM scratch AS dex-auth-source
ADD https://github.com/eeekcct/hermes-dex-auth-plugin.git#b6ddc1e89e3fe15dee8a0f90f9455637080d99d2 /src/

FROM nousresearch/hermes-agent:v0.23.1@sha256:276d44685c65c0cb2a25f190b63c65c8906f9dc76486fb1c05ae71b5826bda08

USER root
WORKDIR /opt/hermes

ARG TARGETARCH
ARG GH_AMD64_VERSION=v2.103.3
ARG GH_AMD64_SHA256=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d
ARG GH_ARM64_VERSION=v2.103.3
ARG GH_ARM64_SHA256=ee32df2323c8847f5fac6cb6b4b69ca75828e9329a8f22f677021f7b3306ce63

RUN apt-get -o Acquire::Retries=3 update \
 && apt-get -o Acquire::Retries=3 install -y --no-install-recommends libopus0 \
 && rm -rf /var/lib/apt/lists/*

# Use GitHub's release binary rather than a third-party CLI image.
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) version="${GH_AMD64_VERSION#v}"; checksum="${GH_AMD64_SHA256}" ;; \
      arm64) version="${GH_ARM64_VERSION#v}"; checksum="${GH_ARM64_SHA256}" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    archive="gh_${version}_linux_${TARGETARCH}"; \
    if ! curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 180 \
      "https://github.com/cli/cli/releases/download/v${version}/${archive}.tar.gz" \
      -o /tmp/gh.tar.gz; then \
      curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 180 \
        "https://api.github.com/repos/cli/cli/releases/tags/v${version}" \
        -o /tmp/gh-release.json; \
      asset_id="$(python3 -c 'import json, sys; print(next(asset["id"] for asset in json.load(open("/tmp/gh-release.json"))["assets"] if asset["name"] == sys.argv[1]))' "${archive}.tar.gz")"; \
      curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 180 \
        -H "Accept: application/octet-stream" \
        "https://api.github.com/repos/cli/cli/releases/assets/${asset_id}" \
        -o /tmp/gh.tar.gz; \
    fi; \
    printf '%s  %s\n' "$checksum" /tmp/gh.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/gh.tar.gz -C /tmp "${archive}/bin/gh"; \
    install -m 0755 "/tmp/${archive}/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh-release.json /tmp/gh.tar.gz "/tmp/${archive}"; \
    gh --version

COPY --chmod=0755 scripts/build-dependencies.sh /usr/local/libexec/build-hermes-dependencies
COPY --from=dex-auth-source /src/src/hermes_dex_auth_plugin/ /opt/hermes/plugins/dashboard_auth/dex-auth/
COPY --from=dex-auth-source /src/plugin.yaml /opt/hermes/plugins/dashboard_auth/dex-auth/plugin.yaml
RUN /usr/local/libexec/build-hermes-dependencies

ARG VCS_REF=unknown
LABEL org.opencontainers.image.source="https://github.com/eeekcct/hermes-agent-image" \
      org.opencontainers.image.description="Hermes Agent with GitHub CLI, Opus, Edge TTS, local Whisper STT and Dex dashboard authentication" \
      org.opencontainers.image.revision="${VCS_REF}"

# Keep the upstream root entrypoint: it prepares the volume and drops privileges
# to the hermes user before starting the supervised gateway/dashboard.
