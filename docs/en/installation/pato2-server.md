# Pato2 Server Installation (Termux)

Complete guide to install and configure the Pato2 server on Android using Termux.

## Prerequisites

### Hardware
- **Android device** with Android 7.0+ (API 24+)
- **RAM**: Minimum 4GB (8GB recommended)
- **Storage**: 5GB free space
- **Stable internet connection**

### Software
- **Termux** app from F-Droid or Google Play
- **Basic knowledge** of Linux commands

## Environment Setup

### Install Termux

1. **Download Termux**:
   - **Recommended**: [F-Droid](https://f-droid.org/packages/com.termux/)
   - Alternative: [Google Play](https://play.google.com/store/apps/details?id=com.termux)

2. **Grant permissions**:
   - Storage access
   - Network access
   - Background execution

### Update Termux

```bash
# Update package lists
pkg update && pkg upgrade

# Install essential packages
pkg install curl wget git nodejs npm openssh net-tools
```

### Install Node.js

```bash
# Verify Node.js installation
node --version
npm --version

# If not installed or outdated
pkg install nodejs-lts
```

## Download and Installation

### Automatic Method

1. **Download installation script**:
   ```bash
curl -O https://raw.githubusercontent.com/Manel-Romero/pato2/main/scripts/install-pato2-server.sh
```

2. **Make executable and run**:
   ```bash
   chmod +x install-pato2-server.sh
   ./install-pato2-server.sh
   ```

### Manual Method

1. **Clone repository**:
   ```bash
   git clone https://github.com/Manel-Romero/pato2.git
   cd pato2/pato2-server
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Copy environment configuration**:
   ```bash
   cp .env.example .env
   ```

## Configuration

### Environment Variables

Edit the `.env` file:

```bash
nano .env
```

### Basic Configuration

```env
# Server Configuration
PORT=5000
NODE_ENV=production
DOMAIN=pato2.duckdns.org

# Security
JWT_SECRET=your_super_secure_jwt_secret_here
HOST_TOKEN=shared_token_for_hosts

# Host Management
MAX_HOSTS=10
HOST_TIMEOUT=300000
HEARTBEAT_INTERVAL=30000

# Logging
LOG_LEVEL=info
LOG_FILE=./logs/pato2-server.log

# Optional Services
REDIS_URL=redis://localhost:6379
DATABASE_URL=sqlite:./data/pato2.db

# Monitoring (Optional)
ENABLE_METRICS=true
METRICS_PORT=9090

# SSL/TLS (Optional)
SSL_CERT_PATH=
SSL_KEY_PATH=
FORCE_HTTPS=false

# Backup Configuration
BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE=0 2 * * *

# Performance
MAX_CONNECTIONS=100
REQUEST_TIMEOUT=30000
```

### Generate Secure Secrets

```bash
# Generate JWT secret
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"

# Generate host token
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

## Network Configuration

### DuckDNS Setup

1. **Create DuckDNS account**:
   - Go to [duckdns.org](https://www.duckdns.org)
   - Sign in with Google/GitHub
   - Create a subdomain (e.g., `pato2`)

2. **Configure dynamic DNS**:
   ```bash
   # Install DuckDNS updater
   mkdir ~/duckdns
   cd ~/duckdns
   
   # Create update script
   echo 'echo url="https://www.duckdns.org/update?domains=pato2&token=YOUR_TOKEN&ip=" | curl -k -o ~/duckdns/duck.log -K -' > duck.sh
   chmod +x duck.sh
   
   # Test update
   ./duck.sh
   cat duck.log  # Should show "OK"
   ```

3. **Schedule automatic updates**:
   ```bash
   # Install cron
   pkg install cronie
   
   # Add to crontab
   crontab -e
   # Add line: */5 * * * * ~/duckdns/duck.sh >/dev/null 2>&1
   
   # Start cron service
   crond
   ```

### Port Forwarding

Configure your router to forward port 5000:

1. **Access router admin panel** (usually 192.168.1.1)
2. **Find Port Forwarding section**
3. **Add rule**:
   - External Port: 5000
   - Internal Port: 5000
   - Internal IP: Your Android device IP
   - Protocol: TCP

### Static IP (Optional)

```bash
# Find current IP
ip addr show wlan0

# Configure static IP in router DHCP settings
# Or use Android WiFi settings
```

## Server Startup

### First Run

```bash
# Navigate to project directory
cd ~/Pato2/pato2-server

# Start server
npm start
```

### Verify Installation

1. **Check logs**:
   ```
   [INFO] Pato2 Server starting...
   [INFO] Environment: production
   [INFO] Server listening on port 5000
   [INFO] WebSocket server ready
   [INFO] Database connected
   [INFO] Ready to accept host connections
   ```

2. **Test web interface**:
   - Local: `http://localhost:5000`
   - External: `http://pato2.duckdns.org:5000`

3. **Test API**:
   ```bash
   curl http://localhost:5000/api/health
   # Should return: {"status":"ok","uptime":...}
   ```

## Service Configuration (PM2)

### Install PM2

```bash
npm install -g pm2
```

### Configure PM2

1. **Create ecosystem file**:
   ```bash
   nano ecosystem.config.js
   ```

   ```javascript
   module.exports = {
     apps: [{
       name: 'pato2-server',
       script: 'server.js',
       cwd: '/data/data/com.termux/files/home/Pato2/pato2-server',
       instances: 1,
       exec_mode: 'fork',
       env: {
         NODE_ENV: 'production',
         PORT: 5000
       },
       log_file: './logs/combined.log',
       out_file: './logs/out.log',
       error_file: './logs/error.log',
       log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
       restart_delay: 4000,
       max_restarts: 10,
       min_uptime: '10s'
     }]
   };
   ```

2. **Start with PM2**:
   ```bash
   pm2 start ecosystem.config.js
   pm2 save
   pm2 startup
   ```

### PM2 Management

```bash
# View status
pm2 status

# View logs
pm2 logs pato2-server

# Restart
pm2 restart pato2-server

# Stop
pm2 stop pato2-server

# Monitor
pm2 monit
```

## Security

### Firewall Configuration

```bash
# Install iptables (if available)
pkg install iptables

# Allow SSH (port 8022)
iptables -A INPUT -p tcp --dport 8022 -j ACCEPT

# Allow Pato2 server (port 5000)
iptables -A INPUT -p tcp --dport 5000 -j ACCEPT

# Block other ports
iptables -A INPUT -p tcp --dport 1:4999 -j DROP
iptables -A INPUT -p tcp --dport 5001:65535 -j DROP
```

### Termux Auto-start

1. **Install Termux:Boot**:
   - Download from F-Droid
   - Grant auto-start permission

2. **Create startup script**:
   ```bash
   mkdir -p ~/.termux/boot
   nano ~/.termux/boot/start-pato2.sh
   ```

   ```bash
   #!/data/data/com.termux/files/usr/bin/bash
   
   # Wait for network
   sleep 30
   
   # Start DuckDNS updater
   ~/duckdns/duck.sh
   
   # Start Pato2 server
   cd ~/Pato2/pato2-server
   pm2 resurrect
   ```

3. **Make executable**:
   ```bash
   chmod +x ~/.termux/boot/start-pato2.sh
   ```

## Monitoring and Logs

### Log Management

```bash
# View real-time logs
tail -f logs/pato2-server.log

# Search for errors
grep ERROR logs/pato2-server.log

# View last 100 lines
tail -n 100 logs/pato2-server.log

# Rotate logs (weekly)
logrotate -f logrotate.conf
```

### System Monitoring

```bash
# Check system resources
top
htop  # if installed: pkg install htop

# Check disk usage
df -h

# Check memory usage
free -h

# Check network connections
netstat -tlnp | grep :5000
```

### Health Checks

```bash
# Create health check script
nano health-check.sh
```

```bash
#!/bin/bash

# Check if server is responding
if curl -f http://localhost:5000/api/health > /dev/null 2>&1; then
    echo "$(date): Server is healthy"
else
    echo "$(date): Server is down, restarting..."
    pm2 restart pato2-server
fi
```

```bash
# Make executable and schedule
chmod +x health-check.sh

# Add to crontab (every 5 minutes)
crontab -e
# Add: */5 * * * * ~/Pato2/pato2-server/health-check.sh >> ~/health-check.log 2>&1
```

## Troubleshooting

### Common Errors

#### "Port 5000 already in use"

```bash
# Find process using port
netstat -tlnp | grep :5000
lsof -i :5000  # if available

# Kill process
kill -9 PID_NUMBER

# Or use different port in .env
PORT=5001
```

#### "Cannot connect to database"

```bash
# Check SQLite file permissions
ls -la data/pato2.db

# Recreate database
rm data/pato2.db
npm run migrate
```

#### "WebSocket connection failed"

```bash
# Check firewall rules
iptables -L

# Verify port forwarding
telnet pato2.duckdns.org 5000
```

#### "DuckDNS not updating"

```bash
# Check DuckDNS log
cat ~/duckdns/duck.log

# Test manual update
curl "https://www.duckdns.org/update?domains=pato2&token=YOUR_TOKEN&ip="

# Verify cron is running
ps aux | grep cron
```

### Performance Issues

```bash
# Check Node.js memory usage
pm2 monit

# Increase memory limit if needed
node --max-old-space-size=2048 server.js

# Check for memory leaks
npm install -g clinic
clinic doctor -- node server.js
```

### Network Issues

```bash
# Test internal connectivity
curl http://localhost:5000/api/health

# Test external connectivity
curl http://pato2.duckdns.org:5000/api/health

# Check DNS resolution
nslookup pato2.duckdns.org

# Trace network path
traceroute pato2.duckdns.org
```

## Final Verification

### Verification Checklist

- [ ] Termux installed and updated
- [ ] Node.js and npm working
- [ ] Repository cloned successfully
- [ ] Dependencies installed
- [ ] Environment variables configured
- [ ] DuckDNS domain configured
- [ ] Port forwarding configured
- [ ] Server starts without errors
- [ ] Web interface accessible
- [ ] API endpoints responding
- [ ] PM2 service configured
- [ ] Auto-start configured
- [ ] Logs are being generated

### Test Commands

```bash
# Test server health
curl http://localhost:5000/api/health

# Test WebSocket connection
wscat -c ws://localhost:5000/ws/test

# Test external access
curl http://pato2.duckdns.org:5000/api/health

# Check PM2 status
pm2 status

# Verify auto-start
pm2 startup
pm2 save
```

## Next Steps

1. **[Install Host Agent](host-agent.md)** on your PC
2. **[Configure Google Drive](google-drive.md)** for backups
3. **[Read User Guide](../user-guide/player-guide.md)**
4. **[Advanced Configuration](../configuration/advanced.md)**

## Support

- **Documentation**: [docs.pato2.example.com](https://docs.pato2.example.com)
- **Issues**: [GitHub Issues](https://github.com/Manel-Romero/pato2/issues)
- **Community**: [Discord Server](#)