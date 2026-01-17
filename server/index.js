const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http, {
    pingInterval: 2000, 
    pingTimeout: 5000,
    cors: { origin: "*" },
    maxHttpBufferSize: 1e8 // Allow files up to 100MB
});
const dgram = require('dgram');
const os = require('os');

const UDP_PORT = 8888;
const TCP_PORT = 3000;

// =========================================================
// 1. OMNI-BROADCASTING (Connection Stability)
// =========================================================
function getBroadcastAddresses() {
    const interfaces = os.networkInterfaces();
    const addresses = [];
    for (const name of Object.keys(interfaces)) {
        for (const net of interfaces[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                const parts = net.address.split('.');
                parts[3] = '255'; 
                addresses.push({ ip: net.address, broadcast: parts.join('.') });
            }
        }
    }
    return addresses;
}

const udpSocket = dgram.createSocket('udp4');
udpSocket.bind(() => {
    udpSocket.setBroadcast(true);
    console.log("--- NEURAL CORE DISCOVERY ACTIVE ---");
});

setInterval(() => {
    const addresses = getBroadcastAddresses();
    if (addresses.length === 0) return;
    addresses.forEach(addr => {
        const message = Buffer.from(`SPATIAL_ANNOUNCE|${addr.ip}`);
        try {
            udpSocket.send(message, 0, message.length, UDP_PORT, addr.broadcast);
            udpSocket.send(message, 0, message.length, UDP_PORT, "255.255.255.255");
        } catch (e) {}
    });
}, 1000);

// =========================================================
// 2. VECTOR MATH (Smart Swipe Logic)
// =========================================================
let devices = [];

function findTargetDevice(sender, swipeData) {
    const { velocityX, velocityY } = swipeData;
    const magnitude = Math.sqrt(velocityX * velocityX + velocityY * velocityY);
    if (magnitude === 0) return null;
    
    const normVx = velocityX / magnitude;
    const normVy = velocityY / magnitude;

    let bestTarget = null;
    let maxDotProduct = -1.0; 

    devices.forEach(target => {
        if (target.id === sender.id) return; 

        const dx = target.x - sender.x;
        const dy = target.y - sender.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist === 0) return;
        
        const normDx = dx / dist;
        const normDy = dy / dist;

        const dotProduct = (normVx * normDx) + (normVy * normDy);

        if (dotProduct > 0.5 && dotProduct > maxDotProduct) {
            maxDotProduct = dotProduct;
            bestTarget = target;
        }
    });
    return bestTarget;
}

// =========================================================
// 3. SOCKET LOGIC (The Brain)
// =========================================================
io.on('connection', (socket) => {
    console.log(`Node Connected: ${socket.id}`);

    // --- A. REGISTRATION & TOPOLOGY ---
    socket.on('register', (info) => {
        const clientIp = socket.handshake.address.replace('::ffff:', '');
        devices = devices.filter(d => d.ip !== clientIp);

        // Auto-assign: Center(0,0), Left(-1,0), Right(1,0), Top(0,-1)
        const newDevice = {
            id: socket.id,
            name: info.name,
            type: info.type,
            ip: clientIp,
            x: devices.length === 0 ? 0 : (devices.length % 2 === 0 ? 1 : -1),
            y: 0
        };
        
        devices.push(newDevice);
        console.log(`Device Registered: ${newDevice.name} at [${newDevice.x}, ${newDevice.y}]`);
        
        socket.emit('register_confirm', { id: socket.id });
        io.emit('device_list', devices);
    });

    // --- B. SWIPE & FILE TRANSFER ---
    socket.on('swipe_event', (data) => {
        const sender = devices.find(d => d.id === socket.id);
        if (!sender) return;

        const velocityX = data.vx || 0;
        const velocityY = data.vy || 0;

        // Hard Swipe = Transfer
        if (data.action === 'release' && (Math.abs(velocityX) > 100 || Math.abs(velocityY) > 100)) {
            const target = findTargetDevice(sender, { velocityX, velocityY });

            if (target) {
                console.log(`Routed Swipe: ${sender.name} -> ${target.name}`);
                io.to(target.id).emit('swipe_event', { ...data, senderId: sender.id });
                socket.emit('transfer_request', { targetId: target.id }); 
            }
        } else {
            // Soft Drag = Visual Ghost Hand
            socket.broadcast.emit('swipe_event', data);
        }
    });

    socket.on('file_payload', (data) => {
        console.log(`Relaying File (${data.fileName}) -> ${data.targetId}`);
        io.to(data.targetId).emit('content_transfer', data);
    });

    // --- C. UNIFIED CANVAS: SHARED CLIPBOARD ---
    socket.on('clipboard_sync', (data) => {
        console.log(`Clipboard Sync from ${socket.id}`);
        // Broadcast to EVERYONE (Universal Clipboard)
        socket.broadcast.emit('clipboard_sync', { text: data.text });
    });

    // --- D. UNIFIED CANVAS: MOUSE TELEPORT ---
    socket.on('mouse_teleport', (data) => {
        // Relay cursor movement directly to target
        io.to(data.targetId).emit('mouse_teleport', data);
    });

    socket.on('disconnect', () => {
        devices = devices.filter(d => d.id !== socket.id);
        io.emit('device_list', devices);
    });
});

const addrs = getBroadcastAddresses().map(a => a.ip).join(', ');
http.listen(TCP_PORT, '0.0.0.0', () => {
    console.log(`NEURAL CORE v2.5 ONLINE. Listening on: [${addrs}]`);
});
