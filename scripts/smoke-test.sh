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
