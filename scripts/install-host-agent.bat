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
set "INSTALL_DIR=%USERPROFILE%\Pato2"
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
    echo Please download the Pato2 project manually and extract it to:
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

REM Prepare installer logging
set "LOGFILE=%CD%\install.log"
echo. > "%LOGFILE%"
echo [%date% %time%] Starting installation > "%LOGFILE%"

REM Helper :log function
goto :after_log
:log
set "MSG=%~1"
echo [%date% %time%] %MSG%>> "%LOGFILE%"
echo %MSG%
goto :eof
:after_log

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
    call :log "ERROR: Failed to activate virtual environment."
    pause
    exit /b 1
)

pip install --upgrade pip
pip install -r requirements.txt
if %errorLevel% neq 0 (
    call :log "ERROR: Failed to install Python dependencies."
    pause
    exit /b 1
)

REM Interactive configuration prompts (minimized but complete)
call :log "Collecting configuration parameters..."

set "DEFAULT_PATO2_ENDPOINT=http://pato2.duckdns.org:5000"
set "DEFAULT_MINECRAFT_DIR=%USERPROFILE%\minecraft_server"
REM Defaults used sin prompts para JAR y mundo
set "DEFAULT_SERVER_JAR=server.jar"
set "DEFAULT_WORLD_NAME=world"
set "DEFAULT_VIEW_DISTANCE=10"
set "DEFAULT_SIMULATION_DISTANCE=10"
set "DEFAULT_BACKUPS_PATH=%USERPROFILE%\minecraft_backups"
set "DEFAULT_HEARTBEAT_INTERVAL_SECONDS=15"
set "DEFAULT_RECONNECT_DELAY_SECONDS=5"
set "DEFAULT_MAX_RECONNECT_ATTEMPTS=10"
set "DEFAULT_LOG_LEVEL=INFO"

echo.
set /p HOST_TOKEN="Host Token (obligatorio): "
if "%HOST_TOKEN%"=="" (
    call :log "ERROR: HOST_TOKEN no puede estar vacío."
    echo Abortando.
    exit /b 1
)

REM No solicitar endpoint; usar valor por defecto
set "PATO2_ENDPOINT=%DEFAULT_PATO2_ENDPOINT%"

echo.
set /p MINECRAFT_DIR="Ruta del servidor Minecraft [%DEFAULT_MINECRAFT_DIR%]: "
if "%MINECRAFT_DIR%"=="" set "MINECRAFT_DIR=%DEFAULT_MINECRAFT_DIR%"
if not exist "%MINECRAFT_DIR%" (
    call :log "ERROR: La ruta del servidor Minecraft no existe: %MINECRAFT_DIR%"
    echo Crea la carpeta y vuelve a ejecutar el instalador.
    exit /b 1
)

REM No solicitar nombre del JAR; usar valor por defecto
set "SERVER_JAR=%DEFAULT_SERVER_JAR%"

REM No solicitar nombre del mundo; usar valor por defecto
set "WORLD_NAME=%DEFAULT_WORLD_NAME%"

echo.
set /p RAM_MAX_GB="RAM máxima (GB) [4]: "
if "%RAM_MAX_GB%"=="" set "RAM_MAX_GB=4"
echo.
set /p RAM_MIN_GB="RAM mínima (GB) [2]: "
if "%RAM_MIN_GB%"=="" set "RAM_MIN_GB=2"

REM Validate numeric RAM
for /f "delims=0123456789" %%A in ("%RAM_MAX_GB%%RAM_MIN_GB%") do set "_nonnum=1"
if defined _nonnum (
    call :log "ERROR: RAM especificada debe ser numérica (GB)."
    exit /b 1
)
set "JAVA_ARGS=-Xmx%RAM_MAX_GB%G -Xms%RAM_MIN_GB%G -XX:+UseG1GC"

echo.
set /p VIEW_DISTANCE="View distance [%DEFAULT_VIEW_DISTANCE%]: "
if "%VIEW_DISTANCE%"=="" set "VIEW_DISTANCE=%DEFAULT_VIEW_DISTANCE%"
echo.
set /p SIMULATION_DISTANCE="Render/Simulation distance [%DEFAULT_SIMULATION_DISTANCE%]: "
if "%SIMULATION_DISTANCE%"=="" set "SIMULATION_DISTANCE=%DEFAULT_SIMULATION_DISTANCE%"

echo.
set /p BACKUPS_PATH="Ruta almacenamiento backups [%DEFAULT_BACKUPS_PATH%]: "
if "%BACKUPS_PATH%"=="" set "BACKUPS_PATH=%DEFAULT_BACKUPS_PATH%"
if not exist "%BACKUPS_PATH%" (
    mkdir "%BACKUPS_PATH%" 2>nul
)
echo test>"%BACKUPS_PATH%\__writetest__.tmp" 2>nul
if not exist "%BACKUPS_PATH%\__writetest__.tmp" (
    call :log "ERROR: No se puede escribir en la ruta de backups: %BACKUPS_PATH%"
    exit /b 1
)
del /q "%BACKUPS_PATH%\__writetest__.tmp" 2>nul

echo.
set /p GOOGLE_DRIVE_FOLDER_ID="Google Drive FOLDER_ID (existente): "
if "%GOOGLE_DRIVE_FOLDER_ID%"=="" (
    call :log "ERROR: Debes proporcionar un FOLDER_ID existente de Google Drive."
    exit /b 1
)

echo.
set /p CREDENTIALS_JSON="Ruta a credentials.json (Google OAuth): "
if "%CREDENTIALS_JSON%"=="" (
    call :log "ERROR: Debes proporcionar la ruta a credentials.json."
    exit /b 1
)
if not exist "%CREDENTIALS_JSON%" (
    call :log "ERROR: No se encontró credentials.json en: %CREDENTIALS_JSON%"
    exit /b 1
)

REM Generar token de Google Drive usando credentials.json
set "GOOGLE_DRIVE_CLIENT_ID="
set "GOOGLE_DRIVE_CLIENT_SECRET="
set "GOOGLE_DRIVE_REFRESH_TOKEN="
call :log "Generando token de Google Drive con credentials.json..."
> "%CD%\generate_drive_token_from_json.py" (
    echo import sys, json
    echo from google_auth_oauthlib.flow import InstalledAppFlow
    echo SCOPES = ['https://www.googleapis.com/auth/drive.file']
    echo cred_path = sys.argv[1]
    echo with open(cred_path, 'r') as f:
    echo 	data = json.load(f)
    echo ci = data.get('installed', {}).get('client_id', '')
    echo cs = data.get('installed', {}).get('client_secret', '')
    echo flow = InstalledAppFlow.from_client_secrets_file(cred_path, SCOPES)
    echo creds = flow.run_local_server(port=0)
    echo print(f"CLIENT_ID={ci}")
    echo print(f"CLIENT_SECRET={cs}")
    echo print(f"REFRESH_TOKEN={creds.refresh_token or ''}")
)
for /f "usebackq tokens=1,* delims==" %%A in (`python "%CD%\generate_drive_token_from_json.py" "%CREDENTIALS_JSON%"`) do (
    if "%%A"=="CLIENT_ID" set "GOOGLE_DRIVE_CLIENT_ID=%%B"
    if "%%A"=="CLIENT_SECRET" set "GOOGLE_DRIVE_CLIENT_SECRET=%%B"
    if "%%A"=="REFRESH_TOKEN" set "GOOGLE_DRIVE_REFRESH_TOKEN=%%B"
)
del /q "%CD%\generate_drive_token_from_json.py" 2>nul
if "%GOOGLE_DRIVE_REFRESH_TOKEN%"=="" (
    call :log "ADVERTENCIA: No se obtuvo refresh token. Repite la autorización más tarde."
) else (
    call :log "Token de Google Drive generado correctamente."
)

REM System tuning defaults
set "HEARTBEAT_INTERVAL_SECONDS=%DEFAULT_HEARTBEAT_INTERVAL_SECONDS%"
set "RECONNECT_DELAY_SECONDS=%DEFAULT_RECONNECT_DELAY_SECONDS%"
set "MAX_RECONNECT_ATTEMPTS=%DEFAULT_MAX_RECONNECT_ATTEMPTS%"
set "LOG_LEVEL=%DEFAULT_LOG_LEVEL%"

REM Write .env directly with collected values
call :log "Escribiendo archivo .env con la configuración..."
(
    echo HOST_TOKEN=%HOST_TOKEN%
    echo PATO2_ENDPOINT=%PATO2_ENDPOINT%
    echo MINECRAFT_DIR=%MINECRAFT_DIR%
    echo SERVER_JAR=%SERVER_JAR%
    echo WORLD_NAME=%WORLD_NAME%
    echo JAVA_ARGS=%JAVA_ARGS%
    echo GOOGLE_DRIVE_FOLDER_ID=%GOOGLE_DRIVE_FOLDER_ID%
    echo GOOGLE_DRIVE_CLIENT_ID=%GOOGLE_DRIVE_CLIENT_ID%
    echo GOOGLE_DRIVE_CLIENT_SECRET=%GOOGLE_DRIVE_CLIENT_SECRET%
    echo GOOGLE_DRIVE_REFRESH_TOKEN=%GOOGLE_DRIVE_REFRESH_TOKEN%
    echo BACKUPS_PATH=%BACKUPS_PATH%
    echo BACKUP_INTERVAL_HOURS=24
    echo BACKUP_RETENTION_DAYS=7
    echo HEARTBEAT_INTERVAL_SECONDS=%HEARTBEAT_INTERVAL_SECONDS%
    echo RECONNECT_DELAY_SECONDS=%RECONNECT_DELAY_SECONDS%
    echo MAX_RECONNECT_ATTEMPTS=%MAX_RECONNECT_ATTEMPTS%
    echo LOG_LEVEL=%LOG_LEVEL%
) > ".env"
if %errorLevel% neq 0 (
    call :log "ERROR: No se pudo escribir el archivo .env."
    exit /b 1
)

REM Update server.properties with view/simulation distance
set "SERVER_PROPERTIES=%MINECRAFT_DIR%\server.properties"
if exist "%SERVER_PROPERTIES%" (
    call :log "Actualizando server.properties (%SERVER_PROPERTIES%)..."
    powershell -NoProfile -Command "\
        $p='%SERVER_PROPERTIES%'; \
        $content = if (Test-Path $p) { Get-Content $p } else { @() }; \
        $map = @{ 'view-distance'='%VIEW_DISTANCE%'; 'simulation-distance'='%SIMULATION_DISTANCE%' }; \
        foreach ($k in $map.Keys) { \
            if ($content | Select-String -Pattern "^$k=.*" -Quiet) { \
                $content = $content -replace ("^"+$k+"=.*"), ($k+"="+$map[$k]); \
            } else { \
                $content += ($k+"="+$map[$k]); \
            } \
        }; \
        Set-Content -Path $p -Value $content \
    "
    if %errorLevel% neq 0 (
        call :log "ADVERTENCIA: No se pudo actualizar server.properties."
    ) else (
        call :log "server.properties actualizado."
    )
) else (
    call :log "Nota: No se encontró server.properties en %MINECRAFT_DIR%."
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
echo Configuración aplicada en: %CD%\.env
echo Se registró un log detallado en: %LOGFILE%
echo.
echo Puedes iniciar el host agent ahora:
echo    - Doble clic en "start-host-agent.bat"
echo    - ^(opcional^) crear servicio con NSSM
echo.
echo MANAGEMENT COMMANDS:
echo - Start:  start-host-agent.bat
echo - Stop:   stop-host-agent.bat  
echo - Status: status-host-agent.bat
echo - Update: update-host-agent.bat
echo.
echo LOG FILE (runtime):
echo %CD%\host_agent.log
echo.
echo Documentación:
echo %INSTALL_DIR%\docs\es\installation\host-agent.md

echo.
echo Installation script completed.
echo You can now start the host agent using start-host-agent.bat
pause