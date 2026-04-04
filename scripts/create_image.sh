#!/bin/bash
# create_image.sh - Create and format a FAT32 disk image for USB mass storage
# Usage: create_image.sh [size_in_mb] [image_path]

set -e

CONFIG_FILE="/etc/piusb.conf"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

SIZE_MB="${1:-${PIUSB_IMAGE_SIZE:-4096}}"
IMAGE_PATH="${2:-${PIUSB_IMAGE:-/piusb.bin}}"

if [ -f "$IMAGE_PATH" ]; then
    echo "Disk image already exists at $IMAGE_PATH"
    echo "To recreate, remove it first: sudo rm $IMAGE_PATH"
    exit 0
fi

echo "Creating ${SIZE_MB}MB disk image at $IMAGE_PATH..."
dd if=/dev/zero of="$IMAGE_PATH" bs=1M count="$SIZE_MB" status=progress

echo "Formatting as FAT32..."
mkfs.vfat -F 32 -n "PIUSBDRIVE" "$IMAGE_PATH"

echo "Disk image created and formatted successfully."
echo "  Path: $IMAGE_PATH"
echo "  Size: ${SIZE_MB}MB"
echo "  Format: FAT32"
