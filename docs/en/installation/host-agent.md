# Host Agent Installation (PC)

Complete guide to install and configure the Pato2 host agent on your PC.

## Prerequisites

### Hardware
- **PC with Windows 10/11, Linux or macOS**
- **RAM**: Minimum 4GB (8GB recommended)
- **Storage**: 10GB free for Minecraft + worlds
- **Stable internet connection**

### Software
- **Python 3.7** or higher
- **Git** to clone the repository
- **Minecraft server** (can be downloaded automatically)

## Python Installation

### Windows

1. **Download Python**:
   - Go to https://python.org/downloads/
   - Download Python 3.11 or higher
   - **IMPORTANT**: Check "Add Python to PATH" during installation

2. **Verify installation**:
   ```cmd
   python --version
   pip --version
   ```

### Linux (Ubuntu/Debian)

```bash
# Update system
sudo apt update && sudo apt upgrade

# Install Python and pip
sudo apt install python3 python3-pip python3-venv git

# Verify installation
python3 --version
pip3 --version
```

### macOS

```bash
# Install Homebrew if not installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Python
brew install python git

# Verify installation
python3 --version
pip3 --version
```

## Download and Installation

### Automatic Method (Windows)

1. **Download installation script**:
   ```cmd
   curl -O https://raw.githubusercontent.com/Manel-Romero/pato2/main/scripts/install-host-agent.bat
   ```

2. **Run as administrator**:
   ```cmd
   install-host-agent.bat
   ```

### Manual Method

1. **Clone repository**:
   ```bash
   git clone https://github.com/Manel-Romero/pato2.git
   cd pato2/host-agent
   ```

2. **Create virtual environment**:
   ```bash
   # Windows
   python -m venv venv
   venv\Scripts\activate

   # Linux/macOS
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Configuration

### Environment Variables

1. **Copy example file**:
   ```bash
   cp .env.example .env
   ```

2. **Edit configuration**:
   ```bash
   # Windows
   notepad .env

   # Linux/macOS
   nano .env
   ```

### Basic Configuration

```env
# Pato2 Connection
PATO2_HOST=pato2.duckdns.org
PATO2_PORT=5000
PATO2_TOKEN=your_shared_host_token

# Host Information
HOST_NAME=MyPC-Gaming
HOST_DESCRIPTION=Gaming PC with RTX 4070

# Minecraft Server
MINECRAFT_DIR=./minecraft-server
MINECRAFT_PORT=25565
MINECRAFT_JAR=server.jar
MINECRAFT_WORLD=world
MINECRAFT_JAVA_ARGS=-Xmx4G -Xms2G

# Google Drive (Optional)
GOOGLE_DRIVE_FOLDER_ID=your_google_drive_folder_id
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REFRESH_TOKEN=your_refresh_token

# Backup Configuration
BACKUP_PATH=./backups
BACKUP_INTERVAL=3600  # 1 hour in seconds
BACKUP_RETENTION=7    # Days

# System
HEARTBEAT_INTERVAL=30  # seconds
RECONNECT_DELAY=5      # seconds
LOG_LEVEL=INFO
```

### Minecraft Server Configuration

1. **Create directory**:
   ```bash
   mkdir minecraft-server
   cd minecraft-server
   ```

2. **Download server** (example with 1.20.4):
   ```bash
   # Windows
   curl -O https://piston-data.mojang.com/v1/objects/8f3112a1049751cc472ec13e397eade5336ca7ae/server.jar

   # Linux/macOS
   wget https://piston-data.mojang.com/v1/objects/8f3112a1049751cc472ec13e397eade5336ca7ae/server.jar
   ```

3. **Accept EULA**:
   ```bash
   echo "eula=true" > eula.txt
   ```

4. **Configure server.properties**:
   ```properties
   # Basic configuration
   server-port=25565
   online-mode=true
   difficulty=normal
   gamemode=survival
   max-players=20
   motd=Pato2 Server
   
   # Network configuration
   server-ip=127.0.0.1
   enable-rcon=false
   
   # World configuration
   level-name=world
   level-type=minecraft:normal
   spawn-protection=16
   ```

## First Launch

### Test Pato2 connection

```bash
# Activate virtual environment
# Windows: venv\Scripts\activate
# Linux/macOS: source venv/bin/activate

# Test connection
python host_agent.py --test-connection
```

### Start agent

```bash
python host_agent.py
```

### Verify functionality

1. **Check logs**:
   ```
   [INFO] Connecting to Pato2 at pato2.duckdns.org:5000
   [INFO] Authentication successful
   [INFO] Offering host to server
   [INFO] Host accepted, starting Minecraft server
   [INFO] Minecraft server started on port 25565
   [INFO] Heartbeat sent successfully
   ```

2. **Verify on web panel**:
   - Go to `http://pato2.duckdns.org:5000`
   - Verify that your host appears as "Active"

## Configure as Service

### Windows (with NSSM)

1. **Download NSSM**:
   - Go to https://nssm.cc/download
   - Download and extract nssm.exe

2. **Install service**:
   ```cmd
   # Open CMD as administrator
   cd C:\path\to\Pato2\host-agent
   
   # Install service
   nssm install Pato2HostAgent
   
   # Configure service
   nssm set Pato2HostAgent Application "C:\path\to\python.exe"
   nssm set Pato2HostAgent AppParameters "C:\path\to\Pato2\host-agent\host_agent.py"
   nssm set Pato2HostAgent AppDirectory "C:\path\to\Pato2\host-agent"
   nssm set Pato2HostAgent DisplayName "Pato2 Host Agent"
   nssm set Pato2HostAgent Description "Host agent for Pato2 system"
   
   # Start service
   nssm start Pato2HostAgent
   ```

3. **Manage service**:
   ```cmd
   # View status
   nssm status Pato2HostAgent
   
   # Stop
   nssm stop Pato2HostAgent
   
   # Restart
   nssm restart Pato2HostAgent
   
   # Uninstall
   nssm remove Pato2HostAgent confirm
   ```

### Linux (systemd)

1. **Create service file**:
   ```bash
   sudo nano /etc/systemd/system/pato2-host.service
   ```

2. **Configure service**:
   ```ini
   [Unit]
   Description=Pato2 Host Agent
   After=network.target
   
   [Service]
   Type=simple
   User=your_user
   WorkingDirectory=/home/your_user/Pato2/host-agent
   Environment=PATH=/home/your_user/Pato2/host-agent/venv/bin
   ExecStart=/home/your_user/Pato2/host-agent/venv/bin/python host_agent.py
   Restart=always
   RestartSec=10
   
   [Install]
   WantedBy=multi-user.target
   ```

3. **Activate service**:
   ```bash
   # Reload systemd
   sudo systemctl daemon-reload
   
   # Enable auto-start
   sudo systemctl enable pato2-host
   
   # Start service
   sudo systemctl start pato2-host
   
   # View status
   sudo systemctl status pato2-host
   
   # View logs
   sudo journalctl -u pato2-host -f
   ```

### macOS (launchd)

1. **Create plist file**:
   ```bash
   nano ~/Library/LaunchAgents/com.pato2.hostagent.plist
   ```

2. **Configure service**:
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
           <string>/Users/your_user/Pato2/host-agent/host_agent.py</string>
       </array>
       <key>WorkingDirectory</key>
       <string>/Users/your_user/Pato2/host-agent</string>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   ```

3. **Load service**:
   ```bash
   # Load service
   launchctl load ~/Library/LaunchAgents/com.pato2.hostagent.plist
   
   # Start service
   launchctl start com.pato2.hostagent
   
   # View status
   launchctl list | grep pato2
   ```

## Utility Scripts

### Windows (Batch)

```batch
REM start-host.bat
@echo off
cd /d "C:\path\to\Pato2\host-agent"
call venv\Scripts\activate
python host_agent.py
pause

REM stop-host.bat
@echo off
taskkill /f /im python.exe
echo Host agent stopped

REM status-host.bat
@echo off
tasklist | findstr python.exe
if %errorlevel% == 0 (
    echo Host agent is running
) else (
    echo Host agent is not running
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
echo "Host agent stopped"

#!/bin/bash
# status-host.sh
if pgrep -f "python host_agent.py" > /dev/null; then
    echo "Host agent is running"
    pgrep -f "python host_agent.py"
else
    echo "Host agent is not running"
fi
```

## Monitoring

### Agent logs

```bash
# View logs in real time
tail -f logs/host_agent.log

# Search for errors
grep ERROR logs/host_agent.log

# View last 100 lines
tail -n 100 logs/host_agent.log
```

### Minecraft server monitoring

```bash
# View Minecraft logs
tail -f minecraft-server/logs/latest.log

# Check process
ps aux | grep java

# Check port
netstat -tlnp | grep :25565
```

### Web panel

Access `http://pato2.duckdns.org:5000` to:
- View host status
- Monitor active connections
- View performance metrics
- Manage backups

## Troubleshooting

### Error: "Cannot connect to Pato2"

1. **Verify connectivity**:
   ```bash
   ping pato2.duckdns.org
   telnet pato2.duckdns.org 5000
   ```

2. **Verify token**:
   - Check that `PATO2_TOKEN` matches the server

3. **Verify firewall**:
   - Allow outbound connections on port 5000

### Error: "Minecraft server won't start"

1. **Verify Java**:
   ```bash
   java -version
   ```

2. **Verify memory**:
   - Reduce `-Xmx` in `MINECRAFT_JAVA_ARGS`

3. **Verify port**:
   ```bash
   netstat -tlnp | grep :25565
   ```

### Error: "Backup failed"

1. **Verify Google Drive credentials**
2. **Check file permissions**
3. **Verify disk space**

## Security

### Firewall

**Windows**:
```cmd
# Allow outbound connections
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

- **Add exception** for the project folder
- **Allow connections** for Python and Java

## Final Verification

### Checklist

- [ ] Python installed and working
- [ ] Repository cloned correctly
- [ ] Virtual environment created and activated
- [ ] Dependencies installed
- [ ] `.env` file configured
- [ ] Minecraft server configured
- [ ] Pato2 connection successful
- [ ] Host appears as active on web panel
- [ ] Service configured (optional)
- [ ] Utility scripts created

### Test commands

```bash
# Test connection
python host_agent.py --test-connection

# Verify configuration
python host_agent.py --check-config

# Test backup (if configured)
python host_agent.py --test-backup
```

## Next Steps

1. **[Configure Google Drive](google-drive.md)** for automatic backups
2. **[Configure advanced networking](network-setup.md)** if necessary
3. **[Read host manual](../user-guide/host-guide.md)**
4. **[Configure multiple hosts](../configuration/advanced.md)** if you have multiple PCs

## Support

- **Documentation**: [docs.pato2.example.com](https://docs.pato2.example.com)
- **Issues**: [GitHub Issues](https://github.com/Manel-Romero/pato2/issues)
- **Community**: [Discord Server](#)