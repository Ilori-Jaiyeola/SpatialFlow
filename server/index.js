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
    maxHttpBufferSize: 1e8, 
    cors: { origin: "*" }
});

let activeDevices = [];

// --- PRETTY LOGGING ---
function log(tag, message, data = "") {
    const time = new Date().toISOString().split('T')[1].split('.')[0];
    const color = { 'INFO': '\x1b[36m', 'SWIPE': '\x1b[35m', 'FILE': '\x1b[33m', 'ERROR': '\x1b[31m', 'RESET': '\x1b[0m' };
    console.log(`${color['RESET']}[${time}] ${color[tag] || ''}[${tag}] ${message} ${data ? JSON.stringify(data) : ''}${color['RESET']}`);
}

// --- ROBUST IP FINDER (The Logic Restoration) ---
function getLocalIP() {
    if (MANUAL_IP.length > 0) return MANUAL_IP;

    const interfaces = os.networkInterfaces();
    let bestCandidate = null;

    console.log("--- NETWORK SCAN ---");
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            // Must be IPv4 and NOT localhost
            if (iface.family === 'IPv4' && !iface.internal) {
                const ip = iface.address;
                console.log(`Checking: ${name} -> ${ip}`);

                // 1. STRICTLY BLOCK VIRTUAL ADAPTERS
                if (ip.startsWith('192.168.56.')) continue; // VirtualBox
                if (ip.startsWith('192.168.137.')) continue; // Default Windows Hotspot (often creates issues)
                
                // 2. PRIORITIZE STANDARD WI-FI SUBNETS
                // We accept ANY 192.168.x.x that isn't the blocked ones above.
                if (ip.startsWith('192.168.')) {
                    // This is likely Home Wi-Fi
                    return ip; // RETURN IMMEDIATELY (Fastest Match)
                }
                
                // 3. BACKUP (e.g. 172.x or 10.x enterprise networks)
                if (!bestCandidate) bestCandidate = ip;
            }
        }
    }
    return bestCandidate || '127.0.0.1';
}

// --- UDP BEACON (The "Lighthouse") ---
const udpSocket = dgram.createSocket('udp4');
udpSocket.bind(8888, () => {
    udpSocket.setBroadcast(true);
    log('INFO', 'UDP Beacon Active (Broadcasting every 1s)');
});

const MY_IP = getLocalIP();

setInterval(() => {
    // THIS is the packet the phone looks for
    const message = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
    udpSocket.send(message, 0, message.length, 8888, '255.255.255.255');
}, 1000);

// --- SOCKET LOGIC ---
io.on('connection', (socket) => {
    const clientIp = socket.handshake.address;
    log('INFO', `Device Connected: ${socket.id}`);

    // A. REGISTRATION
    socket.on('register', (device) => {
        device.id = socket.id;
        device.ip = clientIp;
        device.x = activeDevices.length === 0 ? -1 : 1; 
        activeDevices.push(device);
        log('INFO', `Registered: ${device.name}`);
        io.emit('device_list', activeDevices);
        socket.emit('register_confirm', { id: socket.id });
    });

    // B. LOG RELAY
    socket.on('remote_log', (data) => {
        const d = activeDevices.find(dev => dev.id === socket.id);
        const name = d ? d.name : "Unknown";
        console.log(`\x1b[33m[REMOTE] [${name}]: ${data.message}\x1b[0m`);
        socket.broadcast.emit('debug_broadcast', { sender: name, message: data.message });
    });

    // C. CORE FEATURES (Swipe, File, Mouse, Clipboard)
    socket.on('swipe_event', (data) => {
        socket.broadcast.emit('swipe_event', data);
        if (data.action === 'release') log('SWIPE', `Gesture Released`);
    });

    socket.on('preview_header', (data) => io.to(data.targetId).emit('preview_header', data));
    socket.on('file_payload', (data) => io.to(data.targetId).emit('content_transfer', data));
    socket.on('mouse_teleport', (data) => socket.broadcast.emit('mouse_teleport', data));
    socket.on('clipboard_sync', (data) => socket.broadcast.emit('clipboard_sync', data));

    socket.on('disconnect', () => {
        activeDevices = activeDevices.filter(d => d.id !== socket.id);
        io.emit('device_list', activeDevices);
    });
});

server.listen(3000, '0.0.0.0', () => {
    console.log("============================================");
    log('INFO', `Neural Core Online at http://${MY_IP}:3000`);
    console.log("============================================");
});
