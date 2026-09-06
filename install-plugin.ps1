<#
    .SYNOPSIS
    Instalador Oficial Automatizado do ManifestAdvTools para Steam
    .DESCRIPTION
    Verifica a instalação da Steam, instala o Millennium (se necessário) e configura o ManifestAdvTools automaticamente.
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Message)
    Write-Host "`n🚀 $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "⚠️ $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

Clear-Host
Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host "           MANIFESTADVTOOLS - INSTALADOR STEAM           " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Magenta

# 1. Localizar Steam
Write-Step "Detectando pasta de instalação da Steam..."
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
    Write-Fail "Não foi possível encontrar a instalação da Steam automaticamente."
    $SteamPath = Read-Host "Por favor, digite o caminho completo da sua pasta da Steam"
    if (-not (Test-Path $SteamPath)) {
        Write-Fail "Caminho inválido. Instalação cancelada."
        exit 1
    }
}

$SteamPath = $SteamPath.Replace('/', '\')
Write-Success "Steam encontrada em: $SteamPath"

# 2. Fechar Steam se estiver rodando
$SteamProcesses = Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue
if ($SteamProcesses) {
    Write-Step "Finalizando processos da Steam para aplicar os arquivos..."
    Stop-Process -Name "steam", "steamwebhelper" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Success "Steam finalizada com sucesso."
}

# 3. Verificar / Instalar Millennium
Write-Step "Verificando instalação do Millennium..."
$MillenniumDll = Join-Path $SteamPath "millennium.dll"
$MillenniumFolder = Join-Path $SteamPath "millennium"

if (-not (Test-Path $MillenniumDll) -and -not (Test-Path $MillenniumFolder)) {
    Write-Warn "Millennium não encontrado. Instalando automaticamente o Millennium..."
    try {
        $installCmd = "iwr -useb 'https://steambrew.app/install.ps1' | iex"
        Invoke-Expression $installCmd
        Write-Success "Instalação do Millennium concluída!"
    } catch {
        Write-Warn "Falha ao instalar o Millennium automaticamente: $_"
        Write-Host "Tentando continuar com a cópia do plugin..." -ForegroundColor Yellow
    }
} else {
    Write-Success "Millennium já está instalado no sistema."
}

# 4. Baixar e Instalar o Plugin ManifestAdvTools
Write-Step "Baixando a versão mais recente do ManifestAdvTools..."
$PluginsDir = Join-Path $SteamPath "millennium\plugins"
if (-not (Test-Path $PluginsDir)) {
    New-Item -Path $PluginsDir -ItemType Directory -Force | Out-Null
}

$TargetPluginDir = Join-Path $PluginsDir "ManifestAdvTools"
$ZipUrl = "https://github.com/l89699756-design/ManifestAdvTools/releases/latest/download/ManifestAdvTools.zip"
$TempZip = Join-Path $env:TEMP "ManifestAdvTools.zip"

try {
    Write-Host "Baixando pacote do plugin..." -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "ManifestAdvTools-Installer")
    $wc.DownloadFile($ZipUrl, $TempZip)
    Write-Success "Download concluído!"
} catch {
    Write-Warn "Não foi possível baixar o release do GitHub via link direto. Tentando espelho alternativo..."
    $FallbackUrl = "https://raw.githubusercontent.com/l89699756-design/ManifestAdvTools/main/ManifestAdvTools.zip"
    try {
        $wc.DownloadFile($FallbackUrl, $TempZip)
        Write-Success "Download concluído via repositório!"
    } catch {
        Write-Fail "Falha ao baixar o arquivo ManifestAdvTools.zip: $_"
        exit 1
    }
}

Write-Step "Instalando plugin no diretório do Millennium..."
if (Test-Path $TargetPluginDir) {
    Remove-Item -Path $TargetPluginDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $TargetPluginDir -ItemType Directory -Force | Out-Null

Expand-Archive -Path $TempZip -DestinationPath $TargetPluginDir -Force
Remove-Item -Path $TempZip -Force -ErrorAction SilentlyContinue

Write-Success "ManifestAdvTools instalado em: $TargetPluginDir"

# 5. Reabrir Steam
Write-Step "Reiniciando a Steam..."
$SteamExe = Join-Path $SteamPath "steam.exe"
if (Test-Path $SteamExe) {
    Start-Process -FilePath $SteamExe
    Write-Success "Steam iniciada com sucesso!"
} else {
    Start-Process "steam://open/main"
}

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host "   🎉 INSTALAÇÃO DO MANIFESTADVTOOLS CONCLUÍDA COM SUCESSO! " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "Abra a Steam e aproveite as ferramentas do ManifestAdvTools!`n" -ForegroundColor Cyan
