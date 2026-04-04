#!/bin/bash
# install.sh - Master installer for PiUSB Drive Server
# Run as root: sudo ./install.sh

set -e

INSTALL_DIR="/opt/piusb"
CONFIG_FILE="/etc/piusb.conf"
PIUSB_IMAGE="/piusb.bin"
PIUSB_IMAGE_SIZE=4096  # MB
PIUSB_MOUNT="/mnt/piusb"
PIUSB_WEB_PORT=8080

echo "=============================="
echo " PiUSB Drive Server Installer"
echo "=============================="

# Check we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo ./install.sh"
    exit 1
fi

# Check we're on a Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null && \
   ! grep -q "BCM" /proc/cpuinfo 2>/dev/null; then
    echo "WARNING: This does not appear to be a Raspberry Pi."
    echo "The USB gadget features require a Pi Zero (W/2W)."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ---- 1. Install system dependencies ----
echo ""
echo "[1/7] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip dosfstools

# ---- 2. Write configuration file ----
echo "[2/7] Writing configuration to $CONFIG_FILE..."
cat > "$CONFIG_FILE" <<EOF
# PiUSB Drive Server Configuration
PIUSB_IMAGE=$PIUSB_IMAGE
PIUSB_IMAGE_SIZE=$PIUSB_IMAGE_SIZE
PIUSB_MOUNT=$PIUSB_MOUNT
PIUSB_WEB_PORT=$PIUSB_WEB_PORT
EOF

# ---- 3. Enable dwc2 overlay (USB gadget mode) ----
echo "[3/7] Enabling USB gadget mode (dwc2)..."

# Add dtoverlay=dwc2 to /boot/firmware/config.txt (or /boot/config.txt for older OS)
BOOT_CONFIG=""
if [ -f /boot/firmware/config.txt ]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    BOOT_CONFIG="/boot/config.txt"
fi

if [ -n "$BOOT_CONFIG" ]; then
    if ! grep -q "^dtoverlay=dwc2" "$BOOT_CONFIG"; then
        echo "dtoverlay=dwc2" >> "$BOOT_CONFIG"
        echo "  Added dtoverlay=dwc2 to $BOOT_CONFIG"
    else
        echo "  dtoverlay=dwc2 already in $BOOT_CONFIG"
    fi
fi

# Add dwc2 to /etc/modules if not present
if ! grep -q "^dwc2" /etc/modules 2>/dev/null; then
    echo "dwc2" >> /etc/modules
    echo "  Added dwc2 to /etc/modules"
fi

# ---- 4. Create the disk image ----
echo "[4/7] Creating disk image..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/scripts/create_image.sh" "$PIUSB_IMAGE_SIZE" "$PIUSB_IMAGE"

# ---- 5. Install application files ----
echo "[5/7] Installing application to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/web" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/scripts/"*.sh

# Create Python virtual environment and install Flask
echo "  Setting up Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet flask

# Create mount point
mkdir -p "$PIUSB_MOUNT"

# ---- 6. Install systemd services ----
echo "[6/7] Installing systemd services..."
cp "$SCRIPT_DIR/systemd/piusb-gadget.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/piusb-web.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable piusb-gadget.service
systemctl enable piusb-web.service

# ---- 7. Done ----
echo "[7/7] Installation complete!"
echo ""
echo "=============================="
echo " Next steps:"
echo "=============================="
echo ""
echo "  1. Reboot the Pi:  sudo reboot"
echo ""
echo "  2. Connect the Pi's USB port (not PWR) to your host device."
echo "     It will appear as a USB thumb drive."
echo ""
echo "  3. Open http://$(hostname -I | awk '{print $1}'):$PIUSB_WEB_PORT"
echo "     in your browser to manage files."
echo ""
echo "  Config file: $CONFIG_FILE"
echo "  Disk image:  $PIUSB_IMAGE (${PIUSB_IMAGE_SIZE}MB)"
echo "  Web port:    $PIUSB_WEB_PORT"
echo ""
