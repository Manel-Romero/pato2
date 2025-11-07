@echo off
REM Pato2 Host Agent Installation Script for Windows
REM This script automates the installation of Pato2 host agent on Windows

setlocal enabledelayedexpansion

REM ========================================
REM Helpers and logging
REM ========================================
set "LOG_FILE=install-host-agent.log"
echo [%DATE% %TIME%] Starting installer > "%LOG_FILE%"

REM Helper: write info to screen and log
set "_echo=echo"
set "_log=>> "%LOG_FILE%""
REM Simple logger macros are tricky in batch; just echo and append

REM Helper: set or replace a line KEY=VALUE in .env
REM Usage: call :set_env KEY VALUE
REM ENV_FILE and ENV_EXAMPLE will be set after changing to host-agent directory
set "ENV_FILE=.env"
set "ENV_EXAMPLE=.env.example"
:
:set_env
set "_KEY=%~1"
set "_VAL=%~2"
if not exist "%ENV_FILE%" (
    echo Creating %ENV_FILE% >> "%LOG_FILE%"
    copy "%ENV_EXAMPLE%" "%ENV_FILE%" >nul 2>&1
)
set "TMP_PS=%TEMP%\pato2_setenv.ps1"
>"%TMP_PS%" echo param([string]^$File,[string]^$Key,[string]^$Value)
>>"%TMP_PS%" echo if (!(Test-Path ^$File)) { New-Item -ItemType File -Path ^$File -Force ^| Out-Null }
>>"%TMP_PS%" echo ^$lines = Get-Content ^$File
>>"%TMP_PS%" echo ^$pattern = '^' + [regex]::Escape(^$Key) + '='
>>"%TMP_PS%" echo ^$idx = (^$lines ^| Select-String -Pattern ^$pattern).LineNumber
>>"%TMP_PS%" echo if (^$idx) { ^$lines[^$idx-1] = "^$Key=^$Value"; ^$lines ^| Set-Content ^$File } else { Add-Content -Path ^$File -Value "^$Key=^$Value" }
powershell -NoProfile -File "%TMP_PS%" "%ENV_FILE%" "%_KEY%" "%_VAL%"
if errorlevel 1 (
    echo ERROR: failed writing %_KEY% to %ENV_FILE% >> "%LOG_FILE%"
)
del "%TMP_PS%" >nul 2>&1
goto :eof

REM Helper: update property in server.properties
REM Usage: call :set_property FILE KEY VALUE
:set_property
set "_PROP_FILE=%~1"
set "_PROP_KEY=%~2"
set "_PROP_VAL=%~3"
if not exist "%_PROP_FILE%" (
    echo WARNING: %_PROP_FILE% not found, skipping %_PROP_KEY% >> "%LOG_FILE%"
    goto :eof
)
set "TMP_PS=%TEMP%\pato2_setprop.ps1"
>"%TMP_PS%" echo param([string]^$File,[string]^$Key,[string]^$Value)
>>"%TMP_PS%" echo if (!(Test-Path ^$File)) { exit 0 }
>>"%TMP_PS%" echo ^$lines = Get-Content ^$File
>>"%TMP_PS%" echo ^$pattern = '^' + [regex]::Escape(^$Key) + '='
>>"%TMP_PS%" echo ^$idx = (^$lines ^| Select-String -Pattern ^$pattern).LineNumber
>>"%TMP_PS%" echo if (^$idx) { ^$lines[^$idx-1] = "^$Key=^$Value"; ^$lines ^| Set-Content ^$File } else { Add-Content -Path ^$File -Value "^$Key=^$Value" }
powershell -NoProfile -File "%TMP_PS%" "%_PROP_FILE%" "%_PROP_KEY%" "%_PROP_VAL%"
del "%TMP_PS%" >nul 2>&1
goto :eof

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
    echo ERROR: Python missing >> "%LOG_FILE%"
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
echo Using installation directory: %INSTALL_DIR% >> "%LOG_FILE%"

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
        echo ERROR: git clone failed >> "%LOG_FILE%"
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
    echo ERROR: cannot cd to host-agent >> "%LOG_FILE%"
    pause
    exit /b 1
)

echo Current directory: %CD%

REM Set absolute paths for env files to avoid wrong working directory issues
set "ENV_FILE=%CD%\.env"
set "ENV_EXAMPLE=%CD%\.env.example"

REM Create virtual environment
echo Creating Python virtual environment...
python -m venv venv
if %errorLevel% neq 0 (
    echo ERROR: Failed to create virtual environment.
    echo ERROR: venv creation failed >> "%LOG_FILE%"
    pause
    exit /b 1
)

REM Activate virtual environment and install dependencies
echo Activating virtual environment and installing dependencies...
call venv\Scripts\activate.bat
if %errorLevel% neq 0 (
    echo ERROR: Failed to activate virtual environment.
    echo ERROR: venv activation failed >> "%LOG_FILE%"
    pause
    exit /b 1
)

pip install --upgrade pip
pip install -r requirements.txt
if %errorLevel% neq 0 (
    echo ERROR: Failed to install Python dependencies.
    echo ERROR: pip install failed >> "%LOG_FILE%"
    pause
    exit /b 1
)

REM ========================================
REM Guided configuration (.env + server.properties)
REM ========================================
echo Configuring environment (.env) and server properties...
if not exist "%ENV_FILE%" copy "%ENV_EXAMPLE%" "%ENV_FILE%" >nul 2>&1

REM Defaults
set "DEFAULT_ENDPOINT=http://pato2.duckdns.org:5000"
set "DEFAULT_MINECRAFT_DIR=%USERPROFILE%\MinecraftServer"
set "DEFAULT_BACKUPS_PATH=%USERPROFILE%\minecraft_backups"
set "DEFAULT_VIEW=10"
set "DEFAULT_RENDER=10"
set "DEFAULT_MIN_RAM=1G"
set "DEFAULT_MAX_RAM=2G"

echo.
set /p HOST_TOKEN="Host Token (autenticación Pato2) [obligatorio]: "
if "!HOST_TOKEN!"=="" (
  echo ERROR: Host Token es obligatorio.
  echo ERROR: missing HOST_TOKEN >> "%LOG_FILE%"
  exit /b 1
)
call :set_env HOST_TOKEN "!HOST_TOKEN!"

echo.
set /p PATO2_ENDPOINT="PATO2 Endpoint [Default %DEFAULT_ENDPOINT%]: "
if "!PATO2_ENDPOINT!"=="" set "PATO2_ENDPOINT=%DEFAULT_ENDPOINT%"
call :set_env PATO2_ENDPOINT "!PATO2_ENDPOINT!"

echo.
set /p MINECRAFT_DIR="Ruta del servidor de Minecraft [Default %DEFAULT_MINECRAFT_DIR%]: "
if "!MINECRAFT_DIR!"=="" set "MINECRAFT_DIR=%DEFAULT_MINECRAFT_DIR%"
if not exist "!MINECRAFT_DIR!" (
  echo ERROR: La ruta no existe: !MINECRAFT_DIR!
  echo ERROR: invalid MINECRAFT_DIR >> "%LOG_FILE%"
  exit /b 1
)
call :set_env MINECRAFT_DIR "!MINECRAFT_DIR!"

echo.
set /p MINECRAFT_PORT="Puerto del servidor [Default 25565]: "
if "!MINECRAFT_PORT!"=="" set "MINECRAFT_PORT=25565"
call :set_env MINECRAFT_PORT "!MINECRAFT_PORT!"

echo.
set /p MIN_RAM="RAM mínima (e.g., 1G o 1024M) [Default %DEFAULT_MIN_RAM%]: "
if "!MIN_RAM!"=="" set "MIN_RAM=%DEFAULT_MIN_RAM%"
set /p MAX_RAM="RAM máxima (e.g., 2G o 2048M) [Default %DEFAULT_MAX_RAM%]: "
if "!MAX_RAM!"=="" set "MAX_RAM=%DEFAULT_MAX_RAM%"
set "JAVA_ARGS=-Xmx!MAX_RAM! -Xms!MIN_RAM!"
call :set_env JAVA_ARGS "!JAVA_ARGS!"

echo.
set /p BACKUPS_PATH="Ruta de almacenamiento de backups [Default %DEFAULT_BACKUPS_PATH%]: "
if "!BACKUPS_PATH!"=="" set "BACKUPS_PATH=%DEFAULT_BACKUPS_PATH%"
if not exist "!BACKUPS_PATH!" (
  echo Creando carpeta de backups: !BACKUPS_PATH!
  mkdir "!BACKUPS_PATH!" >nul 2>&1
)
call :set_env BACKUPS_PATH "!BACKUPS_PATH!"

echo.
set /p VIEW_DISTANCE="View distance (servidor) [Default %DEFAULT_VIEW%]: "
if "!VIEW_DISTANCE!"=="" set "VIEW_DISTANCE=%DEFAULT_VIEW%"
set /p RENDER_DISTANCE="Simulation/Render distance (servidor) [Default %DEFAULT_RENDER%]: "
if "!RENDER_DISTANCE!"=="" set "RENDER_DISTANCE=%DEFAULT_RENDER%"

REM Update server.properties if exists
set "PROP_FILE=!MINECRAFT_DIR!\server.properties"
call :set_property "%PROP_FILE%" view-distance "!VIEW_DISTANCE!"
call :set_property "%PROP_FILE%" simulation-distance "!RENDER_DISTANCE!"

echo.
set /p GOOGLE_DRIVE_FOLDER_ID="Google Drive FOLDER_ID existente (no crear nuevas carpetas) [obligatorio]: "
if "!GOOGLE_DRIVE_FOLDER_ID!"=="" (
  echo ERROR: FOLDER_ID es obligatorio.
  echo ERROR: missing FOLDER_ID >> "%LOG_FILE%"
  exit /b 1
)
call :set_env GOOGLE_DRIVE_FOLDER_ID "!GOOGLE_DRIVE_FOLDER_ID!"

echo.
set /p CRED_PATH="Ruta del credentials JSON (OAuth cliente existente) [obligatorio]: "
if "!CRED_PATH!"=="" (
  echo ERROR: Ruta de credentials JSON es obligatoria.
  echo ERROR: missing credentials path >> "%LOG_FILE%"
  exit /b 1
)
if not exist "!CRED_PATH!" (
  echo ERROR: No se encontró el archivo: !CRED_PATH!
  echo ERROR: invalid credentials path >> "%LOG_FILE%"
  exit /b 1
)

echo Generando token de Google Drive (se abrirá el navegador para autorizar)...
REM Create temporary Python script to generate OAuth refresh token
set "TMP_PY=gen_drive_token.py"
>"%TMP_PY%" echo import sys, json
>>"%TMP_PY%" echo from google_auth_oauthlib.flow import InstalledAppFlow
>>"%TMP_PY%" echo SCOPES = ['https://www.googleapis.com/auth/drive.file']
>>"%TMP_PY%" echo cred_path = sys.argv[1]
>>"%TMP_PY%" echo flow = InstalledAppFlow.from_client_secrets_file(cred_path, SCOPES)
>>"%TMP_PY%" echo creds = flow.run_local_server(port=0)
>>"%TMP_PY%" echo out = {'CLIENT_ID': creds.client_id, 'CLIENT_SECRET': creds.client_secret, 'REFRESH_TOKEN': creds.refresh_token}
>>"%TMP_PY%" echo print(json.dumps(out))

for /f "usebackq delims=" %%O in (`python "%TMP_PY%" "!CRED_PATH!"`) do set "GD_JSON=%%O"
del "%TMP_PY%" >nul 2>&1

REM Parse JSON via PowerShell to environment variables
for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "$j = ConvertFrom-Json '%GD_JSON%'; Write-Output ('CLIENT_ID='+$j.CLIENT_ID); Write-Output ('CLIENT_SECRET='+$j.CLIENT_SECRET); Write-Output ('REFRESH_TOKEN='+$j.REFRESH_TOKEN)"`) do (
  for /f "tokens=1,* delims==" %%K in ("%%A") do set "%%K=%%L"
)

if "!CLIENT_ID!"=="" (
  echo ERROR: No se pudo obtener CLIENT_ID.
  echo ERROR: oauth flow failed >> "%LOG_FILE%"
  exit /b 1
)
call :set_env GOOGLE_CLIENT_ID "!CLIENT_ID!"
call :set_env GOOGLE_CLIENT_SECRET "!CLIENT_SECRET!"
call :set_env GOOGLE_REFRESH_TOKEN "!REFRESH_TOKEN!"

echo.
echo Configuración completada. Se ha actualizado %ENV_FILE% con tus valores.
type "%ENV_FILE%" >> "%LOG_FILE%"

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

REM Test installation & basic validation
echo Testing installation and configuration...
call venv\Scripts\activate.bat
python -c "import requests, websocket, google.auth; print('Dependencies OK')" >nul 2>&1
if %errorLevel% neq 0 (
    echo WARNING: Some dependencies may not be properly installed.
    echo WARNING: Dependency test failed >> "%LOG_FILE%"
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
echo STARTUP:
echo  - Inicia el host con: start-host-agent.bat
echo  - Logs de instalacion: %CD%\%LOG_FILE%
echo  - Logs del agente:     %CD%\host_agent.log
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
echo Se ha configurado automáticamente tu archivo .env y server.properties (si existe).
echo Revisa los logs si necesitas detalles.

echo.
echo Installation script completed.
echo You can now start the host agent using start-host-agent.bat
pause