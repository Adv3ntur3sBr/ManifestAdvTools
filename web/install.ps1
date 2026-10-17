<#
    .SYNOPSIS
    Instalador Oficial Automatizado do ManifestAdvTools para Steam
    .DESCRIPTION
    Instalação direta e infalível: Steamtools + Millennium v3 + ManifestAdvTools
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
        [string]$Url,
        [string]$DestFolder,
        [string]$Name
    )

    $tempZip = Join-Path $env:TEMP "$Name-temp.zip"
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }

    Write-Step "Baixando $Name..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ManifestAdvTools")
    $wc.DownloadFile($Url, $tempZip)

    if (-not (Test-Path $tempZip)) {
        throw "Falha ao baixar $Name ($Url)"
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
Write-Step "Encerrando processos da Steam para aplicar os arquivos..."
while (Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "steam", "steamwebhelper" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
Write-Success "Processos da Steam encerrados."

# 3. Instalar Steamtools (ost.zip -> dwmapi.dll e xinput1_4.dll)
Write-Step "Verificando Steamtools (desbloqueador de manifestos)..."
$OstUrl = "https://github.com/madoiscool/lt_api_links/releases/download/ost-148/ost.zip"
try {
    Download-And-Extract -Url $OstUrl -DestFolder $SteamPath -Name "Steamtools"
} catch {
    Write-Warn "Aviso ao instalar Steamtools: $_. Continuando..."
}

# 4. Instalar Millennium v3 diretamente (wsock32.dll + millennium/lib/millennium.dll)
Write-Step "Instalando Millennium v3..."
$MillenniumZipUrl = "https://github.com/SteamClientHomebrew/Millennium/releases/download/v3.4.1/millennium-v3.4.1-windows-x86_64.zip"

# Tentar resolver a versão mais recente via GitHub API
try {
    $ghResp = Invoke-RestMethod -Uri "https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest" -Headers @{ "User-Agent" = "ManifestAdvTools" } -TimeoutSec 10
    foreach ($asset in $ghResp.assets) {
        if ($asset.name -match "windows-x86_64\.zip$") {
            $MillenniumZipUrl = $asset.browser_download_url
            break
        }
    }
} catch {
    Write-Warn "Usando espelho de versão fixa do Millennium v3.4.1..."
}

try {
    Download-And-Extract -Url $MillenniumZipUrl -DestFolder $SteamPath -Name "Millennium v3"
} catch {
    Write-Fail "Erro crítico ao baixar Millennium: $_"
    exit 1
}

# 5. Instalar o Plugin ManifestAdvTools
Write-Step "Baixando o plugin ManifestAdvTools..."
$PluginZipUrl = "https://github.com/l89699756-design/ManifestAdvTools/releases/latest/download/ManifestAdvTools.zip"
$PluginsRoot = Join-Path $SteamPath "millennium\plugins"
$DestPlugin1 = Join-Path $PluginsRoot "ManifestAdvTools"
$DestPlugin2 = Join-Path $PluginsRoot "luatools"

try {
    Download-And-Extract -Url $PluginZipUrl -DestFolder $DestPlugin1 -Name "ManifestAdvTools"
    # Criar cópia com o nome 'luatools' para compatibilidade total com instalações existentes
    if (Test-Path $DestPlugin2) {
        Remove-Item $DestPlugin2 -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path $DestPlugin1 -Destination $DestPlugin2 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Fail "Falha ao baixar plugin: $_"
    exit 1
}

# 6. Ativar o Plugin no Millennium (config.json)
Write-Step "Habilitando ManifestAdvTools nas configurações do Millennium..."
$MillConfigDir = Join-Path $SteamPath "millennium\config"
if (-not (Test-Path $MillConfigDir)) {
    New-Item -Path $MillConfigDir -ItemType Directory -Force | Out-Null
}

$MillConfigFile = Join-Path $MillConfigDir "config.json"
$ConfigObj = @{
    plugins = @{
        enabledPlugins = @("ManifestAdvTools", "luatools")
    }
}

if (Test-Path $MillConfigFile) {
    try {
        $existing = Get-Content -Path $MillConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.plugins) {
            $list = @($existing.plugins.enabledPlugins)
            if ($list -notcontains "ManifestAdvTools") { $list += "ManifestAdvTools" }
            if ($list -notcontains "luatools") { $list += "luatools" }
            $existing.plugins.enabledPlugins = $list
            $ConfigObj = $existing
        }
    } catch {}
}

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
Write-Host "Na primeira inicialização, aguarde alguns segundos para o carregamento completo!`n" -ForegroundColor Gray
