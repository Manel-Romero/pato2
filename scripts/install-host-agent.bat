@echo off
REM Pato2 Host Agent One-Click Installer (Windows)
REM - Opera sobre el repo local sin clonar
REM - Configura .env en host-agent
REM - Integra Google Drive sin crear carpetas
REM - Valida rutas/permisos y genera logs

setlocal enabledelayedexpansion

REM Paths
set "REPO_ROOT=%~dp0.."
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"
set "HOST_AGENT_DIR=%REPO_ROOT%\host-agent"
set "ENV_FILE=%HOST_AGENT_DIR%\.env"
set "LOG_FILE=%HOST_AGENT_DIR%\install.log"

echo ========================================
echo    Instalador Pato2 Host Agent (Windows)
echo ========================================
echo Log: %LOG_FILE%
echo.

REM Admin check (necesario para algunas comprobaciones de permisos)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Este instalador requiere privilegios de administrador.
    echo Ejecuta como Administrador y vuelve a intentar.
    echo [ERROR] Admin requerido >> "%LOG_FILE%"
    pause
    exit /b 1
)

REM Validar estructura de repo
if not exist "%HOST_AGENT_DIR%" (
    echo [ERROR] No se encuentra host-agent en %HOST_AGENT_DIR% >> "%LOG_FILE%"
    echo ERROR: No se encuentra el directorio host-agent.
    pause
    exit /b 1
)

echo Directorio host-agent: %HOST_AGENT_DIR% >> "%LOG_FILE%"
echo Directorio host-agent: %HOST_AGENT_DIR%

REM Comprobar Python
echo Comprobando Python...
python --version >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Python no esta instalado o no esta en PATH.
    echo Instala Python 3.8+ desde https://python.org (con "Add to PATH").
    echo [ERROR] Python ausente >> "%LOG_FILE%"
    pause
    exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo Python version: %PYTHON_VERSION% >> "%LOG_FILE%"
echo Python version: %PYTHON_VERSION%

REM Crear venv (si no existe)
cd /d "%HOST_AGENT_DIR%"
if not exist "venv" (
    echo Creando entorno virtual...
    python -m venv venv
    if %errorLevel% neq 0 (
        echo [ERROR] Fallo creando venv >> "%LOG_FILE%"
        echo ERROR: No se pudo crear el entorno virtual.
        pause
        exit /b 1
    )
)

call venv\Scripts\activate.bat
if %errorLevel% neq 0 (
    echo [ERROR] Fallo activando venv >> "%LOG_FILE%"
    echo ERROR: No se pudo activar el entorno virtual.
    pause
    exit /b 1
)

pip install --upgrade pip >nul 2>&1
pip install -r requirements.txt >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Fallo instalando dependencias >> "%LOG_FILE%"
    echo ERROR: No se pudieron instalar las dependencias.
    pause
    exit /b 1
)

REM Preparar .env real
if not exist "%ENV_FILE%" (
    copy ".env.example" "%ENV_FILE%" >nul
    echo Creado .env desde plantilla. >> "%LOG_FILE%"
)

REM ===== Entrada de parámetros =====
echo.
echo Configuracion basica:
set /p HOST_TOKEN="HOST_TOKEN (token del servidor Pato2): "
if "!HOST_TOKEN!"=="" (
    echo [ERROR] HOST_TOKEN vacio >> "%LOG_FILE%"
    echo ERROR: HOST_TOKEN es obligatorio.
    pause
    exit /b 1
)

set /p PATO2_ENDPOINT="PATO2_ENDPOINT [http://pato2.duckdns.org:5000]: "
if "!PATO2_ENDPOINT!"=="" set "PATO2_ENDPOINT=http://pato2.duckdns.org:5000"

set /p MINECRAFT_DIR="Ruta del servidor Minecraft (ej. C:\Minecraft\server): "
if not exist "!MINECRAFT_DIR!" (
    echo [ERROR] Ruta Minecraft no valida >> "%LOG_FILE%"
    echo ERROR: La ruta de Minecraft no existe.
    pause
    exit /b 1
)

set /p BACKUPS_PATH="Ruta para backups (ej. %HOST_AGENT_DIR%\backups): "
if "!BACKUPS_PATH!"=="" set "BACKUPS_PATH=%HOST_AGENT_DIR%\backups"
if not exist "!BACKUPS_PATH!" (
    mkdir "!BACKUPS_PATH!" >nul 2>&1
)
echo Prueba de escritura en backups...
echo test > "!BACKUPS_PATH!\write_test.tmp" 2>nul
if not exist "!BACKUPS_PATH!\write_test.tmp" (
    echo [ERROR] Permisos escritura backups >> "%LOG_FILE%"
    echo ERROR: No se puede escribir en la ruta de backups.
    pause
    exit /b 1
)
del /q "!BACKUPS_PATH!\write_test.tmp" >nul 2>&1

REM RAM configuracion
echo.
echo Configuracion de RAM:
set /p MAX_RAM_GB="RAM maxima (GB) [4]: "
if "!MAX_RAM_GB!"=="" set "MAX_RAM_GB=4"
set /p MIN_RAM_GB="RAM minima (GB) [2]: "
if "!MIN_RAM_GB!"=="" set "MIN_RAM_GB=2"
set "JAVA_ARGS=-Xmx!MAX_RAM_GB!G -Xms!MIN_RAM_GB!G -XX:+UseG1GC"

REM Distancias de servidor
echo.
echo Distancias de servidor (server.properties):
set /p VIEW_DISTANCE="view-distance [10]: "
if "!VIEW_DISTANCE!"=="" set "VIEW_DISTANCE=10"
set /p SIMULATION_DISTANCE="simulation-distance (render) [10]: "
if "!SIMULATION_DISTANCE!"=="" set "SIMULATION_DISTANCE=10"

REM Backup settings
echo.
echo Configuracion de backups:
set /p BACKUP_INTERVAL_HOURS="Intervalo de backups (horas) [24]: "
if "!BACKUP_INTERVAL_HOURS!"=="" set "BACKUP_INTERVAL_HOURS=24"
set /p BACKUP_RETENTION_DAYS="Retencion de backups (dias) [7]: "
if "!BACKUP_RETENTION_DAYS!"=="" set "BACKUP_RETENTION_DAYS=7"

REM Google Drive (sin crear carpeta nueva)
echo.
echo Configuracion Google Drive:
set /p GOOGLE_DRIVE_FOLDER_ID="GOOGLE_DRIVE_FOLDER_ID existente: "
if "!GOOGLE_DRIVE_FOLDER_ID!"=="" (
    echo [ERROR] FOLDER_ID vacio >> "%LOG_FILE%"
    echo ERROR: Debes proporcionar un Folder ID existente de Google Drive.
    pause
    exit /b 1
)

echo Instalando librerias OAuth de Google...
pip install google-auth google-auth-oauthlib google-api-python-client >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Fallo instalando librerias Google >> "%LOG_FILE%"
    echo ERROR: No se pudieron instalar librerias de Google.
    pause
    exit /b 1
)

set /p CRED_JSON_PATH="Ruta al JSON de credenciales OAuth (client_secret_xxx.json): "
if not exist "!CRED_JSON_PATH!" (
    echo [ERROR] Credenciales JSON no encontradas >> "%LOG_FILE%"
    echo ERROR: Archivo de credenciales no existe.
    pause
    exit /b 1
)

REM Generar refresh token sin crear carpetas
echo Generando token de actualizacion (se abrira el navegador)...
set "TOKEN_OUT=%HOST_AGENT_DIR%\gdrive_creds.out.json"
> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo import sys, json
>> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo from google_auth_oauthlib.flow import InstalledAppFlow
>> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo SCOPES = ['https://www.googleapis.com/auth/drive.file']
>> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo flow = InstalledAppFlow.from_client_secrets_file(r"%CRED_JSON_PATH%", SCOPES)
>> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo creds = flow.run_local_server(port=0)
>> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo out = {'client_id': creds.client_id, 'client_secret': creds.client_secret, 'refresh_token': creds.refresh_token}
>> "%HOST_AGENT_DIR%\gdrive_token_gen.py" echo print(json.dumps(out))

python "%HOST_AGENT_DIR%\gdrive_token_gen.py" > "%TOKEN_OUT%"
if %errorLevel% neq 0 (
    echo [ERROR] Fallo autenticando Google Drive >> "%LOG_FILE%"
    echo ERROR: No se pudo completar la autenticacion de Google.
    del /q "%HOST_AGENT_DIR%\gdrive_token_gen.py" >nul 2>&1
    pause
    exit /b 1
)
del /q "%HOST_AGENT_DIR%\gdrive_token_gen.py" >nul 2>&1

for /f "usebackq tokens=*" %%A in ("%TOKEN_OUT%") do set TOKEN_JSON=%%A
del /q "%TOKEN_OUT%" >nul 2>&1

for /f "usebackq tokens=2 delims=:," %%A in (`powershell -NoProfile -Command "$j = ConvertFrom-Json '%TOKEN_JSON%'; Write-Output \"client_id: $($j.client_id)\"; Write-Output \"client_secret: $($j.client_secret)\"; Write-Output \"refresh_token: $($j.refresh_token)\""`) do (
    if not defined GOOGLE_CLIENT_ID set GOOGLE_CLIENT_ID=%%A
)
for /f "usebackq tokens=2 delims=:," %%A in (`powershell -NoProfile -Command "$j = ConvertFrom-Json '%TOKEN_JSON%'; Write-Output \"client_secret: $($j.client_secret)\""`) do (
    if not defined GOOGLE_CLIENT_SECRET set GOOGLE_CLIENT_SECRET=%%A
)
for /f "usebackq tokens=2 delims=:," %%A in (`powershell -NoProfile -Command "$j = ConvertFrom-Json '%TOKEN_JSON%'; Write-Output \"refresh_token: $($j.refresh_token)\""`) do (
    if not defined GOOGLE_REFRESH_TOKEN set GOOGLE_REFRESH_TOKEN=%%A
)

REM ===== Actualizar .env de host-agent =====
echo Actualizando .env...
powershell -NoProfile -Command ^
  "$p='%ENV_FILE%'; ^
   if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p -Force | Out-Null }; ^
   $c = Get-Content $p -Raw; ^
   $envPairs = @{ ^
     'HOST_TOKEN'='%HOST_TOKEN%'; ^
     'PATO2_ENDPOINT'='%PATO2_ENDPOINT%'; ^
     'MINECRAFT_DIR'='%MINECRAFT_DIR%'; ^
     'BACKUPS_PATH'='%BACKUPS_PATH%'; ^
     'BACKUP_INTERVAL_HOURS'='%BACKUP_INTERVAL_HOURS%'; ^
     'BACKUP_RETENTION_DAYS'='%BACKUP_RETENTION_DAYS%'; ^
     'JAVA_ARGS'='%JAVA_ARGS%'; ^
     'GOOGLE_DRIVE_FOLDER_ID'='%GOOGLE_DRIVE_FOLDER_ID%'; ^
     'GOOGLE_CLIENT_ID'='%GOOGLE_CLIENT_ID%'; ^
     'GOOGLE_CLIENT_SECRET'='%GOOGLE_CLIENT_SECRET%'; ^
     'GOOGLE_REFRESH_TOKEN'='%GOOGLE_REFRESH_TOKEN%' ^
   }; ^
   foreach ($k in $envPairs.Keys) { ^
     if ($c -match "(?m)^$k=.*$") { $c = [regex]::Replace($c, "(?m)^$k=.*$", "$k=" + $envPairs[$k]) } ^
     else { $c += "`r`n$k=" + $envPairs[$k] } ^
   }; ^
   Set-Content -Path $p -Value $c"
if %errorLevel% neq 0 (
    echo [ERROR] Fallo escribiendo .env >> "%LOG_FILE%"
    echo ERROR: No se pudo actualizar el archivo .env.
    pause
    exit /b 1
)
echo .env actualizado correctamente. >> "%LOG_FILE%"

REM ===== Actualizar server.properties =====
set "SERVER_PROPERTIES=!MINECRAFT_DIR!\server.properties"
if exist "!SERVER_PROPERTIES!" (
    echo Actualizando server.properties...
    powershell -NoProfile -Command ^
      "$p='%SERVER_PROPERTIES%'; $c=Get-Content $p -Raw; ^
       if ($c -match '(?m)^view-distance=') { $c = [regex]::Replace($c,'(?m)^view-distance=.*$','view-distance=%VIEW_DISTANCE%') } else { $c += "`r`nview-distance=%VIEW_DISTANCE%" }; ^
       if ($c -match '(?m)^simulation-distance=') { $c = [regex]::Replace($c,'(?m)^simulation-distance=.*$','simulation-distance=%SIMULATION_DISTANCE%') } else { $c += "`r`nsimulation-distance=%SIMULATION_DISTANCE%" }; ^
       Set-Content -Path $p -Value $c"
    if %errorLevel% neq 0 (
        echo [ERROR] Fallo actualizando server.properties >> "%LOG_FILE%"
        echo WARNING: No se pudo actualizar server.properties.
    ) else (
        echo server.properties actualizado. >> "%LOG_FILE%"
    )
) else (
    echo WARNING: server.properties no encontrado, se omite. >> "%LOG_FILE%"
    echo Aviso: no se encontró server.properties en !MINECRAFT_DIR!.
)

REM Crear scripts de gestion
echo Creando scripts de gestion...
echo @echo off> start-host-agent.bat
echo cd /d "%HOST_AGENT_DIR%">> start-host-agent.bat
echo call venv\Scripts\activate.bat>> start-host-agent.bat
echo python host_agent.py>> start-host-agent.bat
echo pause>> start-host-agent.bat

echo @echo off> status-host-agent.bat
echo echo === Estado Pato2 Host Agent ===>> status-host-agent.bat
echo tasklist /fi "IMAGENAME eq python.exe" /fo table>> status-host-agent.bat
echo if exist "%HOST_AGENT_DIR%\host_agent.log" (>> status-host-agent.bat
echo   powershell "Get-Content '%HOST_AGENT_DIR%\host_agent.log' -Tail 20">> status-host-agent.bat
echo ) else (>> status-host-agent.bat
echo   echo No hay log.>> status-host-agent.bat
echo )>> status-host-agent.bat
echo pause>> status-host-agent.bat

echo @echo off> stop-host-agent.bat
echo echo Deteniendo Pato2 Host Agent...>> stop-host-agent.bat
echo taskkill /f /im python.exe 2^>nul>> stop-host-agent.bat
echo echo Host agent detenido.>> stop-host-agent.bat
echo pause>> stop-host-agent.bat

echo.
echo ========================================
echo   Instalacion completada correctamente
echo ========================================
echo .env y configuraciones aplicadas.
echo Detalles en: %LOG_FILE%
echo.
echo Para iniciar: start-host-agent.bat
echo Para estado:  status-host-agent.bat
echo Para parar:   stop-host-agent.bat
echo.
pause

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