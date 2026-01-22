const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const dgram = require('dgram');
const os = require('os');

// ==========================================
// CONFIG: MANUAL IP (Leave empty "" for Auto)
const MANUAL_IP = ""; 
// ==========================================

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    maxHttpBufferSize: 1e8, // 100MB Limit (Required for Video)
    cors: { origin: "*" }
});

let activeDevices = [];

// --- LOGGING SYSTEM ---
function log(tag, message, data = "") {
    const time = new Date().toISOString().split('T')[1].split('.')[0];
    const color = { 
        'INFO': '\x1b[36m', 'SWIPE': '\x1b[35m', 'FILE': '\x1b[33m', 
        'MOUSE': '\x1b[32m', 'CLIP': '\x1b[34m', 'ERROR': '\x1b[31m', 'RESET': '\x1b[0m' 
    };
    console.log(`${color['RESET']}[${time}] ${color[tag] || ''}[${tag}] ${message} ${data ? JSON.stringify(data) : ''}${color['RESET']}`);
}

// --- SMART IP FINDER (Fixes Autoconnect) ---
function getLocalIP() {
    if (MANUAL_IP.length > 0) return MANUAL_IP;

    const interfaces = os.networkInterfaces();
    let candidates = [];

    console.log("--- NETWORK SCAN ---");
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                const ip = iface.address;
                // BLOCK Virtual Adapters (The cause of connection issues)
                if (ip.startsWith('192.168.56.') || ip.startsWith('192.168.137.')) continue;
                
                // PRIORITIZE Home/Office Wi-Fi
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

// --- 1. OMNI-BROADCASTING (Conference Mode Beacon) ---
// This broadcasts to the ENTIRE network. Any device with the app open will hear this and connect.
const udpSocket = dgram.createSocket('udp4');
udpSocket.bind(8888, () => {
    udpSocket.setBroadcast(true);
    log('INFO', 'UDP Discovery Beacon Active');
});

const MY_IP = getLocalIP();

setInterval(() => {
    const message = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
    udpSocket.send(message, 0, message.length, 8888, '255.255.255.255');
}, 1000);

// --- 2. THE NEURAL CORE (Socket Logic) ---
io.on('connection', (socket) => {
    const clientIp = socket.handshake.address;
    log('INFO', `New Connection: ${socket.id}`);

    // A. REGISTRATION & TOPOLOGY (Conference Mode Logic)
    socket.on('register', (device) => {
        device.id = socket.id;
        device.ip = clientIp;
        
        // DYNAMIC POSITIONING: 
        // 1st Device = 0 (Center)
        // 2nd Device = 1 (Right)
        // 3rd Device = -1 (Left)
        // 4th Device = 2 (Far Right), etc.
        // This ensures distinct positions for multiple devices.
        if (activeDevices.length === 0) device.x = 0;
        else if (activeDevices.length % 2 === 1) device.x = Math.ceil(activeDevices.length / 2);
        else device.x = -Math.ceil(activeDevices.length / 2);
        
        activeDevices.push(device);
        
        log('INFO', `Registered: ${device.name} at Position X:${device.x}`);
        socket.emit('register_confirm', { id: socket.id });
        
        // UPDATE EVERYONE (So all devices know about each other)
        io.emit('device_list', activeDevices);
    });

    // B. REMOTE TELEMETRY (Debugging)
    socket.on('remote_log', (data) => {
        const d = activeDevices.find(dev => dev.id === socket.id);
        const name = d ? d.name : "Unknown";
        console.log(`\x1b[33m[REMOTE] [${name}]: ${data.message}\x1b[0m`);
        socket.broadcast.emit('debug_broadcast', { sender: name, message: data.message });
    });

    // C. SWIPE & VECTOR MATH (Smart Trigger)
    socket.on('swipe_event', (data) => {
        // Broadcast to ALL devices (so Ghost Hand appears on the correct screen)
        socket.broadcast.emit('swipe_event', data);
        if (data.action === 'release') log('SWIPE', `Gesture Released`, { vx: data.vx });
    });

    // D. HOLOGRAM PROTOCOL (Header)
    socket.on('preview_header', (data) => {
        const target = activeDevices.find(d => d.id === data.targetId);
        const name = target ? target.name : "Unknown";
        log('FILE', `Sending Hologram (${data.fileType})`, { to: name, size: data.thumbnail.length });
        
        // Direct Tunnel to Target
        io.to(data.targetId).emit('preview_header', data);
    });

    // E. FILE TRANSFER (Payload)
    socket.on('file_payload', (data) => {
        log('FILE', `Transferring Content: ${data.fileName}`);
        io.to(data.targetId).emit('content_transfer', data);
    });

    // F. UNIFIED UTILS (Mouse & Clipboard)
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
    console.log("============================================");
    log('INFO', `Neural Core Online at http://${MY_IP}:3000`);
    console.log("============================================");
});
