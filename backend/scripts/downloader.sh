#!/usr/bin/env bash
# ManifestAdvTools - Linux / SteamOS (Steam Deck) background downloader & extractor
set -u

URL="${1:-}"
DEST_ZIP="${2:-}"
EXTRACT_DIR="${3:-}"
STATE_FILE="${4:-}"
LIST_FILE="${5:-}"
PID_FILE="${6:-}"
DEPOT_CACHE="${7:-}"
TARGET_LUA="${8:-}"
APPID_STR="${9:-}"

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
    local br="${3:-50}"
    local tb="${4:-100}"
    if [ -n "$err" ]; then
        local err_escaped
        err_escaped=$(printf '%s' "$err" | tr '\n\r' '  ' | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"status":"%s","error":"%s","bytesRead":%s,"totalBytes":%s}\n' "$status" "$err_escaped" "$br" "$tb" > "$STATE_FILE"
    else
        printf '{"status":"%s","bytesRead":%s,"totalBytes":%s}\n' "$status" "$br" "$tb" > "$STATE_FILE"
    fi
}

download_raw() {
    local target_url="$1"
    local out_file="$2"
    rm -f "$out_file" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 180 -A "ManifestAdvTools" "$target_url" -o "$out_file" 2>/dev/null && [ -s "$out_file" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 -U "ManifestAdvTools" "$target_url" -O "$out_file" 2>/dev/null && [ -s "$out_file" ] && return 0
    fi
    return 1
}

download_smart() {
    local target_url="$1"
    local out_file="$2"
    download_raw "$target_url" "$out_file" || return 1

    # Check if downloaded file is a Git LFS pointer
    local fsize
    fsize=$(wc -c < "$out_file" 2>/dev/null | tr -d ' ')
    if [ -n "$fsize" ] && [ "$fsize" -gt 0 ] && [ "$fsize" -lt 512 ]; then
        if head -n 1 "$out_file" 2>/dev/null | grep -q "^version https://git-lfs.github.com/spec/v1"; then
            if [[ "$target_url" =~ ^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(refs/heads/)?([^/]+)/(.+)$ ]]; then
                local owner="${BASH_REMATCH[1]}"
                local repo="${BASH_REMATCH[2]}"
                local branch="${BASH_REMATCH[4]}"
                local rpath="${BASH_REMATCH[5]}"
                local media_url="https://media.githubusercontent.com/media/${owner}/${repo}/${branch}/${rpath}"
                if ! download_raw "$media_url" "$out_file"; then
                    local raw_redir="https://github.com/${owner}/${repo}/raw/${branch}/${rpath}"
                    download_raw "$raw_redir" "$out_file" || true
                fi
            fi
        fi
    fi
    [ -s "$out_file" ]
}

set_state "downloading" "" 55 100

mkdir -p "$(dirname "$DEST_ZIP")"
mkdir -p "$EXTRACT_DIR"

if ! download_smart "$URL" "$DEST_ZIP"; then
    set_state "failed" "Falha ao baixar o arquivo da fonte selecionada" 0 100
    exit 1
fi

set_state "extracting" "" 85 100

ext_ok=0
magic_hex=$(head -c 4 "$DEST_ZIP" 2>/dev/null | od -An -tx1 | tr -d ' \n')

if [ "$magic_hex" = "504b0304" ] || [ "$magic_hex" = "504b0506" ]; then
    if command -v unzip >/dev/null 2>&1; then
        if [ -n "$LIST_FILE" ]; then
            unzip -Z1 "$DEST_ZIP" > "$LIST_FILE" 2>/dev/null || true
        fi
        if unzip -o -q "$DEST_ZIP" -d "$EXTRACT_DIR" 2>/dev/null; then
            ext_ok=1
        fi
    fi
    if [ "$ext_ok" -eq 0 ] && command -v python3 >/dev/null 2>&1; then
        if python3 -m zipfile -e "$DEST_ZIP" "$EXTRACT_DIR" 2>/dev/null; then
            ext_ok=1
        fi
    fi
fi

if [ "$ext_ok" -eq 0 ] && command -v tar >/dev/null 2>&1; then
    if tar -xf "$DEST_ZIP" -C "$EXTRACT_DIR" 2>/dev/null; then
        ext_ok=1
    fi
fi

if [ "$ext_ok" -eq 0 ]; then
    # Check if it is a raw .lua file
    if ! grep -qiE "<!doctype|<html" "$DEST_ZIP" 2>/dev/null && grep -qE "addappid\s*\(|setManifestid\s*\(" "$DEST_ZIP" 2>/dev/null; then
        lua_name="${APPID_STR:-manifest}.lua"
        cp -f "$DEST_ZIP" "$EXTRACT_DIR/$lua_name"
        [ -n "$LIST_FILE" ] && echo "$lua_name" > "$LIST_FILE"
        ext_ok=1
    fi
fi

if [ "$ext_ok" -eq 0 ]; then
    set_state "failed" "Formato de arquivo invalido retornado pela API" 0 100
    exit 1
fi

# Copy .manifest files and prepare target .lua if requested
if [ -n "$DEPOT_CACHE" ] || [ -n "$TARGET_LUA" ]; then
    if [ -n "$DEPOT_CACHE" ]; then
        mkdir -p "$DEPOT_CACHE"
        find "$EXTRACT_DIR" -type f -name "*.manifest" -exec cp -f {} "$DEPOT_CACHE/" \; 2>/dev/null || true
    fi
    if [ -n "$TARGET_LUA" ]; then
        mkdir -p "$(dirname "$TARGET_LUA")"
        chosen_lua=""
        if [ -n "$APPID_STR" ] && [ -f "$EXTRACT_DIR/${APPID_STR}.lua" ]; then
            chosen_lua="$EXTRACT_DIR/${APPID_STR}.lua"
        else
            chosen_lua=$(find "$EXTRACT_DIR" -type f -name "*.lua" | head -n 1)
        fi
        if [ -n "$chosen_lua" ] && [ -f "$chosen_lua" ]; then
            sed -E 's/^([[:space:]]*)(setManifestid\()/\1-- \2/' "$chosen_lua" > "$TARGET_LUA"
        fi

        # On Linux, also register depot decryption keys into Steam's config/config.vdf and SLSsteam if present
        if [ -f "$TARGET_LUA" ] && command -v python3 >/dev/null 2>&1; then
            STEAM_ROOT="$(dirname "$(dirname "$(dirname "$TARGET_LUA")")")"
            CONFIG_VDF="$STEAM_ROOT/config/config.vdf"
            python3 - "$TARGET_LUA" "$CONFIG_VDF" "$APPID_STR" << 'PYEOF' 2>/dev/null || true
import sys, os, re

lua_path, vdf_path, appid = sys.argv[1], sys.argv[2], sys.argv[3]
if not os.path.isfile(lua_path):
    sys.exit(0)

lua_text = open(lua_path, "r", encoding="utf-8", errors="ignore").read()
keys = re.findall(r'addappid\(\s*(\d+)\s*,\s*\d+\s*,\s*"([0-9a-fA-F]{64})"\s*\)', lua_text)

if keys and os.path.isfile(vdf_path):
    vdf_text = open(vdf_path, "r", encoding="utf-8", errors="ignore").read()
    modified = False
    for depot_id, key_hex in keys:
        if re.search(r'"' + re.escape(depot_id) + r'"\s*\{\s*"DecryptionKey"', vdf_text, re.IGNORECASE):
            continue
        m = re.search(r'("depots"\s*\{)', vdf_text, re.IGNORECASE)
        if m:
            entry = f'\n\t\t\t\t\t"{depot_id}"\n\t\t\t\t\t{{\n\t\t\t\t\t\t"DecryptionKey"\t\t"{key_hex}"\n\t\t\t\t\t}}'
            idx = m.end(1)
            vdf_text = vdf_text[:idx] + entry + vdf_text[idx:]
            modified = True
    if modified:
        open(vdf_path, "w", encoding="utf-8").write(vdf_text)

# Optional SLSsteam integration
for sls_cfg in [
    os.path.expanduser("~/.config/SLSsteam/config.yaml"),
    os.path.expanduser("~/.var/app/com.valvesoftware.Steam/.config/SLSsteam/config.yaml"),
]:
    if appid and os.path.isfile(sls_cfg):
        cfg_txt = open(sls_cfg, "r", encoding="utf-8", errors="ignore").read()
        if not re.search(r'^\s*-\s*' + re.escape(appid) + r'\s*$', cfg_txt, re.MULTILINE):
            m = re.search(r'(AdditionalApps:\s*\n)', cfg_txt)
            if m:
                idx = m.end(1)
                cfg_txt = cfg_txt[:idx] + f"  - {appid}\n" + cfg_txt[idx:]
                open(sls_cfg, "w", encoding="utf-8").write(cfg_txt)
PYEOF
        fi
    fi
fi

rm -f "$DEST_ZIP" 2>/dev/null || true
set_state "extracted" "" 100 100
