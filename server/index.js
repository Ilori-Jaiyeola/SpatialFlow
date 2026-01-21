const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const dgram = require('dgram');
const os = require('os');

// --- SETUP ---
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    maxHttpBufferSize: 1e8, // 100 MB Limit for large video files
    cors: { origin: "*" }
});

// --- STATE MANAGEMENT ---
let activeDevices = [];

// --- LOGGING SYSTEM (The Control Tower) ---
function log(tag, message, data = "") {
    const time = new Date().toISOString().split('T')[1].split('.')[0];
    const color = {
        'INFO': '\x1b[36m', // Cyan
        'SWIPE': '\x1b[35m', // Magenta
        'FILE': '\x1b[33m', // Yellow
        'MOUSE': '\x1b[32m', // Green
        'CLIP': '\x1b[34m', // Blue
        'ERROR': '\x1b[31m', // Red
        'RESET': '\x1b[0m'
    };
    console.log(`${color['RESET']}[${time}] ${color[tag] || ''}[${tag}] ${message} ${data ? JSON.stringify(data) : ''}${color['RESET']}`);
}

// --- 1. OMNI-BROADCASTING (UDP Discovery) ---
const udpSocket = dgram.createSocket('udp4');
udpSocket.bind(8888, () => {
    udpSocket.setBroadcast(true);
    log('INFO', 'UDP Beacon Active on Port 8888');
});

function getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                return iface.address;
            }
        }
    }
    return '127.0.0.1';
}

// Broadcast IP every second so devices can find the server automatically
setInterval(() => {
    const message = Buffer.from(`SPATIAL_ANNOUNCE|${getLocalIP()}`);
    udpSocket.send(message, 0, message.length, 8888, '255.255.255.255');
}, 1000);

// --- 2. SOCKET LOGIC (The Neural Core) ---
io.on('connection', (socket) => {
    const clientIp = socket.handshake.address;
    log('INFO', `New Connection: ${socket.id} from ${clientIp}`);

    // A. DEVICE REGISTRATION & POSITIONING
    socket.on('register', (device) => {
        device.id = socket.id;
        device.ip = clientIp;
        
        // Smart Positioning Logic:
        // First device = Left (-1), Second device = Right (1)
        // This enables the "Vector Math" on the client to know which way to swipe.
        device.x = activeDevices.length === 0 ? -1 : 1; 
        device.y = 0;

        activeDevices.push(device);
        
        log('INFO', `Device Registered: ${device.name} (${device.type}) at X:${device.x}`);
        
        socket.emit('register_confirm', { id: socket.id });
        io.emit('device_list', activeDevices);
    });

    // B. REMOTE LOGGING (The Telemetry Relay)
    socket.on('remote_log', (data) => {
        const device = activeDevices.find(d => d.id === socket.id);
        const name = device ? device.name : "Unknown";
        
        // 1. Show in Server Terminal
        console.log(`\x1b[33m[REMOTE] [${name}]: ${data.message}\x1b[0m`);
        
        // 2. Relay to PC (for debugging without looking at server)
        socket.broadcast.emit('debug_broadcast', { 
            sender: name, 
            message: data.message 
        });
    });

    // C. VECTOR SWIPE LOGIC
    socket.on('swipe_event', (data) => {
        // Relay gesture data to all other devices so they can render the "Ghost Hand"
        socket.broadcast.emit('swipe_event', data);

        if (data.action === 'release') {
            log('SWIPE', `Gesture Released by ${data.senderId}`, { velocity: data.vx });
        }
    });

    // D. HOLOGRAM PROTOCOL (Header)
    socket.on('preview_header', (data) => {
        const target = activeDevices.find(d => d.id === data.targetId);
        const targetName = target ? target.name : "Unknown";
        
        log('FILE', `Sending Hologram (${data.fileType})`, { to: targetName, size: data.thumbnail.length });

        // Direct routing to target
        io.to(data.targetId).emit('preview_header', data);
    });

    // E. FILE TRANSFER (Payload)
    socket.on('file_payload', (data) => {
        const target = activeDevices.find(d => d.id === data.targetId);
        const targetName = target ? target.name : "Unknown";

        log('FILE', `Transferring Content: ${data.fileName}`, { to: targetName });

        io.to(data.targetId).emit('content_transfer', data);
    });

    // F. UNIFIED CANVAS: MOUSE TELEPORT
    socket.on('mouse_teleport', (data) => {
        // Relay mouse deltas to move the virtual cursor on the other screen
        socket.broadcast.emit('mouse_teleport', data);
    });

    // G. UNIFIED CANVAS: SHARED CLIPBOARD
    socket.on('clipboard_sync', (data) => {
        log('CLIP', `Clipboard Synced`, { textLength: data.text.length });
        socket.broadcast.emit('clipboard_sync', data);
    });

    // H. CONNECTION STABILITY
    socket.on('heartbeat', () => {
        // Keep connection alive
    });

    socket.on('disconnect', () => {
        const device = activeDevices.find(d => d.id === socket.id);
        if (device) log('INFO', `Device Disconnected: ${device.name}`);
        
        activeDevices = activeDevices.filter(d => d.id !== socket.id);
        io.emit('device_list', activeDevices);
    });
});

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
    log('INFO', `Neural Core Online at http://${getLocalIP()}:${PORT}`);
});
