#!/usr/bin/env bash
# ManifestAdvTools - Linux / Steam Deck background downloader & extractor
set -euo pipefail

URL="$1"
DEST_ZIP="$2"
EXTRACT_DIR="$3"
STATE_FILE="$4"
LIST_FILE="${5:-}"
PID_FILE="${6:-}"

if [ -n "$PID_FILE" ]; then
    echo $$ > "$PID_FILE"
fi

cleanup() {
    if [ -n "$PID_FILE" ]; then
        rm -f "$PID_FILE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

set_state() {
    local status="$1"
    local err="${2:-}"
    if [ -n "$err" ]; then
        err_escaped=$(printf '%s' "$err" | sed 's/"/\\"/g')
        printf '{"status":"%s","error":"%s"}\n' "$status" "$err_escaped" > "$STATE_FILE"
    else
        printf '{"status":"%s"}\n' "$status" > "$STATE_FILE"
    fi
}

set_state "downloading"

mkdir -p "$(dirname "$DEST_ZIP")"
mkdir -p "$EXTRACT_DIR"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL -A "ManifestAdvTools" "$URL" -o "$DEST_ZIP" || {
        set_state "failed" "curl download failed"
        exit 1
    }
elif command -v wget >/dev/null 2>&1; then
    wget -q -U "ManifestAdvTools" "$URL" -O "$DEST_ZIP" || {
        set_state "failed" "wget download failed"
        exit 1
    }
else
    set_state "failed" "neither curl nor wget is available"
    exit 1
fi

set_state "extracting"

# Extract zip overwriting existing files
if command -v unzip >/dev/null 2>&1; then
    if [ -n "$LIST_FILE" ]; then
        unzip -Z1 "$DEST_ZIP" > "$LIST_FILE" 2>/dev/null || true
    fi
    unzip -o -q "$DEST_ZIP" -d "$EXTRACT_DIR" || {
        set_state "failed" "unzip failed"
        exit 1
    }
else
    set_state "failed" "unzip utility not found"
    exit 1
fi

rm -f "$DEST_ZIP" 2>/dev/null || true
set_state "extracted"
