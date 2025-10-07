# Instalación del Agente Host (PC)

Guía completa para instalar y configurar el agente host de Pato2 en tu PC.

## Requisitos Previos

### Hardware
- **PC con Windows 10/11, Linux o macOS**
- **RAM**: Mínimo 4GB (8GB recomendado)
- **Almacenamiento**: 10GB libres para Minecraft + mundos
- **Conexión a internet** estable

### Software
- **Python 3.7** o superior
- **Git** para clonar el repositorio
- **Servidor de Minecraft** (se puede descargar automáticamente)

## Instalación de Python

### Windows

1. **Descargar Python**:
   - Ir a https://python.org/downloads/
   - Descargar Python 3.11 o superior
   - **IMPORTANTE**: Marcar "Add Python to PATH" durante la instalación

2. **Verificar instalación**:
   ```cmd
   python --version
   pip --version
   ```

### Linux (Ubuntu/Debian)

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade

# Instalar Python y pip
sudo apt install python3 python3-pip python3-venv git

# Verificar instalación
python3 --version
pip3 --version
```

### macOS

```bash
# Instalar Homebrew si no está instalado
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Instalar Python
brew install python git

# Verificar instalación
python3 --version
pip3 --version
```

## Descarga e Instalación

### Método Automático (Windows)

1. **Descargar script de instalación**:
   ```cmd
   curl -O https://raw.githubusercontent.com/Manel-Romero/pato2/main/scripts/install-host-agent.bat
   ```

2. **Ejecutar como administrador**:
   ```cmd
   install-host-agent.bat
   ```

### Método Manual

1. **Clonar repositorio**:
   ```bash
   git clone https://github.com/Manel-Romero/pato2.git
   cd pato2/host-agent
   ```

2. **Crear entorno virtual**:
   ```bash
   # Windows
   python -m venv venv
   venv\Scripts\activate

   # Linux/macOS
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Instalar dependencias**:
   ```bash
   pip install -r requirements.txt
   ```

## Configuración

### Variables de Entorno

1. **Copiar archivo de ejemplo**:
   ```bash
   cp .env.example .env
   ```

2. **Editar configuración**:
   ```bash
   # Windows
   notepad .env

   # Linux/macOS
   nano .env
   ```

### Configuración Básica

```env
# Conexión a Pato2
PATO2_HOST=pato2.duckdns.org
PATO2_PORT=5000
PATO2_TOKEN=tu_host_token_compartido

# Información del host
HOST_NAME=MiPC-Gaming
HOST_DESCRIPTION=PC Gaming con RTX 4070

# Servidor Minecraft
MINECRAFT_DIR=./minecraft-server
MINECRAFT_PORT=25565
MINECRAFT_JAR=server.jar
MINECRAFT_WORLD=world
MINECRAFT_JAVA_ARGS=-Xmx4G -Xms2G

# Google Drive (Opcional)
GOOGLE_DRIVE_FOLDER_ID=tu_folder_id_de_google_drive
GOOGLE_CLIENT_ID=tu_client_id
GOOGLE_CLIENT_SECRET=tu_client_secret
GOOGLE_REFRESH_TOKEN=tu_refresh_token

# Configuración de backups
BACKUP_PATH=./backups
BACKUP_INTERVAL=3600  # 1 hora en segundos
BACKUP_RETENTION=7    # Días

# Sistema
HEARTBEAT_INTERVAL=30  # segundos
RECONNECT_DELAY=5      # segundos
LOG_LEVEL=INFO
```

### Configuración del Servidor Minecraft

1. **Crear directorio**:
   ```bash
   mkdir minecraft-server
   cd minecraft-server
   ```

2. **Descargar servidor**:
   [Descarga desde PaperMC](https://papermc.io/downloads/paper)
   Renombra el archivo descargado a `server.jar` y añádelo al directorio `minecraft-server`.

3. **Aceptar EULA**:
   ```bash
   echo "eula=true" > eula.txt
   ```

4. **Configurar server.properties**:
   ```properties
   # Configuración básica
   server-port=25565
   online-mode=true
   difficulty=normal
   gamemode=survival
   max-players=20
   motd=Servidor Pato2
   
   # Configuración de red
   server-ip=127.0.0.1
   enable-rcon=false
   
   # Configuración del mundo
   level-name=world
   level-type=minecraft:normal
   spawn-protection=16
   ```

## Primer Inicio

### Probar conexión a Pato2

```bash
# Activar entorno virtual
# Windows: venv\Scripts\activate
# Linux/macOS: source venv/bin/activate

# Probar conexión
python host_agent.py --test-connection
```

### Iniciar agente

```bash
python host_agent.py
```

### Verificar funcionamiento

1. **Comprobar logs**:
   ```
   [INFO] Conectando a Pato2 en pato2.duckdns.org:5000
   [INFO] Autenticación exitosa
   [INFO] Ofreciendo host al servidor
   [INFO] Host aceptado, iniciando servidor Minecraft
   [INFO] Servidor Minecraft iniciado en puerto 25565
   [INFO] Heartbeat enviado exitosamente
   ```

2. **Verificar en panel web**:
   - Ir a `http://pato2.duckdns.org:5000`
   - Verificar que tu host aparece como "Activo"

## Configurar como Servicio

### Windows (con NSSM)

1. **Descargar NSSM**:
   - Ir a https://nssm.cc/download
   - Descargar y extraer nssm.exe

2. **Instalar servicio**:
   ```cmd
   # Abrir CMD como administrador
   cd C:\ruta\a\Pato2\host-agent
   
   # Instalar servicio
   nssm install Pato2HostAgent
   
   # Configurar servicio
   nssm set Pato2HostAgent Application "C:\ruta\a\python.exe"
   nssm set Pato2HostAgent AppParameters "C:\ruta\a\Pato2\host-agent\host_agent.py"
   nssm set Pato2HostAgent AppDirectory "C:\ruta\a\Pato2\host-agent"
   nssm set Pato2HostAgent DisplayName "Pato2 Host Agent"
   nssm set Pato2HostAgent Description "Agente host para sistema Pato2"
   
   # Iniciar servicio
   nssm start Pato2HostAgent
   ```

3. **Gestionar servicio**:
   ```cmd
   # Ver estado
   nssm status Pato2HostAgent
   
   # Detener
   nssm stop Pato2HostAgent
   
   # Reiniciar
   nssm restart Pato2HostAgent
   
   # Desinstalar
   nssm remove Pato2HostAgent confirm
   ```

### Linux (systemd)

1. **Crear archivo de servicio**:
   ```bash
   sudo nano /etc/systemd/system/pato2-host.service
   ```

2. **Configurar servicio**:
   ```ini
   [Unit]
   Description=Pato2 Host Agent
   After=network.target
   
   [Service]
   Type=simple
   User=tu_usuario
   WorkingDirectory=/home/tu_usuario/Pato2/host-agent
   Environment=PATH=/home/tu_usuario/Pato2/host-agent/venv/bin
   ExecStart=/home/tu_usuario/Pato2/host-agent/venv/bin/python host_agent.py
   Restart=always
   RestartSec=10
   
   [Install]
   WantedBy=multi-user.target
   ```

3. **Activar servicio**:
   ```bash
   # Recargar systemd
   sudo systemctl daemon-reload
   
   # Habilitar inicio automático
   sudo systemctl enable pato2-host
   
   # Iniciar servicio
   sudo systemctl start pato2-host
   
   # Ver estado
   sudo systemctl status pato2-host
   
   # Ver logs
   sudo journalctl -u pato2-host -f
   ```

### macOS (launchd)

1. **Crear archivo plist**:
   ```bash
   nano ~/Library/LaunchAgents/com.pato2.hostagent.plist
   ```

2. **Configurar servicio**:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.pato2.hostagent</string>
       <key>ProgramArguments</key>
       <array>
           <string>/usr/local/bin/python3</string>
           <string>/Users/tu_usuario/Pato2/host-agent/host_agent.py</string>
       </array>
       <key>WorkingDirectory</key>
       <string>/Users/tu_usuario/Pato2/host-agent</string>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   ```

3. **Cargar servicio**:
   ```bash
   # Cargar servicio
   launchctl load ~/Library/LaunchAgents/com.pato2.hostagent.plist
   
   # Iniciar servicio
   launchctl start com.pato2.hostagent
   
   # Ver estado
   launchctl list | grep pato2
   ```

## Scripts de Utilidad

### Windows (Batch)

```batch
REM start-host.bat
@echo off
cd /d "C:\ruta\a\Pato2\host-agent"
call venv\Scripts\activate
python host_agent.py
pause

REM stop-host.bat
@echo off
taskkill /f /im python.exe
echo Host agent detenido

REM status-host.bat
@echo off
tasklist | findstr python.exe
if %errorlevel% == 0 (
    echo Host agent está ejecutándose
) else (
    echo Host agent no está ejecutándose
)
pause
```

### Linux/macOS (Bash)

```bash
#!/bin/bash
# start-host.sh
cd ~/Pato2/host-agent
source venv/bin/activate
python host_agent.py

#!/bin/bash
# stop-host.sh
pkill -f "python host_agent.py"
echo "Host agent detenido"

#!/bin/bash
# status-host.sh
if pgrep -f "python host_agent.py" > /dev/null; then
    echo "Host agent está ejecutándose"
    pgrep -f "python host_agent.py"
else
    echo "Host agent no está ejecutándose"
fi
```

## Monitoreo

### Logs del agente

```bash
# Ver logs en tiempo real
tail -f logs/host_agent.log

# Buscar errores
grep ERROR logs/host_agent.log

# Ver últimas 100 líneas
tail -n 100 logs/host_agent.log
```

### Monitoreo del servidor Minecraft

```bash
# Ver logs de Minecraft
tail -f minecraft-server/logs/latest.log

# Verificar proceso
ps aux | grep java

# Verificar puerto
netstat -tlnp | grep :25565
```

### Panel web

Acceder a `http://pato2.duckdns.org:5000` para:
- Ver estado del host
- Monitorear conexiones activas
- Ver métricas de rendimiento
- Gestionar backups

## Solución de Problemas

### Error: "No se puede conectar a Pato2"

1. **Verificar conectividad**:
   ```bash
   ping pato2.duckdns.org
   telnet pato2.duckdns.org 5000
   ```

2. **Verificar token**:
   - Comprobar que `PATO2_TOKEN` coincide con el servidor

3. **Verificar firewall**:
   - Permitir conexiones salientes en puerto 5000

### Error: "Servidor Minecraft no inicia"

1. **Verificar Java**:
   ```bash
   java -version
   ```

2. **Verificar memoria**:
   - Reducir `-Xmx` en `MINECRAFT_JAVA_ARGS`

3. **Verificar puerto**:
   ```bash
   netstat -tlnp | grep :25565
   ```

### Error: "Backup falló"

1. **Verificar credenciales de Google Drive**
2. **Comprobar permisos de archivos**
3. **Verificar espacio en disco**

## Seguridad

### Firewall

**Windows**:
```cmd
# Permitir conexiones salientes
netsh advfirewall firewall add rule name="Pato2 Host Agent" dir=out action=allow protocol=TCP localport=5000
```

**Linux**:
```bash
# UFW
sudo ufw allow out 5000/tcp

# iptables
sudo iptables -A OUTPUT -p tcp --dport 5000 -j ACCEPT
```

### Antivirus

- **Agregar excepción** para la carpeta del proyecto
- **Permitir conexiones** de Python y Java

## Verificación Final

### Lista de verificación

- [ ] Python instalado y funcionando
- [ ] Repositorio clonado correctamente
- [ ] Entorno virtual creado y activado
- [ ] Dependencias instaladas
- [ ] Archivo `.env` configurado
- [ ] Servidor Minecraft configurado
- [ ] Conexión a Pato2 exitosa
- [ ] Host aparece como activo en panel web
- [ ] Servicio configurado (opcional)
- [ ] Scripts de utilidad creados

### Comandos de prueba

```bash
# Probar conexión
python host_agent.py --test-connection

# Verificar configuración
python host_agent.py --check-config

# Probar backup (si está configurado)
python host_agent.py --test-backup
```

## Siguientes Pasos

1. **[Configurar Google Drive](google-drive.md)** para backups automáticos
2. **[Configurar red avanzada](network-setup.md)** si es necesario
3. **[Leer manual para hosts](../user-guide/host-guide.md)**
4. **[Configurar múltiples hosts](../configuration/advanced.md)** si tienes varios PCs

## Soporte

- **Documentación**: [docs.pato2.example.com](https://docs.pato2.example.com)
- **Issues**: [GitHub Issues](https://github.com/Manel-Romero/pato2/issues)
- **Comunidad**: [Discord Server](#)