// PiUSB Web Interface - Client-side JavaScript

let currentPath = '';
let isMonted = false;

// ---- API helpers ----

async function api(url, opts = {}) {
    const resp = await fetch(url, opts);
    return resp.json();
}

async function apiPost(url, body) {
    return api(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
}

// ---- Status ----

async function refreshStatus() {
    const data = await api('/api/status');
    const text = document.getElementById('status-text');
    const btn = document.getElementById('btn-mount');
    const usageContainer = document.getElementById('usage-bar-container');

    isMounted = data.mounted;

    if (data.mounted) {
        text.innerHTML = '<span class="indicator mounted"></span> Mounted locally (editing mode)';
        btn.textContent = 'Unmount & Export';
        btn.className = 'btn btn-danger';
        document.getElementById('toolbar').style.display = 'flex';

        // Show usage
        if (data.usage && data.usage.total > 0) {
            usageContainer.style.display = 'block';
            const pct = ((data.usage.used / data.usage.total) * 100).toFixed(1);
            document.getElementById('usage-fill').style.width = pct + '%';
            document.getElementById('usage-text').textContent =
                `${formatSize(data.usage.used)} used of ${formatSize(data.usage.total)} (${pct}%)`;
        }
    } else if (data.exported) {
        text.innerHTML = '<span class="indicator exported"></span> Exported to USB host';
        btn.textContent = 'Mount for Editing';
        btn.className = 'btn btn-primary';
        document.getElementById('toolbar').style.display = 'none';
        usageContainer.style.display = 'none';
    } else {
        text.innerHTML = '<span class="indicator offline"></span> Offline';
        btn.textContent = 'Mount for Editing';
        btn.className = 'btn btn-primary';
        document.getElementById('toolbar').style.display = 'none';
        usageContainer.style.display = 'none';
    }

    return data;
}

async function toggleMount() {
    const btn = document.getElementById('btn-mount');
    btn.disabled = true;
    btn.textContent = 'Working...';

    const status = await api('/api/status');
    let result;

    if (status.mounted) {
        result = await apiPost('/api/unmount');
    } else {
        result = await apiPost('/api/mount');
    }

    if (!result.success) {
        alert(result.message || result.error || 'Operation failed');
    }

    btn.disabled = false;
    await refreshStatus();
    await refreshFiles();
}

// ---- File listing ----

async function navigate(path) {
    currentPath = path;
    updateBreadcrumb();
    await refreshFiles();
}

function updateBreadcrumb() {
    const nav = document.getElementById('breadcrumb');
    let html = '<a href="#" onclick="navigate(\'\'); return false;">Root</a>';

    if (currentPath) {
        const parts = currentPath.split('/');
        let accumulated = '';
        for (const part of parts) {
            accumulated += (accumulated ? '/' : '') + part;
            const p = accumulated;
            html += `<span class="sep">/</span><a href="#" onclick="navigate('${escapeHtml(p)}'); return false;">${escapeHtml(part)}</a>`;
        }
    }

    nav.innerHTML = html;
}

async function refreshFiles() {
    const list = document.getElementById('file-list');
    const status = await api('/api/status');

    if (!status.mounted) {
        list.innerHTML = '<div class="empty-state">Mount the drive to browse files.</div>';
        return;
    }

    const url = currentPath ? `/api/files/${currentPath}` : '/api/files';
    const data = await api(url);

    if (data.error) {
        list.innerHTML = `<div class="empty-state">${escapeHtml(data.error)}</div>`;
        return;
    }

    if (data.files.length === 0) {
        list.innerHTML = '<div class="empty-state">This folder is empty.</div>';
        return;
    }

    let html = '';

    // Parent directory link
    if (currentPath) {
        const parent = currentPath.split('/').slice(0, -1).join('/');
        html += `
        <div class="file-item">
            <div class="file-icon">..</div>
            <div class="file-name">
                <a href="#" onclick="navigate('${escapeHtml(parent)}'); return false;">..</a>
            </div>
            <div class="file-size"></div>
            <div class="file-actions"></div>
        </div>`;
    }

    for (const f of data.files) {
        const filePath = currentPath ? `${currentPath}/${f.name}` : f.name;
        const icon = f.is_dir ? '\uD83D\uDCC1' : fileIcon(f.name);
        const size = f.is_dir ? '' : formatSize(f.size);

        let nameHtml;
        if (f.is_dir) {
            nameHtml = `<a href="#" onclick="navigate('${escapeHtml(filePath)}'); return false;">${escapeHtml(f.name)}</a>`;
        } else {
            nameHtml = `<a href="/api/download/${encodeURIPath(filePath)}" title="Download">${escapeHtml(f.name)}</a>`;
        }

        html += `
        <div class="file-item">
            <div class="file-icon">${icon}</div>
            <div class="file-name">${nameHtml}</div>
            <div class="file-size">${size}</div>
            <div class="file-actions">
                <button title="Rename" onclick="showRenameDialog('${escapeHtml(filePath)}', '${escapeHtml(f.name)}')">Ren</button>
                <button title="Delete" onclick="confirmDelete('${escapeHtml(filePath)}', '${escapeHtml(f.name)}')">Del</button>
            </div>
        </div>`;
    }

    list.innerHTML = html;
}

// ---- Upload ----

function showUploadDialog() {
    document.getElementById('upload-overlay').style.display = 'flex';
    document.getElementById('upload-progress').style.display = 'none';
}

function setupDropZone() {
    const zone = document.getElementById('drop-zone');
    const input = document.getElementById('file-input');

    zone.addEventListener('click', () => input.click());

    zone.addEventListener('dragover', (e) => {
        e.preventDefault();
        zone.classList.add('dragover');
    });

    zone.addEventListener('dragleave', () => {
        zone.classList.remove('dragover');
    });

    zone.addEventListener('drop', (e) => {
        e.preventDefault();
        zone.classList.remove('dragover');
        uploadFiles(e.dataTransfer.files);
    });

    input.addEventListener('change', () => {
        if (input.files.length > 0) {
            uploadFiles(input.files);
        }
    });
}

async function uploadFiles(fileList) {
    const progress = document.getElementById('upload-progress');
    const fill = document.getElementById('upload-fill');
    const status = document.getElementById('upload-status');

    progress.style.display = 'block';
    fill.style.width = '0%';
    status.textContent = `Uploading ${fileList.length} file(s)...`;

    const formData = new FormData();
    for (const f of fileList) {
        formData.append('files', f);
    }

    const url = currentPath ? `/api/upload/${currentPath}` : '/api/upload';

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);

    xhr.upload.onprogress = (e) => {
        if (e.lengthComputable) {
            const pct = (e.loaded / e.total * 100).toFixed(0);
            fill.style.width = pct + '%';
            status.textContent = `Uploading... ${pct}%`;
        }
    };

    xhr.onload = async () => {
        const data = JSON.parse(xhr.responseText);
        if (data.success) {
            status.textContent = `Uploaded: ${data.uploaded.join(', ')}`;
            fill.style.width = '100%';
            await refreshFiles();
            await refreshStatus();
        } else {
            status.textContent = `Error: ${data.error}`;
        }
    };

    xhr.onerror = () => {
        status.textContent = 'Upload failed.';
    };

    xhr.send(formData);
}

// ---- Mkdir ----

function showMkdirDialog() {
    document.getElementById('mkdir-overlay').style.display = 'flex';
    const input = document.getElementById('mkdir-name');
    input.value = '';
    input.focus();
}

async function createFolder() {
    const name = document.getElementById('mkdir-name').value.trim();
    if (!name) return;

    const path = currentPath ? `${currentPath}/${name}` : name;
    const result = await apiPost('/api/mkdir', { path });

    if (result.success) {
        closeOverlay();
        await refreshFiles();
    } else {
        alert(result.error || 'Failed to create folder');
    }
}

// ---- Rename ----

function showRenameDialog(path, currentName) {
    document.getElementById('rename-overlay').style.display = 'flex';
    document.getElementById('rename-path').value = path;
    const input = document.getElementById('rename-input');
    input.value = currentName;
    input.focus();
    input.select();
}

async function doRename() {
    const path = document.getElementById('rename-path').value;
    const newName = document.getElementById('rename-input').value.trim();
    if (!newName) return;

    const result = await apiPost('/api/rename', { path, new_name: newName });

    if (result.success) {
        closeOverlay();
        await refreshFiles();
    } else {
        alert(result.error || 'Rename failed');
    }
}

// ---- Delete ----

async function confirmDelete(path, name) {
    if (!confirm(`Delete "${name}"? This cannot be undone.`)) return;

    const result = await apiPost('/api/delete', { path });

    if (result.success) {
        await refreshFiles();
    } else {
        alert(result.error || 'Delete failed');
    }
}

// ---- Overlays ----

function closeOverlay() {
    document.querySelectorAll('.overlay').forEach(el => el.style.display = 'none');
}

// Close overlay on escape key
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeOverlay();
});

// Close overlay when clicking outside dialog
document.querySelectorAll('.overlay').forEach(el => {
    el.addEventListener('click', (e) => {
        if (e.target === el) closeOverlay();
    });
});

// ---- Helpers ----

function formatSize(bytes) {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0) + ' ' + units[i];
}

function fileIcon(name) {
    const ext = name.split('.').pop().toLowerCase();
    const icons = {
        jpg: '\uD83D\uDDBC', jpeg: '\uD83D\uDDBC', png: '\uD83D\uDDBC',
        gif: '\uD83D\uDDBC', bmp: '\uD83D\uDDBC', svg: '\uD83D\uDDBC', webp: '\uD83D\uDDBC',
        mp4: '\uD83C\uDFAC', mkv: '\uD83C\uDFAC', avi: '\uD83C\uDFAC', mov: '\uD83C\uDFAC',
        mp3: '\uD83C\uDFB5', wav: '\uD83C\uDFB5', flac: '\uD83C\uDFB5', ogg: '\uD83C\uDFB5',
        pdf: '\uD83D\uDCC4', doc: '\uD83D\uDCC4', docx: '\uD83D\uDCC4', txt: '\uD83D\uDCC4',
        zip: '\uD83D\uDCE6', tar: '\uD83D\uDCE6', gz: '\uD83D\uDCE6', '7z': '\uD83D\uDCE6',
    };
    return icons[ext] || '\uD83D\uDCC4';
}

function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function encodeURIPath(path) {
    return path.split('/').map(encodeURIComponent).join('/');
}

// ---- Init ----

document.addEventListener('DOMContentLoaded', async () => {
    setupDropZone();
    await refreshStatus();
    await refreshFiles();

    // Auto-refresh status every 10 seconds
    setInterval(refreshStatus, 10000);
});
