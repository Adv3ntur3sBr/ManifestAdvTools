#!/usr/bin/env bash
# ==============================================================================
#  ManifestAdvTools — Instalador Automatizado para Linux & SteamOS (Steam Deck)
#  Uso: curl -fsSL "https://raw.githubusercontent.com/Adv3ntur3sBr/ManifestAdvTools/main/install.sh" | bash
# ==============================================================================
set -u

REPO="Adv3ntur3sBr/ManifestAdvTools"
PLUGIN_NAME="ManifestAdvTools"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

step()    { printf "\n${CYAN}➜ %s${NC}\n" "$1"; }
success() { printf "${GREEN}✔ %s${NC}\n" "$1"; }
warn()    { printf "${YELLOW}⚠ %s${NC}\n" "$1"; }
fail()    { printf "${RED}✖ %s${NC}\n" "$1"; exit 1; }

printf "${MAGENTA}=========================================================${NC}\n"
printf "${BOLD}     MANIFESTADVTOOLS — INSTALADOR LINUX / STEAMOS       ${NC}\n"
printf "${MAGENTA}=========================================================${NC}\n"

# 1. Verificar dependências básicas
step "Verificando ferramentas necessárias (curl, unzip/tar)..."
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    fail "curl ou wget não encontrado. Instale o pacote 'curl' na sua distribuição."
fi
if ! command -v unzip >/dev/null 2>&1 && ! command -v tar >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    fail "unzip, tar ou python3 não encontrado. Instale o pacote 'unzip' na sua distribuição."
fi
success "Ferramentas básicas verificadas."

# 2. Detectar diretório da Steam no Linux / Steam Deck
step "Detectando instalação da Steam..."
STEAM_PATH=""
CANDIDATES=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

for cand in "${CANDIDATES[@]}"; do
    if [ -d "$cand/steamapps" ] || [ -d "$cand/config" ] || [ -f "$cand/steam.sh" ]; then
        STEAM_PATH="$(cd "$cand" 2>/dev/null && pwd -P || echo "$cand")"
        break
    fi
done

if [ -z "$STEAM_PATH" ]; then
    warn "Não foi possível detectar a pasta da Steam nos caminhos padrões."
    printf "Digite o caminho completo da sua pasta Steam (ex: %s/.local/share/Steam): " "$HOME"
    read -r USER_STEAM_PATH </dev/tty || true
    if [ -n "${USER_STEAM_PATH:-}" ] && [ -d "$USER_STEAM_PATH" ]; then
        STEAM_PATH="$USER_STEAM_PATH"
    else
        fail "Caminho da Steam inválido. Instalação cancelada."
    fi
fi
success "Steam detectada em: $STEAM_PATH"

# 3. Encerrar processos da Steam se estiverem em execução
if pgrep -x "steam" >/dev/null 2>&1; then
    step "Encerrando a Steam para aplicar a instalação..."
    pkill -x "steam" 2>/dev/null || killall steam 2>/dev/null || true
    sleep 2
    pkill -9 -x "steam" 2>/dev/null || true
    success "Steam encerrada."
fi

# 4. Verificar / Instalar Millennium (SteamBrew) para Linux
step "Verificando instalação do Millennium (SteamBrew)..."
MILLENNIUM_XDG="$HOME/.local/share/millennium"
MILLENNIUM_STEAM="$STEAM_PATH/millennium"

if [ ! -d "$MILLENNIUM_XDG" ] && [ ! -d "$MILLENNIUM_STEAM" ] && ! command -v millennium >/dev/null 2>&1; then
    warn "Millennium não encontrado. Instalando Millennium para Linux automaticamente..."
    if command -v curl >/dev/null 2>&1; then
        sh -c "$(curl -fsSL https://steambrew.app/install.sh)" || warn "Instalador oficial do Millennium retornou aviso. Continuando configuração do plugin..."
    elif command -v wget >/dev/null 2>&1; then
        sh -c "$(wget -qO- https://steambrew.app/install.sh)" || warn "Instalador oficial do Millennium retornou aviso. Continuando configuração do plugin..."
    fi
else
    success "Millennium já está presente no sistema."
fi

# 5. Baixar pacote mais recente do ManifestAdvTools
step "Baixando versão mais recente do ManifestAdvTools..."
TMP_ZIP="/tmp/ManifestAdvTools-$$.zip"
rm -f "$TMP_ZIP" 2>/dev/null || true

MAIN_ZIP_URL="https://raw.githubusercontent.com/${REPO}/main/ManifestAdvTools.zip?t=$(date +%s)"
REL_ZIP_URL="https://github.com/${REPO}/releases/latest/download/ManifestAdvTools.zip"

download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -A "ManifestAdvTools-Linux-Installer" "$url" -o "$dest" 2>/dev/null && [ -s "$dest" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -U "ManifestAdvTools-Linux-Installer" "$url" -O "$dest" 2>/dev/null && [ -s "$dest" ] && return 0
    fi
    return 1
}

if download_file "$MAIN_ZIP_URL" "$TMP_ZIP"; then
    success "Pacote baixado da branch principal (main)!"
elif download_file "$REL_ZIP_URL" "$TMP_ZIP"; then
    success "Pacote baixado da última release!"
else
    fail "Não foi possível baixar o pacote ManifestAdvTools.zip do GitHub."
fi

# 6. Extrair o plugin nos diretórios do Millennium
step "Instalando plugin ManifestAdvTools..."
TARGET_STEAM_PLUGIN="$STEAM_PATH/millennium/plugins/$PLUGIN_NAME"
TARGET_XDG_PLUGIN="$MILLENNIUM_XDG/plugins/$PLUGIN_NAME"

extract_zip() {
    local zip_file="$1"
    local dest_dir="$2"
    rm -rf "$dest_dir" 2>/dev/null || true
    mkdir -p "$dest_dir"
    if command -v unzip >/dev/null 2>&1; then
        unzip -o -q "$zip_file" -d "$dest_dir" && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$zip_file" "$dest_dir" && return 0
    fi
    if command -v tar >/dev/null 2>&1; then
        tar -xf "$zip_file" -C "$dest_dir" && return 0
    fi
    return 1
}

if ! extract_zip "$TMP_ZIP" "$TARGET_STEAM_PLUGIN"; then
    rm -f "$TMP_ZIP" 2>/dev/null || true
    fail "Falha ao extrair o pacote em $TARGET_STEAM_PLUGIN"
fi

# Se a pasta XDG do Millennium existir ou for usada no Linux, sincroniza lá também
mkdir -p "$MILLENNIUM_XDG/plugins"
if [ "$TARGET_STEAM_PLUGIN" != "$TARGET_XDG_PLUGIN" ]; then
    rm -rf "$TARGET_XDG_PLUGIN" 2>/dev/null || true
    cp -rf "$TARGET_STEAM_PLUGIN" "$TARGET_XDG_PLUGIN"
fi

rm -f "$TMP_ZIP" 2>/dev/null || true

# Ajustar permissões dos scripts Linux
chmod +x "$TARGET_STEAM_PLUGIN/backend/scripts/downloader.sh" 2>/dev/null || true
chmod +x "$TARGET_XDG_PLUGIN/backend/scripts/downloader.sh" 2>/dev/null || true

# Garantir pastas de manifesto e cache na Steam
mkdir -p "$STEAM_PATH/config/stplug-in"
mkdir -p "$STEAM_PATH/depotcache"
mkdir -p "$STEAM_PATH/steamui/webkit"

if [ -f "$TARGET_STEAM_PLUGIN/.millennium/Dist/webkit.js" ]; then
    cp -f "$TARGET_STEAM_PLUGIN/.millennium/Dist/webkit.js" "$STEAM_PATH/steamui/webkit/manifestadvtools.js" 2>/dev/null || true
fi

# 7. Ativar o plugin nas configurações do Millennium
step "Ativando ManifestAdvTools no Millennium..."
for cfg_dir in "$STEAM_PATH/ext" "$MILLENNIUM_XDG" "$HOME/.config/millennium"; do
    cfg_json="$cfg_dir/config.json"
    if [ -f "$cfg_json" ] && command -v python3 >/dev/null 2>&1; then
        python3 - "$cfg_json" << 'PYEOF' 2>/dev/null || true
import sys, json
p = sys.argv[1]
try:
    data = json.load(open(p, "r", encoding="utf-8"))
except Exception:
    data = {}
plugins = data.get("plugins")
if isinstance(plugins, list):
    if "ManifestAdvTools" not in plugins:
        plugins.append("ManifestAdvTools")
elif isinstance(plugins, dict):
    plugins["ManifestAdvTools"] = True
else:
    data["plugins"] = ["ManifestAdvTools"]
json.dump(data, open(p, "w", encoding="utf-8"), indent=2)
PYEOF
    fi
done

success "ManifestAdvTools instalado em: $TARGET_STEAM_PLUGIN"

# 8. Iniciar a Steam em segundo plano
step "Iniciando a Steam..."
if command -v steam >/dev/null 2>&1; then
    nohup steam >/dev/null 2>&1 &
    success "Steam iniciada em segundo plano!"
elif [ -x "$STEAM_PATH/steam.sh" ]; then
    nohup "$STEAM_PATH/steam.sh" >/dev/null 2>&1 &
    success "Steam iniciada via steam.sh!"
else
    warn "Abra a Steam manualmente pelo menu do seu sistema."
fi

printf "\n${GREEN}=========================================================${NC}\n"
printf "${BOLD}  🎉 MANIFESTADVTOOLS INSTALADO COM SUCESSO NO LINUX!    ${NC}\n"
printf "${GREEN}=========================================================${NC}\n\n"
