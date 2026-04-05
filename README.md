# FrameTVusb - Raspberry Pi Zero USB Drive Server

Turn a Raspberry Pi Zero (W/2W) into a smart USB thumb drive. The host device
sees a standard USB mass storage device, while you manage files over WiFi
through a web interface.

## How It Works

```
[Host Device] <--USB cable--> [Pi Zero USB port] (mass storage gadget)
                                    |
                                  [WiFi]
                                    |
                              [Web Interface]
                      http://<hostname>.local:8080
```

- A disk image file (`/piusb.bin`) is formatted as FAT32 and exposed to the
  host via the Linux USB gadget mass storage driver (`g_mass_storage`).
- The Pi connects to your WiFi network.
- A Flask web app lets you mount/unmount the image, browse files, upload,
  download, rename, and delete — all from your browser.

## Requirements

- Raspberry Pi Zero W, Zero 2 W, or Zero (with USB WiFi adapter)
- Raspberry Pi OS Lite (Bookworm) — the only supported OS at this time
- MicroSD card (8 GB+)
- USB data cable (micro-USB to USB-A) connected to the **USB** port (not PWR) (this is the port closest to the middle on Pi Zero W)
- [Raspberry Pi Imager](https://www.raspberrypi.com/software/) installed on your computer

## Quick Start

### 1. Flash the SD Card

Open **Raspberry Pi Imager** and configure:

- **Raspberry Pi Device**: Select your Pi model (e.g., Raspberry Pi Zero W)
- **Operating System**: Choose **Raspberry Pi OS (other)** → **Raspberry Pi OS Lite (32-bit)** (Bookworm, no desktop). Use 64-bit only if you have a Pi Zero 2 W.
- **Storage**: Select your MicroSD card

Before writing, click **Edit Settings** (or the gear icon) to configure:

- **Hostname**: Choose a name (e.g., `frametvusb`) — you'll use this to connect
- **Username and password**: Set your login credentials
- **Wireless LAN**: Enter your WiFi network name (SSID) and password
- **Wireless LAN country**: Select your country (e.g., `US`)
- **Locale settings**: Set your timezone and keyboard layout
- **Services tab**: Enable **SSH** (use password authentication)

Click **Save**, then **Write** to flash the SD card.

### 2. Boot and Connect

1. Insert the SD card into the Pi and power it on.
2. Wait 3–5 minutes for the first boot to complete.
3. SSH into the Pi from your computer:

```bash
ssh <username>@<hostname>.local
```

For example, if you set hostname `frametvusb` and username `admin`:

```bash
ssh admin@frametvusb.local
```

> **Note:** The `.local` address uses mDNS, which works out of the box on
> macOS, Linux, and Windows 10+. If it doesn't resolve, check your router's
> admin page for the Pi's IP address and use that instead.

### 3. Install FrameTVusb

```bash
sudo apt update && sudo apt install git -y
git clone https://github.com/dmlandin/frametvusb.git
cd frametvusb
sudo ./install.sh
```

### 4. Reboot

```bash
sudo reboot
```

### 5. Connect and Use

1. Plug the Pi's **USB** port (not PWR — the port closest to the middle) into
   your host device. It will appear as a USB thumb drive.
2. Open `http://<hostname>.local:8080` in your browser to manage files
   (e.g., `http://frametvusb.local:8080`).

## Project Structure

```
├── install.sh              # Master installer
├── scripts/
│   ├── setup_gadget.sh     # Configures USB mass storage gadget on boot
│   ├── create_image.sh     # Creates and formats the FAT32 disk image
│   └── mount_image.sh      # Mount/unmount helper for the disk image
├── web/
│   ├── app.py              # Flask web application
│   ├── templates/
│   │   └── index.html      # Web UI
│   └── static/
│       ├── css/style.css
│       └── js/app.js
├── systemd/
│   ├── piusb-gadget.service    # Starts USB gadget on boot
│   └── piusb-web.service       # Starts web interface on boot
└── README.md
```

## Web Interface Features

- Browse files and directories on the USB drive
- Upload files (drag & drop supported)
- Download, rename, and delete files
- Create new directories
- Safely unmount from host before making changes, re-mount when done

## Important Notes

- **Mount safety**: The disk image cannot be mounted on the Pi and exposed to
  the host at the same time. The web UI handles this automatically — it
  unmounts from the host before making changes, then re-exports when done.
- **USB port**: Use the port labeled "USB" (not "PWR") on the Pi Zero.
- The default disk image size is **4 GB**. Change this in `install.sh` or
  by running `scripts/create_image.sh` with a custom size.

## Configuration

Edit `/etc/piusb.conf` after install:

```bash
PIUSB_IMAGE=/piusb.bin       # Path to disk image
PIUSB_IMAGE_SIZE=4096        # Size in MB (only used on creation)
PIUSB_MOUNT=/mnt/piusb       # Mount point for file management
PIUSB_WEB_PORT=8080          # Web interface port
```

## License

MIT
