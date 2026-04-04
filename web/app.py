#!/usr/bin/env python3
"""
PiUSB Web Interface - Manage files on the USB drive image via browser.
"""

import os
import shutil
import subprocess
import time
from pathlib import Path

from flask import (
    Flask, render_template, request, jsonify, send_file, redirect, url_for
)
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2GB max upload

# Load configuration
CONFIG = {
    'PIUSB_IMAGE': '/piusb.bin',
    'PIUSB_MOUNT': '/mnt/piusb',
    'PIUSB_WEB_PORT': '8080',
}

CONFIG_FILE = '/etc/piusb.conf'
if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, _, value = line.partition('=')
                CONFIG[key.strip()] = value.strip()

MOUNT_POINT = CONFIG['PIUSB_MOUNT']
IMAGE_PATH = CONFIG['PIUSB_IMAGE']
GADGET_LUN = '/sys/kernel/config/usb_gadget/piusb/functions/mass_storage.0/lun.0/file'


def is_mounted():
    """Check if the disk image is mounted locally."""
    result = subprocess.run(
        ['mountpoint', '-q', MOUNT_POINT],
        capture_output=True
    )
    return result.returncode == 0


def is_exported():
    """Check if the disk image is exported to the USB host."""
    try:
        with open(GADGET_LUN) as f:
            return bool(f.read().strip())
    except (FileNotFoundError, PermissionError):
        return False


def mount_image():
    """Mount the disk image locally (removes it from USB host)."""
    if is_mounted():
        return True, "Already mounted"

    # Remove from USB host first
    if is_exported():
        try:
            with open(GADGET_LUN, 'w') as f:
                f.write('')
            time.sleep(0.5)
        except (FileNotFoundError, PermissionError) as e:
            return False, f"Failed to unexport from USB: {e}"

    os.makedirs(MOUNT_POINT, exist_ok=True)
    result = subprocess.run(
        ['mount', '-o', 'loop', IMAGE_PATH, MOUNT_POINT],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        # Try to re-export on failure
        _export_to_host()
        return False, f"Mount failed: {result.stderr}"

    return True, "Mounted successfully"


def unmount_image():
    """Unmount the disk image and re-export to USB host."""
    if is_mounted():
        # Sync before unmounting
        subprocess.run(['sync'], capture_output=True)
        result = subprocess.run(
            ['umount', MOUNT_POINT],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            return False, f"Unmount failed: {result.stderr}"

    return _export_to_host()


def _export_to_host():
    """Re-export the image to the USB host."""
    try:
        with open(GADGET_LUN, 'w') as f:
            f.write(IMAGE_PATH)
        return True, "Exported to USB host"
    except (FileNotFoundError, PermissionError) as e:
        return True, f"Unmounted (gadget not available: {e})"


def safe_path(user_path):
    """Resolve a user-provided path safely within the mount point."""
    base = Path(MOUNT_POINT).resolve()
    target = (base / user_path).resolve()
    if not str(target).startswith(str(base)):
        return None
    return target


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/status')
def api_status():
    """Get current mount/export status."""
    mounted = is_mounted()
    exported = is_exported()

    # Get image size
    try:
        image_size = os.path.getsize(IMAGE_PATH)
    except OSError:
        image_size = 0

    # Get usage info if mounted
    usage = {}
    if mounted:
        stat = os.statvfs(MOUNT_POINT)
        usage = {
            'total': stat.f_blocks * stat.f_frsize,
            'free': stat.f_bfree * stat.f_frsize,
            'used': (stat.f_blocks - stat.f_bfree) * stat.f_frsize,
        }

    return jsonify({
        'mounted': mounted,
        'exported': exported,
        'image_path': IMAGE_PATH,
        'image_size': image_size,
        'mount_point': MOUNT_POINT,
        'usage': usage,
    })


@app.route('/api/mount', methods=['POST'])
def api_mount():
    """Mount the disk image locally for file management."""
    success, message = mount_image()
    return jsonify({'success': success, 'message': message})


@app.route('/api/unmount', methods=['POST'])
def api_unmount():
    """Unmount and re-export to USB host."""
    success, message = unmount_image()
    return jsonify({'success': success, 'message': message})


@app.route('/api/files')
@app.route('/api/files/<path:subpath>')
def api_list_files(subpath=''):
    """List files in a directory."""
    if not is_mounted():
        return jsonify({'error': 'Drive not mounted. Mount it first.'}), 400

    target = safe_path(subpath)
    if target is None:
        return jsonify({'error': 'Invalid path'}), 400

    if not target.exists():
        return jsonify({'error': 'Path not found'}), 404

    if not target.is_dir():
        return jsonify({'error': 'Not a directory'}), 400

    files = []
    try:
        for entry in sorted(target.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower())):
            stat = entry.stat()
            files.append({
                'name': entry.name,
                'is_dir': entry.is_dir(),
                'size': stat.st_size if not entry.is_dir() else 0,
                'modified': stat.st_mtime,
            })
    except PermissionError:
        return jsonify({'error': 'Permission denied'}), 403

    return jsonify({
        'path': subpath,
        'files': files,
    })


@app.route('/api/upload', methods=['POST'])
@app.route('/api/upload/<path:subpath>', methods=['POST'])
def api_upload(subpath=''):
    """Upload files to a directory."""
    if not is_mounted():
        return jsonify({'error': 'Drive not mounted'}), 400

    target = safe_path(subpath)
    if target is None:
        return jsonify({'error': 'Invalid path'}), 400

    if not target.is_dir():
        return jsonify({'error': 'Target is not a directory'}), 400

    uploaded = []
    for f in request.files.getlist('files'):
        if f.filename:
            filename = secure_filename(f.filename)
            if not filename:
                continue
            dest = target / filename
            f.save(str(dest))
            uploaded.append(filename)

    return jsonify({'success': True, 'uploaded': uploaded})


@app.route('/api/download/<path:subpath>')
def api_download(subpath):
    """Download a file."""
    if not is_mounted():
        return jsonify({'error': 'Drive not mounted'}), 400

    target = safe_path(subpath)
    if target is None:
        return jsonify({'error': 'Invalid path'}), 400

    if not target.exists():
        return jsonify({'error': 'File not found'}), 404

    if target.is_dir():
        return jsonify({'error': 'Cannot download a directory'}), 400

    return send_file(str(target), as_attachment=True, download_name=target.name)


@app.route('/api/delete', methods=['POST'])
def api_delete():
    """Delete a file or directory."""
    if not is_mounted():
        return jsonify({'error': 'Drive not mounted'}), 400

    data = request.get_json()
    if not data or 'path' not in data:
        return jsonify({'error': 'No path provided'}), 400

    target = safe_path(data['path'])
    if target is None:
        return jsonify({'error': 'Invalid path'}), 400

    if not target.exists():
        return jsonify({'error': 'Path not found'}), 404

    # Don't allow deleting the mount point itself
    if target == Path(MOUNT_POINT).resolve():
        return jsonify({'error': 'Cannot delete root'}), 400

    try:
        if target.is_dir():
            shutil.rmtree(str(target))
        else:
            target.unlink()
    except OSError as e:
        return jsonify({'error': str(e)}), 500

    return jsonify({'success': True})


@app.route('/api/rename', methods=['POST'])
def api_rename():
    """Rename a file or directory."""
    if not is_mounted():
        return jsonify({'error': 'Drive not mounted'}), 400

    data = request.get_json()
    if not data or 'path' not in data or 'new_name' not in data:
        return jsonify({'error': 'Missing path or new_name'}), 400

    target = safe_path(data['path'])
    if target is None:
        return jsonify({'error': 'Invalid path'}), 400

    if not target.exists():
        return jsonify({'error': 'Path not found'}), 404

    new_name = secure_filename(data['new_name'])
    if not new_name:
        return jsonify({'error': 'Invalid new name'}), 400

    new_path = target.parent / new_name
    new_resolved = safe_path(str(new_path.relative_to(Path(MOUNT_POINT).resolve())))
    if new_resolved is None:
        return jsonify({'error': 'Invalid new path'}), 400

    try:
        target.rename(new_path)
    except OSError as e:
        return jsonify({'error': str(e)}), 500

    return jsonify({'success': True, 'new_name': new_name})


@app.route('/api/mkdir', methods=['POST'])
def api_mkdir():
    """Create a new directory."""
    if not is_mounted():
        return jsonify({'error': 'Drive not mounted'}), 400

    data = request.get_json()
    if not data or 'path' not in data:
        return jsonify({'error': 'No path provided'}), 400

    target = safe_path(data['path'])
    if target is None:
        return jsonify({'error': 'Invalid path'}), 400

    if target.exists():
        return jsonify({'error': 'Already exists'}), 400

    try:
        target.mkdir(parents=True)
    except OSError as e:
        return jsonify({'error': str(e)}), 500

    return jsonify({'success': True})


if __name__ == '__main__':
    port = int(CONFIG.get('PIUSB_WEB_PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
