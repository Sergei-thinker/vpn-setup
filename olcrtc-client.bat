@echo off
REM =============================================================================
REM  OLCRTC-CLIENT.BAT — Windows клиент OlcRTC (Layer 3 аварийный)
REM =============================================================================
REM
REM  Запускает нативный olcrtc.exe (Go cross-compiled) или WSL2 fallback.
REM  Предоставляет SOCKS5 прокси на localhost:8809 для Hiddify/браузера.
REM
REM  Сборка olcrtc.exe (на Linux/macOS/WSL2):
REM    cd /opt/olcrtc && GOOS=windows GOARCH=amd64 go build -o olcrtc.exe ./cmd/olcrtc
REM
REM  Использование:
REM    olcrtc-client.bat                          (интерактивный режим)
REM    olcrtc-client.bat ROOM_ID HEX_KEY [PORT]   (с параметрами)
REM
REM  Создано с помощью Claude Code
REM  Дата: 2026-04-08
REM =============================================================================

echo.
echo  ======================================================
echo   OlcRTC Client -- Layer 3 Emergency WebRTC
echo  ======================================================
echo.

REM Check for native binary first
set "SCRIPT_DIR=%~dp0"
set "OLCRTC_EXE=%SCRIPT_DIR%olcrtc.exe"

if exist "%OLCRTC_EXE%" (
    echo  [OK] Native olcrtc.exe found
    echo.

    if "%~1"=="" (
        set /p ROOM_ID="  Telemost Room ID: "
        set /p HEX_KEY="  Encryption Key (hex): "
        set SOCKS_PORT=8809
    ) else (
        set ROOM_ID=%~1
        set HEX_KEY=%~2
        if "%~3"=="" (set SOCKS_PORT=8809) else (set SOCKS_PORT=%~3)
    )

    echo.
    echo  SOCKS5 proxy: localhost:%SOCKS_PORT%
    echo.
    echo  For Hiddify: Settings - Add Server - SOCKS5 - 127.0.0.1:%SOCKS_PORT%
    echo  Test: curl --socks5h localhost:%SOCKS_PORT% https://ifconfig.me
    echo.

    "%OLCRTC_EXE%" -mode cnc -room %ROOM_ID% -key %HEX_KEY% -socks-port %SOCKS_PORT%
    goto :end
)

REM Fallback: WSL2
echo  [WARN] olcrtc.exe not found, trying WSL2 fallback...
echo.
echo  To build native binary (faster, no WSL2 needed):
echo    On Linux/WSL2: cd /opt/olcrtc
echo    GOOS=windows GOARCH=amd64 go build -o olcrtc.exe ./cmd/olcrtc
echo    Copy olcrtc.exe to this directory
echo.

wsl --status >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Neither olcrtc.exe nor WSL2 found!
    echo  Please build olcrtc.exe or install WSL2: wsl --install
    pause
    exit /b 1
)

echo  [INFO] Starting via WSL2...
wsl -e bash -c "cd /opt/olcrtc 2>/dev/null && go run ./cmd/olcrtc -mode cnc %* 2>&1 || bash '%SCRIPT_DIR:\=/%olcrtc-wsl-client.sh' %*"

:end
if errorlevel 1 (
    echo.
    echo  [ERROR] OlcRTC client failed. Check output above.
    pause
)
