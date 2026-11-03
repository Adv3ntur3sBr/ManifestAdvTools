#!/usr/bin/env bash
# ==============================================================================
#  ManifestAdvTools — Desinstalador para Linux & SteamOS (Steam Deck)
#  Uso: curl -fsSL "https://raw.githubusercontent.com/Adv3ntur3sBr/ManifestAdvTools/main/uninstall.sh" | bash
# ==============================================================================
set -u

PLUGIN_NAME="ManifestAdvTools"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

step()    { printf "\n${CYAN}➜ %s${NC}\n" "$1"; }
success() { printf "${GREEN}✔ %s${NC}\n" "$1"; }
warn()    { printf "${YELLOW}⚠ %s${NC}\n" "$1"; }

printf "${MAGENTA}=========================================================${NC}\n"
printf "${BOLD}   MANIFESTADVTOOLS — DESINSTALADOR LINUX / STEAMOS      ${NC}\n"
printf "${MAGENTA}=========================================================${NC}\n"

# 1. Encerrar processos da Steam
if pgrep -x "steam" >/dev/null 2>&1; then
    step "Encerrando a Steam..."
    pkill -x "steam" 2>/dev/null || killall steam 2>/dev/null || true
    sleep 2
    success "Steam encerrada."
fi

# 2. Remover diretórios do plugin
step "Removendo arquivos do ManifestAdvTools..."
CANDIDATES=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

for cand in "${CANDIDATES[@]}"; do
    if [ -d "$cand" ]; then
        rm -rf "$cand/millennium/plugins/$PLUGIN_NAME" 2>/dev/null || true
        rm -f "$cand/steamui/webkit/manifestadvtools.js" 2>/dev/null || true
        rm -f "$cand/steamui/webkit/luatools.js" 2>/dev/null || true
    fi
done

rm -rf "$HOME/.local/share/millennium/plugins/$PLUGIN_NAME" 2>/dev/null || true
success "Arquivos do plugin removidos com sucesso."

# 3. Reiniciar a Steam
step "Reiniciando a Steam..."
if command -v steam >/dev/null 2>&1; then
    nohup steam >/dev/null 2>&1 &
    success "Steam reiniciada!"
else
    warn "Abra a Steam manualmente pelo menu do seu sistema."
fi

printf "\n${GREEN}=========================================================${NC}\n"
printf "${BOLD}  ✔ MANIFESTADVTOOLS DESINSTALADO COM SUCESSO!          ${NC}\n"
printf "${GREEN}=========================================================${NC}\n\n"
