#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/benchmarks/ispd08"}
DOWNLOADER=${DOWNLOADER:-"$ROOT/scripts/download_file.sh"}
mkdir -p "$OUT_DIR"

BASE07="https://www.ispd.cc/contests/07/rcontest/benchmark"
BASE08="https://www.ispd.cc/contests/08/benchmark"

urls=(
  "$BASE07/adaptec1.capo70.3d.35.50.90.gr.gz"
  "$BASE07/adaptec2.mpl60.3d.35.20.100.gr.gz"
  "$BASE07/adaptec3.dragon70.3d.30.50.90.gr.gz"
  "$BASE07/adaptec4.aplace60.3d.30.50.90.gr.gz"
  "$BASE07/adaptec5.mfar50.3d.50.20.100.gr.gz"
  "$BASE07/newblue1.ntup50.3d.30.50.90.gr.gz"
  "$BASE07/newblue2.fastplace90.3d.50.20.100.gr.gz"
  "$BASE07/newblue3.kraftwerk80.3d.40.50.90.gr.gz"
  "$BASE08/bigblue1.capo60.3d.50.10.100.gr.gz"
  "$BASE08/bigblue2.mpl60.3d.40.60.60.gr.gz"
  "$BASE08/bigblue3.aplace70.3d.50.10.90.m8.gr.gz"
  "$BASE08/bigblue4.fastplace70.3d.80.20.80.gr.gz"
  "$BASE08/newblue4.mpl50.3d.40.10.95.gr.gz"
  "$BASE08/newblue5.ntup50.3d.40.10.100.gr.gz"
  "$BASE08/newblue6.mfar80.3d.60.10.100.gr.gz"
  "$BASE08/newblue7.kraftwerk70.3d.80.20.82.m8.gr.gz"
)

for url in "${urls[@]}"; do
  gz="$OUT_DIR/$(basename "$url")"
  gr="${gz%.gz}"
  if [[ ! -s "$gr" ]]; then
    if [[ ! -s "$gz" ]]; then
      echo "download $url"
      bash "$DOWNLOADER" "$url" "$gz"
    fi
    echo "decompress $(basename "$gz")"
    gzip -dc "$gz" > "$gr"
  fi
done

echo "benchmarks ready in $OUT_DIR"
