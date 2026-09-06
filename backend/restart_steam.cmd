@echo off
setlocal EnableDelayedExpansion

ping 127.0.0.1 -n 2 >nul

set "STEAM_DIR="
for /f "tokens=2,*" %%A in ('reg query "HKEY_CURRENT_USER\Software\Valve\Steam" /v SteamPath 2^>nul ^| find "SteamPath"') do set "STEAM_DIR=%%B"

if defined STEAM_DIR (
    set "STEAM_DIR=!STEAM_DIR:/=\!"
) else (
    set "STEAM_DIR=C:\Program Files (x86)\Steam"
)

set "STEAM_EXE=!STEAM_DIR!\steam.exe"
if not exist "!STEAM_EXE!" (
    set "STEAM_EXE=C:\Program Files (x86)\Steam\steam.exe"
)

taskkill /F /IM steam.exe >nul 2>&1
taskkill /F /IM steamwebhelper.exe >nul 2>&1
taskkill /F /IM millennium* >nul 2>&1

ping 127.0.0.1 -n 3 >nul

if exist "!STEAM_EXE!" (
    start "" "!STEAM_EXE!"
) else (
    start "" "steam://open/main"
)

exit
