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

// --- LOGGING SYSTEM ---
function log(tag, message, data = "") {
    const time = new Date().toISOString().split('T')[1].split('.')[0];
    const color = { 
        'INFO': '\x1b[36m', 'SWIPE': '\x1b[35m', 'FILE': '\x1b[33m', 
        'MOUSE': '\x1b[32m', 'CLIP': '\x1b[34m', 'ERROR': '\x1b[31m', 'RESET': '\x1b[0m' 
    };
    console.log(`${color['RESET']}[${time}] ${color[tag] || ''}[${tag}] ${message} ${data ? JSON.stringify(data) : ''}${color['RESET']}`);
}

// --- SMART IP FINDER ---
function getLocalIP() {
    if (MANUAL_IP.length > 0) return MANUAL_IP;
    const interfaces = os.networkInterfaces();
    let candidates = [];
    
    // console.log("--- NETWORK SCAN ---"); // Reduced noise
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                const ip = iface.address;
                if (ip.startsWith('192.168.56.') || ip.startsWith('192.168.137.')) continue;
                if (ip.startsWith('192.168.0.') || ip.startsWith('192.168.1.') || ip.startsWith('172.') || ip.startsWith('10.')) {
                    candidates.unshift(ip);
                } else {
                    candidates.push(ip);
                }
            }
        }
    }
    const chosen = candidates.length > 0 ? candidates[0] : '127.0.0.1';
    return chosen;
}

const MY_IP = getLocalIP();

// --- UDP DISCOVERY (THE FIX) ---
const udpSocket = dgram.createSocket('udp4');

udpSocket.on('message', (msg, rinfo) => {
    const message = msg.toString().trim();

    // 1. ACTIVE DISCOVERY (Instant Connect)
    // When Android shouts "FIND_NEURAL_CORE", we reply immediately.
    if (message === 'FIND_NEURAL_CORE') {
        log('INFO', `Discovery Signal from ${rinfo.address}`);
        const reply = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
        
        // Reply directly to the device that asked
        udpSocket.send(reply, 0, reply.length, rinfo.port, rinfo.address, (err) => {
            if (err) log('ERROR', 'Reply Failed', err);
        });
        return; 
    }
});

// Bind to Port 41234 so phones know where to shout
udpSocket.bind(41234, () => {
    udpSocket.setBroadcast(true);
    log('INFO', `Neural Core Online at http://${MY_IP}:3000`);
    log('INFO', 'Discovery System Active (Listening on 41234)');
});

// 2. PASSIVE BEACON (Backup for legacy clients)
setInterval(() => {
    const message = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
    udpSocket.send(message, 0, message.length, 8888, '255.255.255.255');
}, 1000);


// --- THE NEURAL CORE (Socket Logic) ---
io.on('connection', (socket) => {
    const clientIp = socket.handshake.address;
    log('INFO', `New Connection: ${socket.id}`);

    // A. REGISTRATION & TOPOLOGY
    socket.on('register', (device) => {
        device.id = socket.id;
        device.ip = clientIp;
        // Smart Positioning (Auto-Layout)
        if (activeDevices.length === 0) device.x = 0;
        else if (activeDevices.length % 2 === 1) device.x = Math.ceil(activeDevices.length / 2);
        else device.x = -Math.ceil(activeDevices.length / 2);
        
        activeDevices.push(device);
        log('INFO', `Registered: ${device.name} at Position X:${device.x}`);
        io.emit('device_list', activeDevices);
        socket.emit('register_confirm', { id: socket.id });
    });

    // B. REMOTE TELEMETRY
    socket.on('remote_log', (data) => {
        const d = activeDevices.find(dev => dev.id === socket.id);
        const name = d ? d.name : "Unknown";
        console.log(`\x1b[33m[REMOTE] [${name}]: ${data.message}\x1b[0m`);
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

    // E. FILE TRANSFER
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

server.listen(3000, '0.0.0.0');
