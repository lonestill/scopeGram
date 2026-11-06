#!/bin/sh
set -e

SOURCE_DIR="$1"
DEST_DIR="$2"

if [ ! -d "$SOURCE_DIR" ]; then
    if [ -d "$DEST_DIR" ] && [ "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
        echo "Header source missing, but destination already populated: $DEST_DIR (skipping sync)"
        exit 0
    fi
    echo "Missing header source: $SOURCE_DIR" >&2
    exit 1
fi
mkdir -p "$DEST_DIR"
rsync -rlc --delete --delete-excluded \
    --include='*/' --include='*.h' --exclude='*' "$SOURCE_DIR/" "$DEST_DIR/"
