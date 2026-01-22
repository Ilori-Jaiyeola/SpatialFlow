const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const dgram = require('dgram');
const os = require('os');

// ==========================================
// CONFIG: MANUAL IP (Leave empty for Auto)
const MANUAL_IP = ""; 
// ==========================================

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    maxHttpBufferSize: 1e8, // 100MB Limit (Crucial for Video)
    cors: { origin: "*" }
});

let activeDevices = [];

// --- LOGGING SYSTEM (Restored Full Verbosity) ---
function log(tag, message, data = "") {
    const time = new Date().toISOString().split('T')[1].split('.')[0];
    const color = { 
        'INFO': '\x1b[36m', 'SWIPE': '\x1b[35m', 'FILE': '\x1b[33m', 
        'MOUSE': '\x1b[32m', 'CLIP': '\x1b[34m', 'ERROR': '\x1b[31m', 'RESET': '\x1b[0m' 
    };
    console.log(`${color['RESET']}[${time}] ${color[tag] || ''}[${tag}] ${message} ${data ? JSON.stringify(data) : ''}${color['RESET']}`);
}

// --- SMART IP FINDER (Restored Logic) ---
function getLocalIP() {
    if (MANUAL_IP.length > 0) return MANUAL_IP;
    const interfaces = os.networkInterfaces();
    let candidates = [];
    console.log("--- NETWORK SCAN ---");
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                const ip = iface.address;
                // BLOCK Virtual Adapters
                if (ip.startsWith('192.168.56.') || ip.startsWith('192.168.137.')) continue;
                // PRIORITIZE Home/Office
                if (ip.startsWith('192.168.0.') || ip.startsWith('192.168.1.') || ip.startsWith('172.') || ip.startsWith('10.')) {
                    candidates.unshift(ip);
                } else {
                    candidates.push(ip);
                }
            }
        }
    }
    const chosen = candidates.length > 0 ? candidates[0] : '127.0.0.1';
    console.log(`>>> AUTO-SELECTED IP: ${chosen}`);
    return chosen;
}

// --- UDP BEACON (THE PC CONNECTION FIX) ---
const udpSocket = dgram.createSocket('udp4');

// CRITICAL CHANGE: Bind to Port 0 (Random) to free up Port 8888 for the PC App.
udpSocket.bind(0, () => {
    udpSocket.setBroadcast(true);
    log('INFO', 'UDP Discovery Beacon Active (Non-Blocking Mode)');
});

const MY_IP = getLocalIP();

setInterval(() => {
    const message = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
    // We SEND to 8888, allowing clients to hear us without conflict.
    udpSocket.send(message, 0, message.length, 8888, '255.255.255.255');
}, 1000);

// --- THE NEURAL CORE (Socket Logic) ---
io.on('connection', (socket) => {
    const clientIp = socket.handshake.address;
    log('INFO', `New Connection: ${socket.id}`);

    // A. REGISTRATION & TOPOLOGY (Conference Mode Logic)
    socket.on('register', (device) => {
        device.id = socket.id;
        device.ip = clientIp;
        // Smart Positioning
        if (activeDevices.length === 0) device.x = 0;
        else if (activeDevices.length % 2 === 1) device.x = Math.ceil(activeDevices.length / 2);
        else device.x = -Math.ceil(activeDevices.length / 2);
        
        activeDevices.push(device);
        log('INFO', `Registered: ${device.name} at Position X:${device.x}`);
        io.emit('device_list', activeDevices);
        socket.emit('register_confirm', { id: socket.id });
    });

    // B. REMOTE TELEMETRY (Debugging)
    socket.on('remote_log', (data) => {
        const d = activeDevices.find(dev => dev.id === socket.id);
        const name = d ? d.name : "Unknown";
        console.log(`\x1b[33m[REMOTE] [${name}]: ${data.message}\x1b[0m`);
        socket.broadcast.emit('debug_broadcast', { sender: name, message: data.message });
    });

    // C. SWIPE & VECTOR MATH
    socket.on('swipe_event', (data) => {
        socket.broadcast.emit('swipe_event', data);
        if (data.action === 'release') log('SWIPE', `Gesture Released`, { vx: data.vx });
    });

    // D. HOLOGRAM PROTOCOL
    socket.on('preview_header', (data) => {
        const target = activeDevices.find(d => d.id === data.targetId);
        const name = target ? target.name : "Unknown";
        log('FILE', `Sending Hologram (${data.fileType})`, { to: name, size: data.thumbnail.length });
        io.to(data.targetId).emit('preview_header', data);
    });

    // E. FILE TRANSFER (Payload)
    socket.on('file_payload', (data) => {
        const target = activeDevices.find(d => d.id === data.targetId);
        const name = target ? target.name : "Unknown";
        log('FILE', `Transferring Content: ${data.fileName}`, { to: name });
        io.to(data.targetId).emit('content_transfer', data);
    });

    // F. UNIFIED UTILS
    socket.on('mouse_teleport', (data) => socket.broadcast.emit('mouse_teleport', data));
    socket.on('clipboard_sync', (data) => {
        log('CLIP', 'Clipboard Synced');
        socket.broadcast.emit('clipboard_sync', data);
    });

    // G. DISCONNECT
    socket.on('disconnect', () => {
        activeDevices = activeDevices.filter(d => d.id !== socket.id);
        io.emit('device_list', activeDevices);
        log('INFO', `Client Disconnected: ${socket.id}`);
    });
});

server.listen(3000, '0.0.0.0', () => {
    log('INFO', `Neural Core Online at http://${MY_IP}:3000`);
});
