#!/bin/sh
set -eu

cd /opt/hermes
export HERMES_HOME=/tmp/hermes-image-build

# PM's build interface requires a fresh destination. Rebuild at the final path
# so Python entry-point shebangs remain valid. The toolchain and PM runtime live
# outside .venv and are retained from the upstream image.
rm -rf /opt/hermes/.venv
rm -f /opt/hermes/manifest.json
/usr/local/bin/python3 -m pm.build_env \
    --source /opt/hermes \
    --python /usr/local/bin/python3 \
    --cache /opt/hermes/uv-cache \
    --out /opt/hermes/.venv \
    --no-install-project --sealed --record-selection \
    --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock \
    --extra azure-identity --extra matrix --extra google-chat --extra fal \
    --extra documents --extra edge-tts --extra stt-whisper

# Recreate the same payload manifest and launchers as the upstream Dockerfile.
# The recorded baseline includes Edge TTS and Whisper STT, including after future PM syncs.
/opt/hermes/.venv/bin/python -m docker.build_agent
chmod 0644 /opt/hermes/tools/facts.json
chmod -R a+rX,go-w /opt/hermes/.venv
rm -f /opt/hermes/.venv/.lock
rm -rf "$HERMES_HOME"
