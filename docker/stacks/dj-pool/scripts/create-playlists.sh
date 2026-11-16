#!/usr/bin/env bash
# Generate per-folder .m3u playlists under the music library (mounted at /music).
set -euo pipefail

ROOTDIR=/music
cd "$ROOTDIR"

readarray -t FOLDERS < <(find . -mindepth 1 -maxdepth 5 -type d)

for DIR in "${FOLDERS[@]}"; do
  cd "$ROOTDIR/$DIR"
  PLAYLIST="folder: $(basename "$(dirname "$DIR")") - $(basename "$DIR").m3u"

  if [[ $(ls 2>/dev/null | grep -E '\.(mp3|wav|flac|aiff)$' | wc -l) -gt 0 ]]; then
    echo "$PLAYLIST"
    ls -t 2>/dev/null | grep -E '\.(mp3|wav|flac|aiff)$' > "$PLAYLIST"
  fi
done
