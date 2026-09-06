<#
    .SYNOPSIS
    Script Oficial de Reparo e Reinicializacao Limpa da Steam
    .DESCRIPTION
    Restaura a Steam para o funcionamento padrao sem necessidade de reinstalacao.
    1. Localiza a Steam automaticamente.
    2. Encerra com seguranca todos os processos travados (steam.exe, steamwebhelper.exe, millennium*).
    3. Limpa caches web temporarios corrompidos (htmlcache, dumps, CEF cache).
    4. Garante que nenhum jogo ou credencial seja afetado.
    5. Reinicia a Steam de forma 100% limpa e confiavel.
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
Write-Host "=========================================================" -ForegroundColor Yellow
Write-Host "       MANIFESTADVTOOLS -- CENTRAL DE REPARO STEAM       " -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Yellow

# 1. Localizar Steam
Write-Step "Localizando instalacao da Steam..."
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

if (-not $SteamPath) {
    Write-Host "ERRO: Nao foi possivel localizar a pasta da Steam." -ForegroundColor Red
    exit 1
}

$SteamPath = $SteamPath.Replace('/', '\')
Write-Success "Steam detectada em: $SteamPath"

# 2. Encerrar processos em background
Write-Step "Encerrando com seguranca todos os processos travados da Steam..."
while (Get-Process -Name "steam", "steamwebhelper", "millennium*" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "steam", "steamwebhelper", "millennium*" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
Write-Success "Processos da Steam e Millennium finalizados."

# 3. Limpeza de caches temporarios corrompidos
Write-Step "Limpando caches temporarios da interface Web (jogos e conta 100% seguros)..."

$CachePaths = @(
    (Join-Path $SteamPath "config\htmlcache"),
    (Join-Path $SteamPath "config\overlayhtmlcache"),
    (Join-Path $SteamPath "appcache\httpcache"),
    (Join-Path $SteamPath "dumps")
)

foreach ($cPath in $CachePaths) {
    if (Test-Path $cPath) {
        try {
            Remove-Item -Path "$cPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "Cache limpo: $(Split-Path $cPath -Leaf)"
        } catch {}
    }
}
Write-Success "Caches temporarios corrompidos limpos com sucesso!"

# 4. Limpeza de sockets e travas temporarias
$TempDir = $env:TEMP
if ($TempDir -and (Test-Path $TempDir)) {
    Get-ChildItem -Path $TempDir -Filter "*millennium*.sock" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 5. Reiniciar Steam no modo padrao
Write-Step "Iniciando a Steam no padrao limpo..."
$SteamExe = Join-Path $SteamPath "steam.exe"

if (Test-Path $SteamExe) {
    Start-Process -FilePath $SteamExe
} else {
    Start-Process "steam://open/main"
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "   STEAM RESTAURADA E REINICIADA COM SUCESSO!            " -ForegroundColor White
Write-Host "   Nenhuma reinstalacao foi necessaria. Bom jogo!        " -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""
