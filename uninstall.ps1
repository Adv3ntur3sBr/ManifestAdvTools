<#
    .SYNOPSIS
    Script Oficial de Desinstalacao Completa do ManifestAdvTools, Millennium e Steamtools
    .DESCRIPTION
    Remove completamente todas as modificacoes, DLLs injetadas, plugins e scripts,
    restaurando a Steam para o estado 100% original de fábrica sem afetar seus jogos ou conta.
#>

$ErrorActionPreference = "SilentlyContinue"
$Script:ProgressPreference = "SilentlyContinue"
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

function Write-Info {
    param([string]$Msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -ForegroundColor Cyan -NoNewline
    Write-Host "INFO: " -ForegroundColor Blue -NoNewline
    Write-Host $Msg -ForegroundColor Gray
}

Clear-Host
Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host "   MANIFESTADVTOOLS -- DESINSTALADOR COMPLETO DA STEAM   " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host "Restaurando a Steam para o padrao oficial e limpo...`n" -ForegroundColor Gray

# 1. Localizar Steam
Write-Step "Localizando instalacao da Steam..."
$SteamPath = $null

$registries = @(
    "HKCU:\Software\Valve\Steam",
    "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
    "HKLM:\SOFTWARE\Valve\Steam"
)

foreach ($reg in $registries) {
    if (Test-Path $reg) {
        $val = (Get-ItemProperty -Path $reg -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
        if (-not $val) {
            $val = (Get-ItemProperty -Path $reg -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
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
    Write-Host "ERRO: Pasta da Steam nao encontrada." -ForegroundColor Red
    $SteamPath = Read-Host "Digite o caminho completo da sua pasta da Steam (ex: C:\Program Files (x86)\Steam)"
    if (-not (Test-Path (Join-Path $SteamPath "steam.exe"))) {
        Write-Host "Caminho invalido. Operacao cancelada." -ForegroundColor Red
        exit 1
    }
}

$SteamPath = $SteamPath.Replace('/', '\')
Write-Success "Steam detectada em: $SteamPath"

# 2. Encerrar processos da Steam
Write-Step "Encerrando todos os processos da Steam e do Millennium..."
while (Get-Process -Name "steam", "steamwebhelper", "millennium*" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "steam", "steamwebhelper", "millennium*" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
Write-Success "Processos finalizados."

# 3. Remover DLLs injetadas da raiz da Steam (Steamtools e Millennium)
Write-Step "Removendo DLLs do Steamtools e Millennium da raiz da Steam..."
$DllsToRemove = @(
    (Join-Path $SteamPath "dwmapi.dll"),
    (Join-Path $SteamPath "xinput1_4.dll"),
    (Join-Path $SteamPath "wsock32.dll"),
    (Join-Path $SteamPath "version.dll")
)

foreach ($dll in $DllsToRemove) {
    if (Test-Path $dll) {
        Remove-Item -Path $dll -Force -ErrorAction SilentlyContinue
        Write-Info "Removido: $(Split-Path $dll -Leaf)"
    }
}
Write-Success "DLLs injetadas removidas."

# 4. Remover pastas do Millennium
Write-Step "Removendo pasta do Millennium e plugins..."
$MillenniumFolder = Join-Path $SteamPath "millennium"
if (Test-Path $MillenniumFolder) {
    Remove-Item -Path $MillenniumFolder -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "Pasta millennium/ removida."
}

# 5. Remover scripts de manifests (stplug-in)
Write-Step "Removendo scripts Lua de manifestos (stplug-in)..."
$StPluginFolder = Join-Path $SteamPath "config\stplug-in"
if (Test-Path $StPluginFolder) {
    Remove-Item -Path $StPluginFolder -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "Pasta config/stplug-in/ removida."
}

# 6. Remover arquivos injetados no Webkit da interface Steam
Write-Step "Limpando arquivos injetados na interface Web..."
$WebkitDir = Join-Path $SteamPath "steamui\webkit"
$WebkitFiles = @(
    (Join-Path $WebkitDir "manifestadvtools.js"),
    (Join-Path $WebkitDir "luatools.js"),
    (Join-Path $WebkitDir "steamdb-webkit.css")
)

foreach ($wf in $WebkitFiles) {
    if (Test-Path $wf) {
        Remove-Item -Path $wf -Force -ErrorAction SilentlyContinue
        Write-Info "Removido: $(Split-Path $wf -Leaf)"
    }
}

# 7. Limpar caches web corrompidos ou em memoria
Write-Step "Limpando caches de tela para restauracao 100% limpa..."
$CachePaths = @(
    (Join-Path $SteamPath "config\htmlcache"),
    (Join-Path $SteamPath "config\overlayhtmlcache"),
    (Join-Path $SteamPath "appcache\httpcache"),
    (Join-Path $SteamPath "package\beta"),
    (Join-Path $SteamPath "steam.cfg"),
    (Join-Path $SteamPath "dumps")
)

foreach ($cPath in $CachePaths) {
    if (Test-Path $cPath) {
        Remove-Item -Path $cPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Limpar sockets residuais no TEMP
$TempDir = $env:TEMP
if ($TempDir -and (Test-Path $TempDir)) {
    Get-ChildItem -Path $TempDir -Filter "*millennium*.sock" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $TempDir -Filter "*ManifestAdvTools*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Success "Caches limpos com sucesso!"

# 8. Reiniciar Steam limpa oficial
Write-Step "Iniciando a Steam no modo padrao oficial da Valve..."
$SteamExe = Join-Path $SteamPath "steam.exe"
if (Test-Path $SteamExe) {
    Start-Process -FilePath $SteamExe -ArgumentList "-clearbeta"
} else {
    Start-Process "steam://open/main"
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "    🎉 DESINSTALACAO E RESTAURACAO CONCLUIDAS!           " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "Todos os arquivos do ManifestAdvTools, Millennium e" -ForegroundColor Cyan
Write-Host "Steamtools foram completamente removidos da sua Steam." -ForegroundColor Cyan
Write-Host "Sua Steam agora esta 100% original e funcionando normalmente.`n" -ForegroundColor Gray
