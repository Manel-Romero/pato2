@echo off
REM Pato2 Host Agent Installation Script for Windows
REM This script automates the installation of Pato2 host agent on Windows

setlocal enabledelayedexpansion

REM Colors (using PowerShell for colored output)
set "GREEN=[32m"
set "RED=[31m"
set "YELLOW=[33m"
set "BLUE=[34m"
set "NC=[0m"

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This script requires administrator privileges.
    echo Please run as administrator.
    pause
    exit /b 1
)

echo.
echo ========================================
echo    Pato2 Host Agent Installation
echo ========================================
echo.

REM Check Python installation
echo Checking Python installation...
python --version >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Python is not installed or not in PATH.
    echo Please install Python 3.7+ from https://python.org
    echo Make sure to check "Add Python to PATH" during installation.
    pause
    exit /b 1
)

REM Get Python version
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo Python version: %PYTHON_VERSION%

REM Check if Git is installed
echo Checking Git installation...
git --version >nul 2>&1
if %errorLevel% neq 0 (
    echo WARNING: Git is not installed.
    echo You can download it from https://git-scm.com/
    echo Or download the project manually.
    set /p CONTINUE="Continue without Git? (y/n): "
    if /i "!CONTINUE!" neq "y" exit /b 1
    set NO_GIT=1
) else (
    echo Git is available.
    set NO_GIT=0
)

REM Set installation directory
set "INSTALL_DIR=%USERPROFILE%\Pato2_TRAE"
echo Installation directory: %INSTALL_DIR%

REM Create installation directory
if exist "%INSTALL_DIR%" (
    echo WARNING: Installation directory already exists.
    set /p OVERWRITE="Overwrite existing installation? (y/n): "
    if /i "!OVERWRITE!" neq "y" exit /b 1
    
    echo Backing up existing installation...
    if exist "%INSTALL_DIR%.backup" rmdir /s /q "%INSTALL_DIR%.backup"
    move "%INSTALL_DIR%" "%INSTALL_DIR%.backup" >nul 2>&1
)

mkdir "%INSTALL_DIR%" 2>nul

REM Download or clone repository
if %NO_GIT% equ 0 (
    echo Cloning repository...
    cd /d "%USERPROFILE%"
    git clone https://github.com/Manel-Romero/pato2.git
    if %errorLevel% neq 0 (
        echo ERROR: Failed to clone repository.
        pause
        exit /b 1
    )
) else (
    echo Please download the Pato2_TRAE project manually and extract it to:
    echo %INSTALL_DIR%
    echo.
    echo Press any key when ready...
    pause >nul
    
    if not exist "%INSTALL_DIR%\host-agent" (
        echo ERROR: host-agent directory not found in %INSTALL_DIR%
        pause
        exit /b 1
    )
)

REM Navigate to host-agent directory
cd /d "%INSTALL_DIR%\host-agent"
if %errorLevel% neq 0 (
    echo ERROR: Could not access host-agent directory.
    pause
    exit /b 1
)

echo Current directory: %CD%

REM Create virtual environment
echo Creating Python virtual environment...
python -m venv venv
if %errorLevel% neq 0 (
    echo ERROR: Failed to create virtual environment.
    pause
    exit /b 1
)

REM Activate virtual environment and install dependencies
echo Activating virtual environment and installing dependencies...
call venv\Scripts\activate.bat
if %errorLevel% neq 0 (
    echo ERROR: Failed to activate virtual environment.
    pause
    exit /b 1
)

pip install --upgrade pip
pip install -r requirements.txt
if %errorLevel% neq 0 (
    echo ERROR: Failed to install Python dependencies.
    pause
    exit /b 1
)

REM Create configuration file
echo Setting up configuration...
if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo Created .env configuration file.
    echo.
    echo IMPORTANT: Please edit the .env file with your settings:
    echo - HOST_TOKEN: Must match the token on Pato2 server
    echo - PATO2_ENDPOINT: Your Pato2 server URL
    echo - MINECRAFT_DIR: Path to your Minecraft server
    echo - Google Drive credentials for backups
) else (
    echo .env file already exists, skipping creation.
)

REM Create batch scripts for easy management
echo Creating management scripts...

REM Start script
echo @echo off > start-host-agent.bat
echo cd /d "%CD%" >> start-host-agent.bat
echo call venv\Scripts\activate.bat >> start-host-agent.bat
echo python host_agent.py >> start-host-agent.bat
echo pause >> start-host-agent.bat

REM Stop script (creates a simple script to find and kill the process)
echo @echo off > stop-host-agent.bat
echo echo Stopping Pato2 Host Agent... >> stop-host-agent.bat
echo taskkill /f /im python.exe /fi "WINDOWTITLE eq Pato2*" 2^>nul >> stop-host-agent.bat
echo echo Host agent stopped. >> stop-host-agent.bat
echo pause >> stop-host-agent.bat

REM Status script
echo @echo off > status-host-agent.bat
echo echo === Pato2 Host Agent Status === >> status-host-agent.bat
echo tasklist /fi "IMAGENAME eq python.exe" /fo table >> status-host-agent.bat
echo echo. >> status-host-agent.bat
echo echo === Recent Log Entries === >> status-host-agent.bat
echo if exist host_agent.log ( >> status-host-agent.bat
echo     powershell "Get-Content host_agent.log -Tail 10" >> status-host-agent.bat
echo ) else ( >> status-host-agent.bat
echo     echo No log file found. >> status-host-agent.bat
echo ) >> status-host-agent.bat
echo pause >> status-host-agent.bat

REM Update script
echo @echo off > update-host-agent.bat
echo cd /d "%CD%" >> update-host-agent.bat
echo echo Updating Pato2 Host Agent... >> update-host-agent.bat
echo git pull >> update-host-agent.bat
echo call venv\Scripts\activate.bat >> update-host-agent.bat
echo pip install -r requirements.txt --upgrade >> update-host-agent.bat
echo echo Update complete! >> update-host-agent.bat
echo pause >> update-host-agent.bat

echo Management scripts created successfully.

REM Test installation
echo Testing installation...
call venv\Scripts\activate.bat
python -c "import requests, websocket, google.auth; print('All dependencies imported successfully')"
if %errorLevel% neq 0 (
    echo WARNING: Some dependencies may not be properly installed.
    echo Please check the error messages above.
) else (
    echo Dependency test passed.
)

REM Create Windows service (optional)
echo.
set /p CREATE_SERVICE="Do you want to create a Windows service for auto-start? (y/n): "
if /i "%CREATE_SERVICE%" equ "y" (
    echo.
    echo To create a Windows service, you'll need NSSM ^(Non-Sucking Service Manager^).
    echo.
    echo 1. Download NSSM from: https://nssm.cc/download
    echo 2. Extract nssm.exe to a folder ^(e.g., C:\nssm\^)
    echo 3. Run as administrator: nssm install Pato2HostAgent
    echo 4. Configure:
    echo    - Path: %CD%\venv\Scripts\python.exe
    echo    - Startup directory: %CD%
    echo    - Arguments: host_agent.py
    echo 5. Set service to start automatically
    echo.
    echo Alternatively, use the Task Scheduler for startup.
)

REM Create desktop shortcuts
echo.
set /p CREATE_SHORTCUTS="Create desktop shortcuts? (y/n): "
if /i "%CREATE_SHORTCUTS%" equ "y" (
    echo Creating desktop shortcuts...
    
    REM Create shortcut for start script
    powershell "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\Start Pato2 Host.lnk'); $Shortcut.TargetPath = '%CD%\start-host-agent.bat'; $Shortcut.WorkingDirectory = '%CD%'; $Shortcut.Save()"
    
    REM Create shortcut for status script
    powershell "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\Pato2 Host Status.lnk'); $Shortcut.TargetPath = '%CD%\status-host-agent.bat'; $Shortcut.WorkingDirectory = '%CD%'; $Shortcut.Save()"
    
    echo Desktop shortcuts created.
)

REM Final instructions
echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.
echo Installation directory: %INSTALL_DIR%\host-agent
echo.
echo NEXT STEPS:
echo 1. Edit the .env file with your configuration:
echo    - Set HOST_TOKEN to match your Pato2 server
echo    - Set PATO2_ENDPOINT to your server URL
echo    - Configure MINECRAFT_DIR path
echo    - Set up Google Drive credentials for backups
echo.
echo 2. Ensure your Minecraft server is set up in the specified directory
echo.
echo 3. Start the host agent:
echo    - Double-click "start-host-agent.bat", or
echo    - Use the desktop shortcut if created
echo.
echo MANAGEMENT COMMANDS:
echo - Start:  start-host-agent.bat
echo - Stop:   stop-host-agent.bat  
echo - Status: status-host-agent.bat
echo - Update: update-host-agent.bat
echo.
echo CONFIGURATION FILE:
echo %CD%\.env
echo.
echo LOG FILE:
echo %CD%\host_agent.log
echo.
echo For detailed setup instructions, see:
echo %INSTALL_DIR%\docs\es\installation\host-agent.md
echo.
echo Press any key to open the configuration file...
pause >nul

REM Open configuration file for editing
notepad "%CD%\.env"

echo.
echo Installation script completed.
echo You can now start the host agent using start-host-agent.bat
pause