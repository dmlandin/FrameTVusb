#!/bin/bash
# mount_image.sh - Mount or unmount the USB disk image for local file management
# Usage: mount_image.sh mount|unmount|status

set -e

CONFIG_FILE="/etc/piusb.conf"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

PIUSB_IMAGE="${PIUSB_IMAGE:-/piusb.bin}"
PIUSB_MOUNT="${PIUSB_MOUNT:-/mnt/piusb}"
GADGET_LUN="/sys/kernel/config/usb_gadget/piusb/functions/mass_storage.0/lun.0/file"
GADGET_EJECT="/sys/kernel/config/usb_gadget/piusb/functions/mass_storage.0/lun.0/forced_eject"

is_exported() {
    if [ -f "$GADGET_LUN" ] && [ -n "$(cat "$GADGET_LUN" 2>/dev/null)" ]; then
        return 0
    fi
    return 1
}

is_mounted() {
    mountpoint -q "$PIUSB_MOUNT" 2>/dev/null
}

do_mount() {
    if is_mounted; then
        echo "Already mounted at $PIUSB_MOUNT"
        return 0
    fi

    # Eject from USB host first
    if is_exported; then
        echo "Ejecting from USB host..."
        echo 1 > "$GADGET_EJECT"
        sleep 1
    fi

    mkdir -p "$PIUSB_MOUNT"
    mount -o loop "$PIUSB_IMAGE" "$PIUSB_MOUNT"
    echo "Mounted $PIUSB_IMAGE at $PIUSB_MOUNT"
}

do_unmount() {
    if ! is_mounted; then
        echo "Not currently mounted"
    else
        umount "$PIUSB_MOUNT"
        echo "Unmounted $PIUSB_MOUNT"
    fi

    # Re-export to USB host
    if [ -f "$GADGET_LUN" ]; then
        echo "$PIUSB_IMAGE" > "$GADGET_LUN"
        echo "Re-exported image to USB host"
    fi
}

do_status() {
    echo "Image: $PIUSB_IMAGE"
    if is_mounted; then
        echo "Local mount: MOUNTED at $PIUSB_MOUNT"
    else
        echo "Local mount: NOT MOUNTED"
    fi
    if is_exported; then
        echo "USB export: ACTIVE (host sees the drive)"
    else
        echo "USB export: INACTIVE"
    fi
}

case "${1:-status}" in
    mount)   do_mount ;;
    unmount) do_unmount ;;
    status)  do_status ;;
    *)
        echo "Usage: $0 {mount|unmount|status}"
        exit 1
        ;;
esac
