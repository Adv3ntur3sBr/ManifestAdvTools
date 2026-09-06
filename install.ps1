<#
    .SYNOPSIS
    Instalador Oficial Automatizado do ManifestAdvTools para Steam
    .DESCRIPTION
    Instalação direta: Steamtools + Millennium v3 + ManifestAdvTools
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
    Write-Host "OK " -ForegroundColor Green -NoNewline
    Write-Host $Msg -ForegroundColor White
}

function Write-Err {
    param([string]$Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
    Write-Host "ERRO: " -ForegroundColor Red -NoNewline
    Write-Host $Msg -ForegroundColor Red
}

Clear-Host
Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host "       MANIFESTADVTOOLS - INSTALADOR AUTOMATIZADO        " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Magenta

# 1. Localizar pasta do Steam
Write-Step "Localizando diretório do Steam..."
$SteamPath = $null
try {
    $SteamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
} catch {}

if (-not $SteamPath -or -not (Test-Path $SteamPath)) {
    try {
        $SteamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    } catch {}
}

if (-not $SteamPath -or -not (Test-Path $SteamPath)) {
    if (Test-Path "C:\Program Files (x86)\Steam") {
        $SteamPath = "C:\Program Files (x86)\Steam"
    } elseif (Test-Path "C:\Steam") {
        $SteamPath = "C:\Steam"
    }
}

if (-not $SteamPath -or -not (Test-Path $SteamPath)) {
    Write-Err "Steam não encontrada no registro nem nos diretórios padrão."
    exit 1
}

$SteamPath = $SteamPath.Replace('/', '\')
Write-Success "Steam detectada em: $SteamPath"

# 2. Encerrar processos da Steam
Write-Step "Encerrando processos da Steam para aplicar os arquivos..."
while (Get-Process -Name "steam", "steamwebhelper", "millennium*" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "steam", "steamwebhelper", "millennium*" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
Write-Success "Processos da Steam encerrados."

# 3. Instalar Steamtools
Write-Step "Verificando Steamtools (desbloqueador de manifestos)..."
$SteamtoolsUrl = "https://github.com/madoiscool/lt_api_links/releases/download/ost-148/ost.zip"
$SteamtoolsZip = Join-Path $SteamPath "steamtools_temp.zip"

Write-Step "Baixando Steamtools..."
Invoke-WebRequest -Uri $SteamtoolsUrl -OutFile $SteamtoolsZip -TimeoutSec 60
Write-Step "Extraindo Steamtools em $SteamPath..."
Expand-Archive -Path $SteamtoolsZip -DestinationPath $SteamPath -Force
Remove-Item $SteamtoolsZip -Force -ErrorAction SilentlyContinue
Write-Success "Steamtools instalado com sucesso!"

# 4. Instalar Millennium v3
Write-Step "Instalando Millennium v3..."
$MillenniumUrl = "https://github.com/SteamClientHomebrew/Millennium/releases/download/v3.4.1/millennium-v3.4.1-windows-x86_64.zip"
$MillenniumZip = Join-Path $SteamPath "millennium_temp.zip"

Write-Step "Baixando Millennium v3..."
Invoke-WebRequest -Uri $MillenniumUrl -OutFile $MillenniumZip -TimeoutSec 60
Write-Step "Extraindo Millennium v3 em $SteamPath..."
Expand-Archive -Path $MillenniumZip -DestinationPath $SteamPath -Force
Remove-Item $MillenniumZip -Force -ErrorAction SilentlyContinue
Write-Success "Millennium v3 instalado com sucesso!"

# 5. Baixar e configurar ManifestAdvTools
$PluginsDir = Join-Path $SteamPath "millennium\plugins"
if (-not (Test-Path $PluginsDir)) {
    New-Item -Path $PluginsDir -ItemType Directory -Force | Out-Null
}

$PluginTargetDir = Join-Path $PluginsDir "ManifestAdvTools"
if (-not (Test-Path $PluginTargetDir)) {
    New-Item -Path $PluginTargetDir -ItemType Directory -Force | Out-Null
}

Write-Step "Baixando o plugin ManifestAdvTools..."
$PluginUrl = "https://github.com/l89699756-design/ManifestAdvTools/releases/download/v8.1.0/ManifestAdvTools.zip"
$PluginZip = Join-Path $SteamPath "ManifestAdvTools_temp.zip"

Write-Step "Baixando ManifestAdvTools..."
Invoke-WebRequest -Uri $PluginUrl -OutFile $PluginZip -TimeoutSec 60
Write-Step "Extraindo ManifestAdvTools em $PluginTargetDir..."
Expand-Archive -Path $PluginZip -DestinationPath $PluginTargetDir -Force
Remove-Item $PluginZip -Force -ErrorAction SilentlyContinue
Write-Success "ManifestAdvTools instalado com sucesso!"

# 6. Otimizar Millennium Config (evita travamento de rede no boot)
$MillConfigDir = Join-Path $SteamPath "millennium\config"
if (-not (Test-Path $MillConfigDir)) {
    New-Item -Path $MillConfigDir -ItemType Directory -Force | Out-Null
}
$MillConfigFile = Join-Path $MillConfigDir "config.json"

$ConfigObj = [PSCustomObject]@{
    general = [PSCustomObject]@{
        checkForMillenniumUpdates = $false
        checkForPluginAndThemeUpdates = $false
        injectJavascript = $true
        injectCSS = $true
        accentColor = "DEFAULT_ACCENT_COLOR"
        millenniumUpdateChannel = "stable"
    }
    plugins = [PSCustomObject]@{
        enabledPlugins = @("ManifestAdvTools")
    }
    themes = [PSCustomObject]@{
        activeTheme = "default"
        allowedScripts = $true
        allowedStyles = $true
    }
}

$ConfigObj | ConvertTo-Json -Depth 10 | Set-Content -Path $MillConfigFile -Encoding UTF8
Write-Success "Configurações otimizadas salvas em: $MillConfigFile"

# 7. Limpar flags de Beta e Cfg da Steam
Write-Step "Otimizando parâmetros de inicialização..."
$BetaFolder = Join-Path $SteamPath "package\beta"
if (Test-Path $BetaFolder) {
    Remove-Item $BetaFolder -Recurse -Force -ErrorAction SilentlyContinue
}

$SteamCfg = Join-Path $SteamPath "steam.cfg"
if (Test-Path $SteamCfg) {
    Remove-Item $SteamCfg -Force -ErrorAction SilentlyContinue
}

# 8. Iniciar Steam
Write-Step "Iniciando a Steam..."
$SteamExe = Join-Path $SteamPath "steam.exe"
Start-Process -FilePath $SteamExe

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "    🎉 INSTALAÇÃO E ATIVAÇÃO CONCLUÍDAS COM SUCESSO!     " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "A Steam está sendo iniciada com o Millennium e o ManifestAdvTools." -ForegroundColor Cyan
Write-Host "Aguarde alguns instantes para a interface carregar completamente!`n" -ForegroundColor Gray
