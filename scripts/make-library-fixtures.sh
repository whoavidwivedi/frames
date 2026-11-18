#!/usr/bin/env bash
# Regenerates assets/test-fixtures/library/* (needs ffmpeg + ffprobe). Fixtures are committed; CI has no ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/assets/test-fixtures/library"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

FF=(ffmpeg -hide_banner -loglevel error -y)
VSIZE=160x90
V264=(-c:v libx264 -preset veryslow -crf 30 -pix_fmt yuv420p -g 5 -keyint_min 5 -sc_threshold 0)
A_AAC=(-c:a aac -b:a 32k -ac 1)

# 320x180 red cover with a diagonal pattern (no text).
"${FF[@]}" -f lavfi -i "color=c=red:s=320x180,geq=r='255':g='mod(X+Y,40)*3':b='mod(X+Y,40)*2'" \
  -frames:v 1 -q:v 8 "$TMP/cover.jpg"

TONE=(-f lavfi -i "sine=frequency=440:duration=2")
COLOR=(-f lavfi -i "color=c=blue:s=${VSIZE}:r=10:d=2")

# Untagged video source: 0.15 s black, then solid orange.
"${FF[@]}" -f lavfi -i "color=c=black:s=${VSIZE}:r=10:d=0.2" \
  -f lavfi -i "color=c=orange:s=${VSIZE}:r=10:d=1.8" \
  "${TONE[@]}" \
  -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[v]" -map "[v]" -map 2:a \
  -t 2 -map_metadata -1 -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
  "${V264[@]}" "${A_AAC[@]}" -x264-params "keyint=5:min-keyint=5:scenecut=0" \
  "$TMP/untagged-src.nut"

"${FF[@]}" -i "$TMP/untagged-src.nut" -map 0 -c copy -map_metadata -1 \
  -fflags +bitexact -movflags +faststart "$OUT/untagged.mp4"

"${FF[@]}" -i "$TMP/untagged-src.nut" -map 0 -c copy -map_metadata -1 \
  -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
  -metadata:s:v encoder= -metadata:s:a encoder= "$OUT/untagged.mkv"

# Tagged MP4 with attached_pic cover.
"${FF[@]}" "${COLOR[@]}" "${TONE[@]}" -i "$TMP/cover.jpg" \
  -map 0:v -map 1:a -map 2:v -t 2 \
  "${V264[@]}" "${A_AAC[@]}" -c:v:1 mjpeg -disposition:v:1 attached_pic \
  -metadata title="Fixture Tagged Title" -metadata artist="Fixture Artist" \
  -movflags +faststart "$OUT/tagged-cover.mp4"

# Tagged MKV: Info Title + segment TITLE/ARTIST tags + cover attachment (Tags stay after clusters).
"${FF[@]}" "${COLOR[@]}" "${TONE[@]}" \
  -map 0:v -map 1:a -t 2 "${V264[@]}" "${A_AAC[@]}" \
  -metadata title="Fixture MKV Title" -metadata artist="Fixture MKV Artist" \
  -attach "$TMP/cover.jpg" -metadata:s:t mimetype=image/jpeg -metadata:s:t filename=cover.jpg \
  "$OUT/tagged-cover.mkv"

# Tagged MP3 (ID3v2.3 + APIC).
"${FF[@]}" "${TONE[@]}" -i "$TMP/cover.jpg" -map 0:a -map 1:v -t 2 \
  -c:a libmp3lame -b:a 32k -ac 1 -c:v copy -id3v2_version 3 \
  -metadata:s:v title="Cover" -metadata:s:v comment="Cover (front)" \
  -metadata title="Fixture MP3 Title" -metadata artist="Fixture MP3 Artist" \
  "$OUT/tagged-cover.mp3"

# Untagged M4A.
"${FF[@]}" "${TONE[@]}" -t 2 "${A_AAC[@]}" -map_metadata -1 -fflags +bitexact \
  -flags:a +bitexact -movflags +faststart "$OUT/untagged.m4a"

# Tagged FLAC.
"${FF[@]}" "${TONE[@]}" -t 2 -ac 1 -ar 16000 -c:a flac -compression_level 8 \
  -metadata TITLE="Fixture FLAC Title" -metadata ARTIST="Fixture FLAC Artist" \
  "$OUT/tagged.flac"

# Corrupt MP4: moov at the end (no faststart), truncated to ~40%.
"${FF[@]}" "${COLOR[@]}" -t 2 "${V264[@]}" -an -movflags -faststart "$TMP/full.mp4"
SIZE="$(wc -c < "$TMP/full.mp4" | tr -d ' ')"
head -c "$((SIZE * 40 / 100))" "$TMP/full.mp4" > "$OUT/corrupt.mp4"

echo "Fixtures written to $OUT"
du -ck "$OUT"/* | tail -1
