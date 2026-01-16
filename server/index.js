const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http, {
    pingInterval: 2000, 
    pingTimeout: 5000,
    cors: { origin: "*" } // Allow all connections
});
const dgram = require('dgram');
const os = require('os');

const UDP_PORT = 8888;
const TCP_PORT = 3000;

// --- 1. THE OMNI-BROADCASTER (Fixes "Scanning..." Loop) ---
// This function finds the broadcast address for every network card you have
function getBroadcastAddresses() {
    const interfaces = os.networkInterfaces();
    const addresses = [];
    
    for (const name of Object.keys(interfaces)) {
        for (const net of interfaces[name]) {
            // Skip internal (localhost) and non-IPv4 addresses
            if (net.family === 'IPv4' && !net.internal) {
                // Calculate Broadcast Address (Simple logic: replace last segment with 255)
                // A proper subnet calculation is better, but this works for 99% of home routers
                const parts = net.address.split('.');
                parts[3] = '255'; 
                addresses.push({
                    ip: net.address,
                    broadcast: parts.join('.') 
                });
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

// Broadcast Loop: Shout on ALL interfaces every 1 second
setInterval(() => {
    const addresses = getBroadcastAddresses();
    if (addresses.length === 0) return;

    addresses.forEach(addr => {
        // Message format: SPATIAL_ANNOUNCE|YOUR_PC_IP
        const message = Buffer.from(`SPATIAL_ANNOUNCE|${addr.ip}`);
        try {
            udpSocket.send(message, 0, message.length, UDP_PORT, addr.broadcast);
            // Also send to global broadcast just in case
            udpSocket.send(message, 0, message.length, UDP_PORT, "255.255.255.255");
        } catch (e) {
            // Ignore errors from inactive adapters
        }
    });
}, 1000);

// --- 2. SOCKET LOGIC (Keep your existing logic) ---
let devices = [];

io.on('connection', (socket) => {
    console.log(`Connection attempt from: ${socket.handshake.address}`);

    socket.on('register', (info) => {
        const clientIp = socket.handshake.address.replace('::ffff:', ''); // Clean IPv6 junk
        
        // Remove existing session from same IP to prevent duplicates
        devices = devices.filter(d => d.ip !== clientIp);

        const newDevice = {
            id: socket.id,
            name: info.name,
            type: info.type,
            ip: clientIp,
            x: devices.length === 0 ? 0 : (devices.length % 2 === 0 ? 1 : -1),
            y: 0
        };
        
        devices.push(newDevice);
        console.log(`REGISTERED: ${newDevice.name} at ${newDevice.ip}`);
        
        socket.emit('register_confirm', { id: socket.id });
        io.emit('device_list', devices);
    });

    socket.on('disconnect', () => {
        console.log(`Node Disconnected: ${socket.id}`);
        devices = devices.filter(d => d.id !== socket.id);
        io.emit('device_list', devices);
    });

    // ... (Your other event handlers: swipe_event, file_payload, etc.) ...
    // Make sure to paste your file transfer logic here if it's not present
    socket.on('swipe_event', (data) => socket.broadcast.emit('swipe_event', data));
});

http.listen(TCP_PORT, '0.0.0.0', () => {
    const addrs = getBroadcastAddresses().map(a => a.ip).join(', ');
    console.log(`NEURAL CORE ONLINE. Listening on IPs: [${addrs}]`);
});
