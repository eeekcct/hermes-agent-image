#!/bin/sh
set -eu

mkdir -p "$HERMES_HOME"
gh --version
hermes --version
python - <<'PY'
from ctypes.util import find_library
import edge_tts
import discord.opus
import ctranslate2
import onnxruntime
from faster_whisper import WhisperModel

library = find_library("opus")
assert library, "Opus was not found by ctypes"
discord.opus.load_opus(library)
assert discord.opus.is_loaded()
discord.opus.Decoder()
compute_types = ctranslate2.get_supported_compute_types("cpu")
assert compute_types, "No CTranslate2 CPU compute types are available"
print("Edge TTS, Whisper STT imports and Opus decoder: OK")
print("CTranslate2 CPU compute types:", sorted(compute_types))
PY

cat > "$HERMES_HOME/config.yaml" <<'YAML'
dashboard:
  oauth:
    dex:
      issuer: https://dex.example.invalid
      client_id: hermes-dashboard
      access:
        users:
          - connector_id: github
            user_id: "123"
YAML

python - <<'PY'
from hermes_cli.dashboard_auth.registry import get_provider
from hermes_cli.plugins import discover_plugins

discover_plugins()
assert get_provider("dex") is not None, "Bundled Dex auth provider did not register"
print("Bundled Dex dashboard auth: OK")
PY
