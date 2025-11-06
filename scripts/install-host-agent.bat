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
set "DEFAULT_INSTALL_DIR=%USERPROFILE%\Pato2"
set "INSTALL_DIR=%DEFAULT_INSTALL_DIR%"
echo Installation directory set to: %INSTALL_DIR%
set "PATO2_REPO_DIR=%INSTALL_DIR%\pato2"

REM Check if Pato2 directory already exists
if exist "%PATO2_REPO_DIR%" (
    echo WARNING: Installation directory already exists.
    set /p OVERWRITE="Overwrite existing installation? (y/n): "
    if /i "!OVERWRITE!" neq "y" exit /b 1
    
    echo Backing up existing installation...
    if exist "%PATO2_REPO_DIR%.backup" rmdir /s /q "%PATO2_REPO_DIR%.backup"
    move "%PATO2_REPO_DIR%" "%PATO2_REPO_DIR%.backup" >nul 2>&1
)

mkdir "%PATO2_REPO_DIR%" 2>nul

REM Download or clone repository
if %NO_GIT% equ 0 (
    echo Cloning repository...
    REM Change to the parent directory of where Pato2 will be installed
    for %%i in ("%PATO2_REPO_DIR%") do set "PARENT_DIR=%%~dpi"
    cd /d "%PARENT_DIR%"
    git clone https://github.com/Manel-Romero/pato2.git "%PATO2_REPO_DIR%"
    if %errorLevel% neq 0 (
        echo ERROR: Failed to clone repository.
        pause
        exit /b 1
    )
) else (
    echo Please download the Pato2 project manually and extract it to:
    echo %PATO2_REPO_DIR%
    echo.
    echo Press any key when ready...
    pause >nul
    
    if not exist "%PATO2_REPO_DIR%\host-agent" (
        echo ERROR: host-agent directory not found in %PATO2_REPO_DIR%
        pause
        exit /b 1
    )
)

REM Navigate to host-agent directory
cd /d "%PATO2_REPO_DIR%\host-agent"
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

REM Ensure .env file exists
if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo Created .env configuration file from .env.example.
) else (
    echo .env file already exists. Will update existing values.
)

REM Function to update or add a variable in .env
REM Usage: call :SET_ENV_VAR "VARIABLE_NAME" "Default Value"
:SET_ENV_VAR
set "VAR_NAME=%~1"
set "DEFAULT_VALUE=%~2"

REM Read current value from .env if it exists
set "CURRENT_VALUE="
for /f "tokens=1* delims==" %%a in ('findstr /b /c:"%VAR_NAME%=" .env 2^>nul') do (
    set "CURRENT_VALUE=%%b"
)

if not "%CURRENT_VALUE%"=="" (
    set /p INPUT_VALUE="Enter %VAR_NAME% (current: %CURRENT_VALUE%, default: %DEFAULT_VALUE%): "
) else (
    set /p INPUT_VALUE="Enter %VAR_NAME% (default: %DEFAULT_VALUE%): "
)

if "%INPUT_VALUE%"=="" (
    set "FINAL_VALUE=%DEFAULT_VALUE%"
) else (
    set "FINAL_VALUE=%INPUT_VALUE%"
)

REM Use PowerShell to update or add the variable
powershell -Command "
    $filePath = '.\.env'
    $varName = '%VAR_NAME%'
    $varValue = '%FINAL_VALUE%'
    $content = [System.IO.File]::ReadAllLines($filePath)
    $found = $false
    for ($i = 0; $i -lt $content.Length; $i++) {
        if ($content[$i].StartsWith("$varName=")) {
            $content[$i] = "$varName=$varValue"
            $found = $true
            break
        }
    }
    if (-not $found) {
        $content += "`n$varName=$varValue"
    }
    [System.IO.File]::WriteAllLines($filePath, $content)
"
echo Set %VAR_NAME%=%FINAL_VALUE%
goto :eof

REM Prompt for configuration values
call :SET_ENV_VAR "HOST_TOKEN" "your_shared_token_for_hosts_change_this"
call :SET_ENV_VAR "PATO2_ENDPOINT" "http://pato2.duckdns.org:5000"

REM Default Minecraft directory to a common path relative to Pato2 installation
set "DEFAULT_MINECRAFT_DIR=%PATO2_REPO_DIR%\minecraft_server"
call :SET_ENV_VAR "MINECRAFT_DIR" "%DEFAULT_MINECRAFT_DIR%"

call :SET_ENV_VAR "MINECRAFT_MIN_RAM" "1G"
call :SET_ENV_VAR "MINECRAFT_MAX_RAM" "2G"

call :SET_ENV_VAR "MINECRAFT_VIEW_DISTANCE" "14"
call :SET_ENV_VAR "MINECRAFT_SIMULATION_DISTANCE" "14"

REM Default Backups path to a common path relative to Pato2 installation
set "DEFAULT_BACKUPS_PATH=%PATO2_REPO_DIR%\backups"
call :SET_ENV_VAR "BACKUPS_PATH" "%DEFAULT_BACKUPS_PATH%"


REM Update server.properties with configured values
echo Updating server.properties...

set "MINECRAFT_SERVER_PROPERTIES=%MINECRAFT_DIR%\server.properties"

if exist "%MINECRAFT_SERVER_PROPERTIES%" (
    REM Read values from .env
    for /f "tokens=1* delims==" %%a in ('findstr /b /c:"MINECRAFT_VIEW_DISTANCE=" .env 2^>nul') do set "VIEW_DISTANCE=%%b"
    for /f "tokens=1* delims==" %%a in ('findstr /b /c:"MINECRAFT_SIMULATION_DISTANCE=" .env 2^>nul') do set "SIMULATION_DISTANCE=%%b"

    REM Use PowerShell to update server.properties
    powershell -Command "
        $filePath = '%MINECRAFT_SERVER_PROPERTIES%'
        $content = [System.IO.File]::ReadAllLines($filePath)
        for ($i = 0; $i -lt $content.Length; $i++) {
            if ($content[$i].StartsWith("view-distance=")) {
                $content[$i] = "view-distance=%VIEW_DISTANCE%"
            }
            if ($content[$i].StartsWith("simulation-distance=")) {
                $content[$i] = "simulation-distance=%SIMULATION_DISTANCE%"
            }
        }
        [System.IO.File]::WriteAllLines($filePath, $content)
    "
    echo Updated view-distance and simulation-distance in server.properties.
) else (
    echo WARNING: server.properties not found at "%MINECRAFT_SERVER_PROPERTIES%". Skipping update.
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
echo Installation directory: %PATO2_REPO_DIR%\host-agent
echo.
echo NEXT STEPS:
echo 1. Review the .env file for your configuration:
echo    - HOST_TOKEN: Must match the token on Pato2 server
echo    - PATO2_ENDPOINT: Your Pato2 server URL
echo    - MINECRAFT_DIR: Path to your Minecraft server
echo    - MINECRAFT_MIN_RAM / MINECRAFT_MAX_RAM: RAM allocation for Minecraft
echo    - BACKUPS_PATH: Path for your backups
echo    - Google Drive credentials for backups (if applicable)
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
echo %PATO2_REPO_DIR%\docs\es\installation\host-agent.md
echo.
echo Press any key to open the configuration file for final review...
pause >nul

REM Open configuration file for editing
notepad "%CD%\.env"

echo.
echo Installation script completed.
echo You can now start the host agent using start-host-agent.bat
pause