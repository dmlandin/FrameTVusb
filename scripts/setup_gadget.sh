#!/bin/bash
# setup_gadget.sh - Configure USB mass storage gadget using configfs
# This script is run at boot by piusb-gadget.service

set -e

CONFIG_FILE="/etc/piusb.conf"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

PIUSB_IMAGE="${PIUSB_IMAGE:-/piusb.bin}"

# Ensure the dwc2 overlay is loaded
if ! lsmod | grep -q dwc2; then
    modprobe dwc2
fi

if ! lsmod | grep -q libcomposite; then
    modprobe libcomposite
fi

GADGET_DIR="/sys/kernel/config/usb_gadget/piusb"

# Clean up any existing gadget config
if [ -d "$GADGET_DIR" ]; then
    # Disable the gadget first
    if [ -e "$GADGET_DIR/UDC" ]; then
        echo "" > "$GADGET_DIR/UDC" 2>/dev/null || true
    fi

    # Remove function from config
    rm -f "$GADGET_DIR/configs/c.1/mass_storage.0" 2>/dev/null || true

    # Remove strings
    rmdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null || true
    rmdir "$GADGET_DIR/configs/c.1" 2>/dev/null || true
    rmdir "$GADGET_DIR/functions/mass_storage.0" 2>/dev/null || true
    rmdir "$GADGET_DIR/strings/0x409" 2>/dev/null || true
    rmdir "$GADGET_DIR" 2>/dev/null || true
fi

# Check that the disk image exists
if [ ! -f "$PIUSB_IMAGE" ]; then
    echo "ERROR: Disk image $PIUSB_IMAGE not found. Run create_image.sh first."
    exit 1
fi

# Create the gadget
mkdir -p "$GADGET_DIR"
cd "$GADGET_DIR"

# Device descriptor
echo 0x1d6b > idVendor    # Linux Foundation
echo 0x0104 > idProduct   # Multifunction Composite Gadget
echo 0x0100 > bcdDevice   # v1.0.0
echo 0x0200 > bcdUSB      # USB2

# Device strings
mkdir -p strings/0x409
echo "fedcba9876543210" > strings/0x409/serialnumber
echo "Pi Zero USB"      > strings/0x409/manufacturer
echo "USB Drive"        > strings/0x409/product

# Configuration
mkdir -p configs/c.1/strings/0x409
echo "Config 1: Mass Storage" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

# Mass storage function
mkdir -p functions/mass_storage.0
echo 1 > functions/mass_storage.0/stall
echo 0 > functions/mass_storage.0/lun.0/cdrom
echo 0 > functions/mass_storage.0/lun.0/ro
echo 0 > functions/mass_storage.0/lun.0/nofua
echo 1 > functions/mass_storage.0/lun.0/removable
echo "$PIUSB_IMAGE" > functions/mass_storage.0/lun.0/file

# Link function to config
ln -s functions/mass_storage.0 configs/c.1/

# Enable the gadget by binding to the UDC driver
UDC=$(ls /sys/class/udc | head -n1)
if [ -z "$UDC" ]; then
    echo "ERROR: No UDC driver found. Is dwc2 overlay enabled?"
    exit 1
fi
echo "$UDC" > UDC

echo "USB mass storage gadget enabled with image: $PIUSB_IMAGE"
