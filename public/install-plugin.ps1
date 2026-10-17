<#
    .SYNOPSIS
    Instalador Oficial Automatizado do ManifestAdvTools para Steam
    .DESCRIPTION
    Instalação direta, limpa e estável: Steamtools + Millennium v3 + ManifestAdvTools
    Sem congelamentos de inicialização, com suporte completo a Steam x64.
#>

$ErrorActionPreference = "Stop"
$Script:ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$null = chcp 65001

function Write-Step {
    param([string]$Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
    Write-Host ">> $Msg" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
    Write-Host "OK $Msg" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
    Write-Host "WARN $Msg" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
    Write-Host "ERR $Msg" -ForegroundColor Red
}

function Download-And-Extract {
    param(
        [string[]]$Urls,
        [string]$DestFolder,
        [string]$Name
    )

    $tempZip = Join-Path $env:TEMP "$Name-temp.zip"
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ManifestAdvTools")

    $downloaded = $false
    foreach ($url in $Urls) {
        try {
            Write-Step "Baixando $Name ($url)..."
            $wc.DownloadFile($url, $tempZip)
            if ((Test-Path $tempZip) -and ((Get-Item $tempZip).Length -gt 1000)) {
                $downloaded = $true
                break
            }
        } catch {
            Write-Warn "Falha ao baixar de $($url): $($_). Tentando próxima fonte..."
        }
    }

    if (-not $downloaded) {
        throw "Não foi possível baixar $Name de nenhuma fonte disponível."
    }

    Write-Step "Extraindo $Name em $DestFolder..."
    if (-not (Test-Path $DestFolder)) {
        New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null
    }

    Expand-Archive -Path $tempZip -DestinationPath $DestFolder -Force
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Write-Success "$Name instalado com sucesso!"
}

Clear-Host
Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host "       MANIFESTADVTOOLS — INSTALADOR AUTOMATIZADO        " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Magenta

# 1. Localizar Steam
Write-Step "Localizando diretório do Steam..."
$SteamPath = $null

$registries = @(
    "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
    "HKLM:\SOFTWARE\Valve\Steam",
    "HKCU:\SOFTWARE\Valve\Steam"
)

foreach ($reg in $registries) {
    if (Test-Path $reg) {
        $val = (Get-ItemProperty -Path $reg -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
        if (-not $val) {
            $val = (Get-ItemProperty -Path $reg -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
        }
        if ($val -and (Test-Path $val) -and (Test-Path (Join-Path $val "steam.exe"))) {
            $SteamPath = $val
            break
        }
    }
}

if (-not $SteamPath) {
    if (Test-Path "C:\Program Files (x86)\Steam\steam.exe") {
        $SteamPath = "C:\Program Files (x86)\Steam"
    } elseif (Test-Path "C:\Steam\steam.exe") {
        $SteamPath = "C:\Steam"
    }
}

if (-not $SteamPath) {
    Write-Fail "Steam não encontrada no registro."
    $SteamPath = Read-Host "Digite o caminho completo da sua pasta da Steam (ex: C:\Program Files (x86)\Steam)"
    if (-not (Test-Path (Join-Path $SteamPath "steam.exe"))) {
        Write-Fail "Caminho inválido ou steam.exe ausente. Abortando."
        exit 1
    }
}

$SteamPath = $SteamPath.Replace('/', '\')
Write-Success "Steam detectada em: $SteamPath"

# 2. Finalizar Steam
Write-Step "Encerrando processos da Steam para aplicar os arquivos com segurança..."
while (Get-Process -Name "steam", "steamwebhelper", "millennium*" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "steam", "steamwebhelper", "millennium*" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
Write-Success "Processos da Steam e módulos finalizados."

# Limpar travas residuais de sockets
if ($env:TEMP -and (Test-Path $env:TEMP)) {
    Get-ChildItem -Path $env:TEMP -Filter "*millennium*.sock" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 3. Instalar Steamtools (OpenSteamTool)
Write-Step "Verificando Steamtools (desbloqueador de manifestos)..."
$OstUrls = @(
    "https://github.com/madoiscool/lt_api_links/releases/download/ost-148/ost.zip",
    "https://github.com/Adv3ntur3sBr/ManifestAdvTools/raw/main/steamtools.zip"
)
try {
    Download-And-Extract -Urls $OstUrls -DestFolder $SteamPath -Name "Steamtools"
} catch {
    Write-Warn "Aviso ao instalar Steamtools: $_. Continuando..."
}

# 4. Instalar Millennium v3
Write-Step "Instalando Millennium v3..."
$MillenniumUrls = @(
    "https://github.com/SteamClientHomebrew/Millennium/releases/download/v3.4.1/millennium-v3.4.1-windows-x86_64.zip",
    "https://github.com/Adv3ntur3sBr/ManifestAdvTools/raw/main/millennium.zip"
)
try {
    Download-And-Extract -Urls $MillenniumUrls -DestFolder $SteamPath -Name "Millennium v3"
} catch {
    Write-Fail "Erro crítico ao baixar Millennium: $_"
    exit 1
}

# 5. Instalar o Plugin ManifestAdvTools (SEM duplicar diretórios para não travar a Steam)
Write-Step "Instalando plugin ManifestAdvTools..."
$PluginsRoot = Join-Path $SteamPath "millennium\plugins"
$DestPlugin = Join-Path $PluginsRoot "ManifestAdvTools"
$LegacyPlugin = Join-Path $PluginsRoot "luatools"

# Remover pasta legada 'luatools' que causa conflito de registro e trava a inicialização
if (Test-Path $LegacyPlugin) {
    Write-Step "Removendo pasta legada 'luatools' para garantir estabilidade..."
    Remove-Item -Path $LegacyPlugin -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $DestPlugin) {
    Remove-Item -Path $DestPlugin -Recurse -Force -ErrorAction SilentlyContinue
}

$PluginUrls = @(
    "https://github.com/Adv3ntur3sBr/ManifestAdvTools/releases/latest/download/ManifestAdvTools.zip",
    "https://github.com/Adv3ntur3sBr/ManifestAdvTools/raw/main/ManifestAdvTools.zip"
)

try {
    Download-And-Extract -Urls $PluginUrls -DestFolder $DestPlugin -Name "ManifestAdvTools"
} catch {
    Write-Fail "Falha ao baixar plugin: $_"
    exit 1
}

# 6. Ativar ManifestAdvTools nas configurações do Millennium (preservando todas as configurações)
Write-Step "Configurando Millennium de forma segura..."
$MillConfigDir = Join-Path $SteamPath "millennium\config"
if (-not (Test-Path $MillConfigDir)) {
    New-Item -Path $MillConfigDir -ItemType Directory -Force | Out-Null
}

$MillConfigFile = Join-Path $MillConfigDir "config.json"
$ConfigObj = $null

if (Test-Path $MillConfigFile) {
    try {
        $ConfigObj = Get-Content -Path $MillConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {}
}

if (-not $ConfigObj) {
    $ConfigObj = [PSCustomObject]@{
        general = [PSCustomObject]@{
            accentColor = "DEFAULT_ACCENT_COLOR"
            checkForMillenniumUpdates = $false
            checkForPluginAndThemeUpdates = $false
            injectCSS = $true
            injectJavascript = $true
            millenniumUpdateChannel = "stable"
            onMillenniumUpdate = 2
            shouldShowThemePluginUpdateNotifications = $false
        }
        misc = [PSCustomObject]@{
            hasShownWelcomeModal = $true
        }
        network = [PSCustomObject]@{
            proxy = ""
            proxyPassword = ""
            proxyUsername = ""
        }
        notifications = [PSCustomObject]@{
            showNotifications = $true
            showPluginNotifications = $true
            showUpdateNotifications = $false
        }
        themes = [PSCustomObject]@{
            activeTheme = "default"
            allowedScripts = $true
            allowedStyles = $true
        }
    }
}

if (-not $ConfigObj.plugins) {
    $ConfigObj | Add-Member -MemberType NoteProperty -Name "plugins" -Value ([PSCustomObject]@{ enabledPlugins = @() }) -Force
}

$activeList = [System.Collections.Generic.List[string]]::new()
if ($ConfigObj.plugins.enabledPlugins) {
    foreach ($p in $ConfigObj.plugins.enabledPlugins) {
        if ($p -and $p -ne "luatools" -and (-not $activeList.Contains($p))) {
            $activeList.Add($p)
        }
    }
}
if (-not $activeList.Contains("ManifestAdvTools")) {
    $activeList.Add("ManifestAdvTools")
}

$ConfigObj.plugins.enabledPlugins = $activeList.ToArray()
$ConfigObj | ConvertTo-Json -Depth 10 | Set-Content -Path $MillConfigFile -Encoding UTF8
Write-Success "Plugin habilitado com sucesso em: $MillConfigFile"

# 7. Limpar flags de Beta e Offline do Steam
Write-Step "Otimizando parâmetros de inicialização..."
$BetaFolder = Join-Path $SteamPath "package\beta"
if (Test-Path $BetaFolder) {
    Remove-Item $BetaFolder -Recurse -Force -ErrorAction SilentlyContinue
}

$SteamCfg = Join-Path $SteamPath "steam.cfg"
if (Test-Path $SteamCfg) {
    Remove-Item $SteamCfg -Force -ErrorAction SilentlyContinue
}

# 8. Iniciar Steam com -clearbeta
Write-Step "Iniciando a Steam com o Millennium e ManifestAdvTools..."
$SteamExe = Join-Path $SteamPath "steam.exe"
Start-Process -FilePath $SteamExe -ArgumentList "-clearbeta"

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "    🎉 INSTALAÇÃO E ATIVAÇÃO CONCLUÍDAS COM SUCESSO!     " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "A Steam está sendo iniciada com o Millennium e o ManifestAdvTools." -ForegroundColor Cyan
Write-Host "Na primeira inicialização, aguarde alguns segundos para o carregamento completo!" -ForegroundColor Gray
Write-Host ""
