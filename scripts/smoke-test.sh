#!/bin/sh
set -eu

mkdir -p "$HERMES_HOME"
gh --version
hermes --version
python - <<'PY'
from ctypes.util import find_library
import edge_tts
import discord.opus

library = find_library("opus")
assert library, "Opus was not found by ctypes"
discord.opus.load_opus(library)
assert discord.opus.is_loaded()
discord.opus.Decoder()
print("Edge TTS import and Opus decoder: OK")
PY
