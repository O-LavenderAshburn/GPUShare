@echo off
setlocal

:: GPUShare — Windows One-Click Launcher
:: Double-click this file to install GPUShare.
:: Pass arguments: setup.bat --quick

title GPUShare Installer

echo.
echo   ██████  ██████  ██    ██     ███    ██  ██████  ██████  ███████
echo  ██       ██   ██ ██    ██     ████   ██ ██    ██ ██   ██ ██
echo  ██   ███ ██████  ██    ██     ██ ██  ██ ██    ██ ██   ██ █████
echo  ██    ██ ██      ██    ██     ██  ██ ██ ██    ██ ██   ██ ██
echo   ██████  ██       ██████      ██   ████  ██████  ██████  ███████
echo.
echo   GPUShare Installer for Windows
echo.

:: Check PowerShell availability
where powershell >nul 2>&1
if errorlevel 1 (
    echo [x] PowerShell is required but not found.
    echo     Install PowerShell from: https://aka.ms/PSWindows
    pause
    exit /b 1
)

:: Check if running as admin (optional, needed for some installs)
net session >nul 2>&1
if errorlevel 1 (
    echo [!] Not running as Administrator.
    echo     Some features may require admin privileges.
    echo     Right-click this file and select "Run as administrator" if needed.
    echo.
)

:: Check if setup.ps1 exists
if not exist "%~dp0setup.ps1" (
    echo [x] setup.ps1 not found in %~dp0
    echo     Make sure this batch file is in the GPUShare repository root.
    pause
    exit /b 1
)

echo [i] Launching PowerShell installer...
echo [i] This will install Docker, Ollama, and start GPUShare.
echo.

:: Pass all arguments through to PowerShell
powershell -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*

if errorlevel 1 (
    echo.
    echo [x] Installation failed. Check the output above for errors.
    echo     You can re-run:  .\setup.ps1
    pause
    exit /b 1
)

echo.
echo [+] Done! Press any key to exit.
pause >nul
