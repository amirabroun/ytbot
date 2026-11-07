#!/bin/bash
# Verifies the yt-dlp output contract the Swift Runner parses:
# lines starting with PROG: / TITLE: / FILE: and exit code 0.
# Usage: bash scripts/check-ytdlp.sh <video-url> [mp3]
set -uo pipefail

URL="${1:?usage: check-ytdlp.sh <video-url> [mp3]}"
MODE="${2:-mp4}"
YTDLP="$(command -v yt-dlp || echo /opt/homebrew/bin/yt-dlp)"

mkdir -p "$HOME/Downloads/ytd"

COMMON=(--newline --no-playlist --progress
  --progress-template "PROG:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_estimate_str)s"
  --print "video:TITLE:%(title)s"
  --print "after_move:FILE:%(filepath)s")

if [ "$MODE" = mp3 ]; then
  EXTRA=(-f "ba/b" -x --audio-format mp3 --audio-quality 0 --embed-thumbnail
    -o "$HOME/Downloads/ytd/Music/%(title).120B [%(id)s].%(ext)s")
else
  EXTRA=(-f "bv*[height<=1080]+ba/b[height<=1080]/b" --merge-output-format mp4
    -o "$HOME/Downloads/ytd/%(title).120B [%(id)s].%(ext)s")
fi

"$YTDLP" "${COMMON[@]}" "${EXTRA[@]}" "$URL"
echo "exit: $?"
