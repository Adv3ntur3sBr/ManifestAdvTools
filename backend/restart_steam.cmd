@echo off
setlocal EnableDelayedExpansion

rem Wait 1 second before killing Steam so the IPC response can finish
ping 127.0.0.1 -n 2 >nul

rem Find Steam install path from registry
set "RAW_STEAM_DIR="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| find "SteamPath"') do set "RAW_STEAM_DIR=%%B"

if defined RAW_STEAM_DIR (
    set "STEAM_DIR=!RAW_STEAM_DIR:/=\!"
)

if not defined STEAM_DIR (
    set "STEAM_DIR=C:\Program Files (x86)\Steam"
)

rem Find steam executable
set "STEAM_EXE=!STEAM_DIR!\Steam.exe"
if not exist "!STEAM_EXE!" (
    set "STEAM_EXE=C:\Program Files (x86)\Steam\Steam.exe"
)

rem Kill Steam processes cleanly / forcefully
taskkill /F /IM steam.exe >nul 2>&1
taskkill /F /IM steamwebhelper.exe >nul 2>&1

rem Wait for processes to fully exit (reliable ping delay, works with redirection)
ping 127.0.0.1 -n 4 >nul

rem Launch Steam back up
if exist "!STEAM_EXE!" (
    start "" "!STEAM_EXE!"
) else (
    start "" steam://open/main
)

exit
