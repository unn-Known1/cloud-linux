# Cloud Linux - One Command Full Desktop

Get a complete, full-featured Linux desktop accessible from any browser with just **one command**.

## Quick Start

Run this single command on any Linux system:

```bash
curl -sL https://raw.githubusercontent.com/unn-Known1/cloud-linux/main/install.sh | bash
```

That's it! After installation, you'll get a URL to access your full Linux desktop from any browser.

## Features

- **Full Linux Desktop** - Complete XFCE desktop environment with all applications
- **Browser Access** - Works in Chrome, Firefox, Safari, Edge - even mobile browsers
- **NoVNC Technology** - Real-time graphical display via WebSocket/VNC
- **Global Access** - Uses tunnel services (bore.pub or serveo) to make accessible from anywhere
- **Single Command** - One curl command to install everything needed
- **Persistent Sessions** - Your files and work persist until you stop the service

## What You Get

- Virtual X11 display (Xvfb) running
- VNC server for remote desktop
- noVNC web interface for browser access
- Tunnel service for global accessibility

## Access Your Desktop

After installation, you'll receive URLs like:
- `http://xxx.bore.pub/vnc.html` - Full Linux desktop
- `http://xxx.bore.pub` - Web dashboard

## Manual Control

```bash
# Start services
/opt/cloud-linux/start.sh

# Start tunnel for global access
/opt/cloud-linux/tunnel.sh

# Stop services
pkill -f "Xvfb|vncserver|novnc"
```

## System Requirements

- Linux (Ubuntu, Debian, CentOS, Fedora, Arch)
- Root or sudo access
- Internet connection
- Any modern browser

## Port Usage

- Port 5901: VNC server
- Port 8080: Web interface (noVNC)
- Tunnel: Exposes port 8080 to internet

## License

MIT License
