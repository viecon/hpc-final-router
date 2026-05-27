#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 URL OUTPUT" >&2
  exit 2
fi

url=$1
out=$2
tmp="${out}.tmp"

rm -f "$tmp"

if command -v curl >/dev/null 2>&1; then
  curl -L --retry 3 "$url" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
  wget --tries=3 --timeout=30 -O "$tmp" "$url"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$url" "$tmp" <<'PY'
import sys
import urllib.request

url, out = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url) as response, open(out, "wb") as f:
    f.write(response.read())
PY
else
  echo "missing downloader: install curl or wget, or provide python3" >&2
  exit 127
fi

mv "$tmp" "$out"
