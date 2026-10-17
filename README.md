# ⚡ ManifestAdvTools

**ManifestAdvTools** é um gerenciador moderno, ágil e visualmente aprimorado de manifestos, jogos e OnlineFixes para o cliente **Steam**, funcionando nativamente através do framework **[Millennium](https://steambrew.app/)**.

---

## 🚀 Instalação Rápida (1-Click)

Abra o **PowerShell** no Windows e execute o comando abaixo:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Adv3ntur3sBr/ManifestAdvTools/main/install.ps1 | iex"
```

> 💡 **O que o instalador faz:**
> 1. Localiza sua pasta do Steam automaticamente pelo Registro do Windows.
> 2. Verifica se o Millennium está presente. Caso não esteja, realiza o download e a instalação de forma silenciosa.
> 3. Baixa e instala a versão mais recente do **ManifestAdvTools**.
> 4. Reinicia a Steam com o plugin 100% pronto para uso.

---

## 🗑️ Desinstalação Completa (1-Click)

Para remover **100% de qualquer modificação** (Millennium, Steamtools, ManifestAdvTools e scripts Lua) e restaurar sua Steam para o estado original de fábrica:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Adv3ntur3sBr/ManifestAdvTools/main/uninstall.ps1 | iex"
```

> 🛡️ **Garantia de Segurança:** Seus jogos já instalados, bibliotecas e conta da Steam permanecem 100% intactos. Apenas os arquivos injetados (`dwmapi.dll`, `xinput1_4.dll`, `wsock32.dll`, pasta `millennium/` e scripts `stplug-in`) são removidos.

---

## 🌟 Principais Recursos

- **🌐 6 Fontes Públicas Integradas**: Raian Manifests, Sushi, GOG Pirate Repo, LuaDepot Games, Angel Manifest e Morrenus.
- **🔧 Suporte Completo a OnlineFix**: Download e extração automatizados de patches e bypasses multiplayer diretamente da Steam.
- **🎨 Sistema Dinâmico de Temas**: 11 temas visuais modernos (Original, Catppuccin, Dracula, Gruvbox, Cyberpunk, Ocean e mais) com paletas adaptativas.
- **🗂️ Configurações em Abas**: Interface organizada com abas para Geral, APIs, Fixes, LUAs e Diagnóstico/Sobre.
- **🎮 Gamepad & Steam Deck**: Compatibilidade nativa com controles, navegação visual e atalhos em modo Big Picture.
- **🔄 Auto-Update Integrado**: Verificação periódica e atualização automática de releases diretamente pelo repositório GitHub.

---

## 🌐 Deploy no Vercel

Este repositório está pronto para deploy instantâneo no **[Vercel](https://vercel.com/)**:
1. Conecte o repositório `ManifestAdvTools` no Vercel.
2. Defina o Root Directory como `./` (ou a pasta do projeto).
3. O arquivo `vercel.json` cuidará de todas as rotas estáticas e headers CORS automaticamente.

---

## 📄 Licença
Distribuído sob licença livre para a comunidade de modding Steam.
