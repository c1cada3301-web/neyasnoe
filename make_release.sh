#!/usr/bin/env bash
# Собирает архивы для GitHub Releases: dist/neyasnoe-coop-<версия>-windows.zip и -macos.zip.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:?укажите версию, например 0.3}"
DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
for os in windows macos; do
  dir="$DIST/neyasnoe-coop-$VERSION-$os"
  mkdir -p "$dir/coop_mod"
  cp "$ROOT"/mod/*.gd "$dir/coop_mod/"
  cp "$ROOT"/install/$os/* "$dir/"
  # без верхней папки: под Windows архив распаковывают прямо в папку игры
  (cd "$dir" && zip -qr "$DIST/neyasnoe-coop-$VERSION-$os.zip" .)
done
ls -1 "$DIST"/*.zip
