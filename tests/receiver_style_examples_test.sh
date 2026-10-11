#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repository required}
if rg -n 'model->open_cached[[:space:]]*\(|cpkt_audio_(decoder_(read_f32_mono_16k|info|destroy)|encoder_(write_f32|close|destroy)|vox_(push_f32_mono_16k|flush|destroy)|capture_(start|read_f32_mono_16k|stop|destroy)|playback_(start|write_f32_mono_16k|drain|stop|destroy))[[:space:]]*\(|cpkt_sus_(model_(open_path|open_cached|info|create_transcriber|destroy)|transcriber_(transcribe_f32_mono_16k|transcribe_f32_mono_16k_text|transcribe_audio_decoder_segmented|transcribe_audio_decoder_segmented_text|revised_text|destroy))[[:space:]]*\(|cpkt_sus_model[[:space:]]*\*|cpkt_sus_model_config' \
  "$repo/docs/audio-sus-facade-spec.md" "$repo/examples"/*/main.c; then
  printf 'Docs and examples must use the public instance receiver methods\n' >&2
  exit 1
fi
