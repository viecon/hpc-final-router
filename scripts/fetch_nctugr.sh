#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/external/nctu-gr"}
TAR=${TAR:-"$ROOT/external/NCTU-GR-20130701.tar"}
DOWNLOADER=${DOWNLOADER:-"$ROOT/scripts/download_file.sh"}
URL="https://people.cs.nycu.edu.tw/~whliu/NCTU-GR%2020130701.tar"

mkdir -p "$(dirname "$TAR")" "$OUT_DIR"

if [[ ! -s "$TAR" ]]; then
  echo "download $URL"
  bash "$DOWNLOADER" "$URL" "$TAR"
fi

if [[ ! -x "$OUT_DIR/NCTUgr" ]]; then
  tar -xf "$TAR" -C "$OUT_DIR"
  chmod +x "$OUT_DIR/NCTUgr"
fi

echo "NCTU-GR ready in $OUT_DIR"
