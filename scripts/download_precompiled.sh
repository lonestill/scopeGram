#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TAG="${1:-precompiled-latest}"
REPO="${2:-lonestill/telegram-macos}"
URL="https://github.com/${REPO}/releases/download/${TAG}/precompiled-core-macos-arm64.tar.gz"

echo "==> Downloading precompiled frameworks from ${URL}..."
TMP_ARCHIVE="$(mktemp /tmp/precompiled-core-XXXXXX.tar.gz)"
trap 'rm -f "$TMP_ARCHIVE"' EXIT

if command -v gh >/dev/null 2>&1; then
    gh release download "$TAG" -R "$REPO" -p "precompiled-core-macos-arm64.tar.gz" -O "$TMP_ARCHIVE" 2>/dev/null || \
    curl -fL "$URL" -o "$TMP_ARCHIVE"
else
    curl -fL "$URL" -o "$TMP_ARCHIVE"
fi

echo "==> Extracting precompiled frameworks into $ROOT_DIR..."
tar -xzf "$TMP_ARCHIVE" -C "$ROOT_DIR"

echo "==> Done! Precompiled core frameworks successfully installed."
echo "==> You can now open Telegram-Mac.xcworkspace in Xcode and build directly."
