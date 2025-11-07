@echo off
REM Pato2 Host Agent Installation Script for Windows
REM This script automates the installation of Pato2 host agent on Windows

setlocal enabledelayedexpansion

REM Colors
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
) else (
    echo .env file already exists, will update values.
)

echo.
echo === Interactive configuration ===
echo Enter values; press Enter to keep defaults.

set /p HOST_TOKEN="HOST_TOKEN (required): "
if "%HOST_TOKEN%"=="" (
    echo ERROR: HOST_TOKEN is required.
    pause
    exit /b 1
)

set /p PATO2_ENDPOINT="PATO2_ENDPOINT [http://pato2.duckdns.org:5000]: "
if "%PATO2_ENDPOINT%"=="" set "PATO2_ENDPOINT=http://pato2.duckdns.org:5000"

set /p MINECRAFT_DIR="Ruta al servidor de Minecraft (MINECRAFT_DIR): "
if not exist "%MINECRAFT_DIR%" (
    echo WARNING: La ruta no existe. Se creara al iniciar si es necesario.
)

REM Valores por defecto sin preguntar para simplificar
set "SERVER_JAR=server.jar"
set "WORLD_NAME=world"

set /p BACKUPS_PATH="Ruta de backups (BACKUPS_PATH) [%%USERPROFILE%%\MinecraftBackups]: "
if "%BACKUPS_PATH%"=="" set "BACKUPS_PATH=%USERPROFILE%\MinecraftBackups"

set /p MAX_RAM_GB="RAM maxima en GB (Xmx) [4]: "
if "%MAX_RAM_GB%"=="" set "MAX_RAM_GB=4"
set /p MIN_RAM_GB="RAM minima en GB (Xms) [2]: "
if "%MIN_RAM_GB%"=="" set "MIN_RAM_GB=2"
set "JAVA_ARGS=-Xmx%MAX_RAM_GB%G -Xms%MIN_RAM_GB%G -XX:+UseG1GC"

set /p VIEW_DISTANCE="View distance (server.properties) [10]: "
if "%VIEW_DISTANCE%"=="" set "VIEW_DISTANCE=10"
set /p SIMULATION_DISTANCE="Simulation/Render distance (server.properties) [10]: "
if "%SIMULATION_DISTANCE%"=="" set "SIMULATION_DISTANCE=10"

echo.
echo === Google Drive (integrado) ===
echo Intentando detectar automaticamente credentials.json...
set "GDRIVE_CRED_PATH="
if exist "%CD%\credentials.json" set "GDRIVE_CRED_PATH=%CD%\credentials.json"
if "%GDRIVE_CRED_PATH%"=="" if exist "%MINECRAFT_DIR%\credentials.json" set "GDRIVE_CRED_PATH=%MINECRAFT_DIR%\credentials.json"
if "%GDRIVE_CRED_PATH%"=="" (
    echo No se encontro credentials.json automaticamente.
    set /p GDRIVE_CRED_PATH="Ruta a credentials.json (Enter para omitir): "
)
set /p GOOGLE_DRIVE_FOLDER_ID="Google Drive Folder ID (Enter para omitir): "
set /p GOOGLE_REFRESH_TOKEN="Google Refresh Token (Enter para omitir): "

REM Extraer client_id y client_secret del JSON si existe
set "GOOGLE_CLIENT_ID="
set "GOOGLE_CLIENT_SECRET="
if not "%GDRIVE_CRED_PATH%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $j=Get-Content '%GDRIVE_CRED_PATH%' | ConvertFrom-Json; if ($j.installed) { Write-Host ('CID=' + $j.installed.client_id); Write-Host ('CSECRET=' + $j.installed.client_secret) } elseif ($j.web) { Write-Host ('CID=' + $j.web.client_id); Write-Host ('CSECRET=' + $j.web.client_secret) } } catch { }" > tmp_gd.txt
    for /f "tokens=1,2 delims==" %%A in (tmp_gd.txt) do (
        if /i "%%A"=="CID" set "GOOGLE_CLIENT_ID=%%B"
        if /i "%%A"=="CSECRET" set "GOOGLE_CLIENT_SECRET=%%B"
    )
    del tmp_gd.txt 2>nul
)

echo.
echo Intentando generar automaticamente GOOGLE_REFRESH_TOKEN...
if "%GOOGLE_REFRESH_TOKEN%"=="" if not "%GDRIVE_CRED_PATH%"=="" (
  echo Se abrira el navegador para autorizar acceso a Google Drive.
  echo Por favor, inicia sesion y acepta los permisos.
  > gen_refresh.py echo import sys
  >> gen_refresh.py echo from google_auth_oauthlib.flow import InstalledAppFlow
  >> gen_refresh.py echo scopes = ['https://www.googleapis.com/auth/drive.file']
  >> gen_refresh.py echo flow = InstalledAppFlow.from_client_secrets_file(sys.argv[1], scopes=scopes)
  >> gen_refresh.py echo creds = flow.run_local_server(port=0)
  >> gen_refresh.py echo print(creds.refresh_token or '')
  python gen_refresh.py "%GDRIVE_CRED_PATH%" > tmp_refresh.txt
  for /f "usebackq delims=" %%T in ("tmp_refresh.txt") do set "GOOGLE_REFRESH_TOKEN=%%T"
  del gen_refresh.py 2>nul
  del tmp_refresh.txt 2>nul
  if "%GOOGLE_REFRESH_TOKEN%"=="" (
    echo No se pudo generar el refresh token automaticamente.
  ) else (
    echo Refresh token generado correctamente.
  )
)

echo.
echo === Actualizando .env real del host-agent ===
call :SetEnv HOST_TOKEN "%HOST_TOKEN%"
call :SetEnv PATO2_ENDPOINT "%PATO2_ENDPOINT%"
call :SetEnv MINECRAFT_DIR "%MINECRAFT_DIR%"
call :SetEnv SERVER_JAR "%SERVER_JAR%"
call :SetEnv WORLD_NAME "%WORLD_NAME%"
call :SetEnv JAVA_ARGS "%JAVA_ARGS%"
call :SetEnv BACKUPS_PATH "%BACKUPS_PATH%"

REM Escribir ambas variantes para compatibilidad
if not "%GOOGLE_CLIENT_ID%"=="" (
  call :SetEnv GOOGLE_CLIENT_ID "%GOOGLE_CLIENT_ID%"
  call :SetEnv GOOGLE_DRIVE_CLIENT_ID "%GOOGLE_CLIENT_ID%"
)
if not "%GOOGLE_CLIENT_SECRET%"=="" (
  call :SetEnv GOOGLE_CLIENT_SECRET "%GOOGLE_CLIENT_SECRET%"
  call :SetEnv GOOGLE_DRIVE_CLIENT_SECRET "%GOOGLE_CLIENT_SECRET%"
)
if not "%GOOGLE_REFRESH_TOKEN%"=="" (
  call :SetEnv GOOGLE_REFRESH_TOKEN "%GOOGLE_REFRESH_TOKEN%"
  call :SetEnv GOOGLE_DRIVE_REFRESH_TOKEN "%GOOGLE_REFRESH_TOKEN%"
)
if not "%GOOGLE_DRIVE_FOLDER_ID%"=="" (
  call :SetEnv GOOGLE_DRIVE_FOLDER_ID "%GOOGLE_DRIVE_FOLDER_ID%"
)

REM Calcular y escribir intervalos/retencion (horas/dias y segundos)
set /p BACKUP_INTERVAL_HOURS="Horas entre backups (BACKUP_INTERVAL_HOURS) [24]: "
if "%BACKUP_INTERVAL_HOURS%"=="" set "BACKUP_INTERVAL_HOURS=24"
set /p BACKUP_RETENTION_DAYS="Dias de retencion (BACKUP_RETENTION_DAYS) [7]: "
if "%BACKUP_RETENTION_DAYS%"=="" set "BACKUP_RETENTION_DAYS=7"
set /a BACKUP_INTERVAL=%BACKUP_INTERVAL_HOURS%*3600
set /a BACKUP_RETENTION=%BACKUP_RETENTION_DAYS%
call :SetEnv BACKUP_INTERVAL_HOURS "%BACKUP_INTERVAL_HOURS%"
call :SetEnv BACKUP_RETENTION_DAYS "%BACKUP_RETENTION_DAYS%"
call :SetEnv BACKUP_INTERVAL "%BACKUP_INTERVAL%"
call :SetEnv BACKUP_RETENTION "%BACKUP_RETENTION%"

echo.
echo === Ajustando server.properties (view/simulation distance) ===
if exist "%MINECRAFT_DIR%\server.properties" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p='%MINECRAFT_DIR%\server.properties'; $c=Get-Content $p; $u=$false; $c = $c -replace '^view-distance=.*', 'view-distance=%VIEW_DISTANCE%' -replace '^simulation-distance=.*', 'simulation-distance=%SIMULATION_DISTANCE%'; if (-not ($c -match '^view-distance=')) { $c += '\nview-distance=%VIEW_DISTANCE%'; $u=$true } if (-not ($c -match '^simulation-distance=')) { $c += '\nsimulation-distance=%SIMULATION_DISTANCE%'; $u=$true } Set-Content -Path $p -Value $c"
) else (
  echo view-distance=%VIEW_DISTANCE%> "%MINECRAFT_DIR%\server.properties"
  echo simulation-distance=%SIMULATION_DISTANCE%>> "%MINECRAFT_DIR%\server.properties"
)

echo Configuration updated successfully.

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

goto :eof

:SetEnv
REM Usage: call :SetEnv KEY VALUE
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$envPath='.env'; $key=$args[0]; $val=$args[1]; $exists=$false; if (Test-Path $envPath) { $lines=Get-Content $envPath; $new = foreach ($line in $lines) { if ($line -match "^$key=") { $exists=$true; \"$key=$val\" } else { $line } }; if ($exists) { Set-Content -Path $envPath -Value $new } else { Add-Content -Path $envPath -Value \"$key=$val\" } } else { Set-Content -Path $envPath -Value \"$key=$val\" }" %~1 %~2
exit /b 0