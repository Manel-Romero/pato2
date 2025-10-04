#!/data/data/com.termux/files/usr/bin/bash

# Pato2 Server Installation Script for Termux
# This script automates the installation of Pato2 server on Android using Termux

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate random string
generate_random() {
    local length=${1:-32}
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c $length
}

# Welcome message
clear
echo "=============================================="
echo "    Pato2 Server Installation Script"
echo "=============================================="
echo ""
print_status "This script will install Pato2 server on Termux"
echo ""

# Check if running in Termux
if [ ! -d "/data/data/com.termux" ]; then
    print_error "This script must be run in Termux!"
    exit 1
fi

# Update packages
print_status "Updating Termux packages..."
pkg update -y && pkg upgrade -y

# Install required packages
print_status "Installing required packages..."
PACKAGES="nodejs npm git curl wget openssh net-tools"
for package in $PACKAGES; do
    if ! command_exists $package; then
        print_status "Installing $package..."
        pkg install $package -y
    else
        print_success "$package is already installed"
    fi
done

# Verify Node.js installation
print_status "Verifying Node.js installation..."
if command_exists node && command_exists npm; then
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    print_success "Node.js $NODE_VERSION and npm $NPM_VERSION are installed"
else
    print_error "Node.js or npm installation failed!"
    exit 1
fi

# Clone repository
REPO_URL="https://github.com/your-user/Pato2_TRAE.git"
INSTALL_DIR="$HOME/Pato2_TRAE"

if [ -d "$INSTALL_DIR" ]; then
    print_warning "Directory $INSTALL_DIR already exists"
    read -p "Do you want to remove it and reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        print_status "Removed existing directory"
    else
        print_error "Installation cancelled"
        exit 1
    fi
fi

print_status "Cloning Pato2 repository..."
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR/pato2-server"

# Install Node.js dependencies
print_status "Installing Node.js dependencies..."
npm install

# Create logs directory
mkdir -p logs

# Configure environment
print_status "Setting up environment configuration..."
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        print_success "Created .env from .env.example"
    else
        print_warning ".env.example not found, creating basic .env"
        cat > .env << EOF
# Server Configuration
PORT=5000
NODE_ENV=production
DOMAIN=pato2.duckdns.org

# Security
JWT_SECRET=$(generate_random 64)
HOST_TOKEN=$(generate_random 32)

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

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090

# Performance
MAX_CONNECTIONS=100
REQUEST_TIMEOUT=30000
EOF
    fi
else
    print_warning ".env file already exists, skipping creation"
fi

# Generate secure secrets if they don't exist
print_status "Generating secure secrets..."
if ! grep -q "JWT_SECRET=" .env || grep -q "JWT_SECRET=$" .env; then
    JWT_SECRET=$(generate_random 64)
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
    print_success "Generated JWT secret"
fi

if ! grep -q "HOST_TOKEN=" .env || grep -q "HOST_TOKEN=$" .env; then
    HOST_TOKEN=$(generate_random 32)
    sed -i "s/HOST_TOKEN=.*/HOST_TOKEN=$HOST_TOKEN/" .env
    print_success "Generated host token"
fi

# Install PM2 globally
print_status "Installing PM2 process manager..."
npm install -g pm2

# Create PM2 ecosystem file
print_status "Creating PM2 configuration..."
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'pato2-server',
    script: 'server.js',
    cwd: '$PWD',
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
EOF

# Setup auto-start
print_status "Setting up auto-start configuration..."
mkdir -p ~/.termux/boot

cat > ~/.termux/boot/start-pato2.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash

# Wait for network
sleep 30

# Start Pato2 server
cd $PWD
pm2 resurrect
EOF

chmod +x ~/.termux/boot/start-pato2.sh

# Create utility scripts
print_status "Creating utility scripts..."

# Start script
cat > start-server.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
pm2 start ecosystem.config.js
echo "Pato2 server started"
pm2 status
EOF

# Stop script
cat > stop-server.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
pm2 stop pato2-server
echo "Pato2 server stopped"
EOF

# Status script
cat > status-server.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
echo "=== PM2 Status ==="
pm2 status
echo ""
echo "=== Server Health ==="
curl -s http://localhost:5000/api/health || echo "Server not responding"
echo ""
echo "=== Port Status ==="
netstat -tlnp | grep :5000 || echo "Port 5000 not listening"
EOF

# Update script
cat > update-server.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
echo "Stopping server..."
pm2 stop pato2-server
echo "Updating repository..."
git pull
echo "Installing dependencies..."
npm install
echo "Starting server..."
pm2 start pato2-server
echo "Update completed"
pm2 status
EOF

# Make scripts executable
chmod +x *.sh

# Test installation
print_status "Testing installation..."
if npm test 2>/dev/null; then
    print_success "Installation test passed"
else
    print_warning "Installation test failed or not available"
fi

# Start server for the first time
print_status "Starting Pato2 server for the first time..."
pm2 start ecosystem.config.js
pm2 save

# Wait a moment for server to start
sleep 5

# Check if server is running
if pm2 list | grep -q "pato2-server.*online"; then
    print_success "Pato2 server is running!"
else
    print_error "Failed to start Pato2 server"
    print_status "Check logs with: pm2 logs pato2-server"
fi

# Display final information
echo ""
echo "=============================================="
echo "    Installation Complete!"
echo "=============================================="
echo ""
print_success "Pato2 server has been installed successfully!"
echo ""
echo "Configuration:"
echo "  - Installation directory: $PWD"
echo "  - Configuration file: .env"
echo "  - Logs directory: logs/"
echo ""
echo "Management commands:"
echo "  - Start server: ./start-server.sh"
echo "  - Stop server: ./stop-server.sh"
echo "  - Check status: ./status-server.sh"
echo "  - Update server: ./update-server.sh"
echo ""
echo "PM2 commands:"
echo "  - pm2 status"
echo "  - pm2 logs pato2-server"
echo "  - pm2 restart pato2-server"
echo "  - pm2 monit"
echo ""
echo "Access your server:"
echo "  - Local: http://localhost:5000"
echo "  - External: http://your-domain:5000"
echo ""
print_warning "IMPORTANT: Configure your .env file with your domain and settings!"
print_warning "IMPORTANT: Set up port forwarding on your router for port 5000!"
print_warning "IMPORTANT: Install Termux:Boot for auto-start functionality!"
echo ""
echo "For detailed configuration, see:"
echo "  docs/en/installation/pato2-server.md"
echo ""
print_success "Happy hosting!"