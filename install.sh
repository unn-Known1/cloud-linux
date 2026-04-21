#!/bin/bash
###############################################################################
# Cloud Linux - One Command Full Desktop                                      #
# Get a complete Linux system accessible from any browser                    #
# Usage: curl -sL <raw_url> | bash                                            #
###############################################################################

set -e

# Configuration
PORT=8080
VNC_PORT=5901
DISPLAY_NUM=1
RESOLUTION="1920x1080x24"
INSTALL_DIR="/opt/cloud-linux"
NOVNC_DIR="$INSTALL_DIR/noVNC"
LOG_DIR="/var/log/cloud-linux"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    warn "Not running as root - some features may be limited"
fi

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        OS="unknown"
    fi
    log "Detected OS: $OS"
}

# Install dependencies
install_deps() {
    log "Installing system dependencies..."
    
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq curl wget git xfvb xvfb tightvncserver novnc websockify python3 nginx supervisor >/dev/null 2>&1 || true
    elif command -v yum &>/dev/null; then
        yum install -y -q curl wget git xorg-x11-server-Xvfb tigervnc-server novnc python3 >/dev/null 2>&1 || true
    elif command -v dnf &>/dev/null; then
        dnf install -y -q curl wget git xorg-x11-server-Xvfb tigervnc-server novnc python3 >/dev/null 2>&1 || true
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm curl wget git xorg-server xvfb tigervnc novnc python3 >/dev/null 2>&1 || true
    fi
    
    success "Dependencies installed"
}

# Create directories
create_dirs() {
    log "Creating directory structure..."
    mkdir -p "$INSTALL_DIR"/{logs,start}
    mkdir -p "$NOVNC_DIR"
    mkdir -p "$LOG_DIR"
    success "Directories created"
}

# Install noVNC
install_novnc() {
    log "Installing noVNC..."
    
    if [[ ! -d "$NOVNC_DIR" ]] || [[ ! -f "$NOVNC_DIR/vnc.html" ]]; then
        rm -rf "$NOVNC_DIR"
        git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || {
            curl -fsSL https://github.com/novnc/noVNC/archive/refs/heads/master.tar.gz -o /tmp/novnc.tar.gz
            tar -xzf /tmp/novnc.tar.gz -C /tmp/
            mv /tmp/noVNC-master "$NOVNC_DIR"
            rm -f /tmp/novnc.tar.gz
        }
    fi
    
    success "noVNC installed"
}

# Install bore tunnel
install_bore() {
    log "Installing bore tunnel..."
    
    if command -v bore &>/dev/null; then
        success "bore already installed"
        return
    fi
    
    BORE_VERSION="0.5.0"
    if curl -fsSL "https://github.com/ekzhang/bore/releases/download/v${BORE_VERSION}/bore-v${BORE_VERSION}-x86_64-unknown-linux-musl.tar.gz" -o /tmp/bore.tar.gz; then
        tar -xzf /tmp/bore.tar.gz -C /usr/local/bin/
        chmod +x /usr/local/bin/bore
        rm -f /tmp/bore.tar.gz
        success "bore installed"
    else
        warn "bore installation failed - using serveo as fallback"
    fi
}

# Create start script
create_start_script() {
    log "Creating start script..."
    
    cat > "$INSTALL_DIR/start.sh" << 'STARTSCRIPT'
#!/bin/bash
export DISPLAY=:1

# Kill existing
pkill -f Xvfb 2>/dev/null || true
pkill -f vncserver 2>/dev/null || true
pkill -f novnc_proxy 2>/dev/null || true
sleep 1

# Start Xvfb
Xvfb :1 -screen 0 1920x1080x24 +extension GLX +extension RANDR +extension RENDER -nolisten tcp +extension Composite &>/dev/null &
sleep 2

# Start VNC
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no &>/dev/null &
sleep 2

# Start noVNC
cd /opt/cloud-linux/noVNC
./utils/novnc_proxy --vnc 127.0.0.1:5901 --listen 0.0.0.0:8080 &>/dev/null &
sleep 2

echo "Cloud Linux started!"
STARTSCRIPT
    chmod +x "$INSTALL_DIR/start.sh"
    
    success "Start script created"
}

# Create tunnel script
create_tunnel_script() {
    log "Creating tunnel script..."
    
    cat > "$INSTALL_DIR/tunnel.sh" << 'TUNNELSCRIPT'
#!/bin/bash
echo "Starting Cloud Linux tunnel..."
echo ""

cleanup() {
    pkill -f "bore local" 2>/dev/null || true
}

trap cleanup EXIT

# Try bore first
if command -v bore &>/dev/null; then
    bore local 8080 --to bore.pub 2>&1 | while read line; do
        echo "$line"
        if echo "$line" | grep -qE "tcp://|localhost"; then
            echo ""
            echo "=================================================="
            echo "  Your Cloud Linux is ready!"
            echo "=================================================="
            echo ""
            echo "Open this URL in your browser:"
            if echo "$line" | grep -q "bore.pub"; then
                HOST=$(echo "$line" | grep -oP '\w+\.bore\.pub' | head -1)
                echo "Desktop: http://${HOST}/vnc.html"
                echo "Panel: http://${HOST}"
            fi
            echo ""
        fi
    done
else
    # Fallback to serveo
    ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -R 80:localhost:8080 serveo.net 2>&1 | while read line; do
        echo "$line"
        if echo "$line" | grep -q "Forwarding"; then
            URL=$(echo "$line" | grep -oP 'http://\K[a-z0-9-]+\.serveo\.net')
            if [[ -n "$URL" ]]; then
                echo ""
                echo "=================================================="
                echo "  Your Cloud Linux is ready!"
                echo "=================================================="
                echo ""
                echo "Desktop: http://${URL}/vnc.html"
                echo "Panel: http://${URL}"
                echo ""
            fi
        fi
    done
fi
TUNNELSCRIPT
    chmod +x "$INSTALL_DIR/tunnel.sh"
    
    success "Tunnel script created"
}

# Create systemd service
create_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/cloud-linux.service << 'SERVICE'
[Unit]
Description=Cloud Linux Browser Desktop
After=network.target

[Service]
Type=simple
ExecStart=/opt/cloud-linux/start.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable cloud-linux.service 2>/dev/null || true
    
    success "Service created"
}

# Create desktop config
create_desktop_config() {
    log "Configuring desktop..."
    
    mkdir -p ~/.vnc
    cat > ~/.vnc/xstartup << 'XSTARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_TYPE=x11
dbus-launch --exit-with-session startxfce4 &
XSTARTUP
    chmod +x ~/.vnc/xstartup
    
    # Install XFCE if available
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xfce4 xfce4-goodies xfce4-terminal 2>/dev/null || true
    fi
    
    success "Desktop configured"
}

# Start all services
start_services() {
    log "Starting Cloud Linux services..."
    
    # Kill existing
    pkill Xvfb 2>/dev/null || true
    pkill vncserver 2>/dev/null || true
    pkill novnc 2>/dev/null || true
    sleep 1
    
    # Start Xvfb
    export DISPLAY=:1
    Xvfb :1 -screen 0 1920x1080x24 +extension GLX +extension RANDR +extension RENDER -nolisten tcp +extension Composite &>/dev/null &
    sleep 2
    
    # Start VNC
    vncserver :1 -geometry 1920x1080 -depth 24 -localhost no &>/dev/null &
    sleep 2
    
    # Start noVNC
    cd "$NOVNC_DIR"
    ./utils/novnc_proxy --vnc 127.0.0.1:5901 --listen 0.0.0.0:8080 &>/dev/null &
    sleep 2
    
    success "All services started!"
}

# Main installation
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║        Cloud Linux - One Command Install          ║"
    echo "║    Full Linux Desktop in Your Browser            ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    
    detect_os
    install_deps
    create_dirs
    install_novnc
    install_bore
    create_desktop_config
    create_start_script
    create_tunnel_script
    create_service
    start_services
    
    echo ""
    echo "╔═══════════════════════════════════════════════════╗"
    echo -e "${GREEN}║        Installation Complete!                  ║${NC}"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    echo "Your Cloud Linux is ready!"
    echo ""
    echo "Local Access:"
    echo "  Desktop: http://localhost:8080/vnc.html"
    echo "  Panel: http://localhost:8080"
    echo ""
    echo "For global access, run:"
    echo "  /opt/cloud-linux/tunnel.sh"
    echo ""
    echo "To stop: pkill -f 'Xvfb|vncserver|novnc'"
    echo ""
}

main "$@"
