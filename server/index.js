const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http, {
    pingInterval: 2000, // Check connection every 2s
    pingTimeout: 5000   // Wait 5s before assuming dead (Tolerates walking)
});
const dgram = require('dgram');
const ip = require('ip');

// --- 1. ROBUST DISCOVERY (The Beacon) ---
const udpSocket = dgram.createSocket('udp4');
const MY_IP = ip.address();
// Broadcast aggressively so moving phones find it instantly
setInterval(() => {
    try {
        const message = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
        udpSocket.setBroadcast(true);
        udpSocket.send(message, 0, message.length, 8888, "255.255.255.255");
    } catch (e) {}
}, 1000); // Frequency: 1 second

// --- 2. SPATIAL STATE ---
let devices = [];

io.on('connection', (socket) => {
    console.log(`Node Connected: ${socket.id}`);

    // --- A. REGISTRATION & POSITIONING ---
    socket.on('register', (info) => {
        // Remove any old "ghost" connections from this same IP
        devices = devices.filter(d => d.ip !== socket.handshake.address);
        
        const newDevice = {
            id: socket.id,
            name: `${info.name} [${socket.id.substring(0,4)}]`,
            type: info.type,
            ip: socket.handshake.address,
            lastSeen: Date.now(), // For Heartbeat
            x: devices.length === 0 ? 0 : (devices.length % 2 === 0 ? 1 : -1), // Auto-Slot
            y: 0
        };
        devices.push(newDevice);
        
        socket.emit('register_confirm', { id: socket.id });
        io.emit('device_list', devices);
    });

    // --- B. THE HEARTBEAT (Fixes the "Walking" Disconnect) ---
    // If a phone moves, it might drop packets. This keeps it alive.
    socket.on('heartbeat', () => {
        const device = devices.find(d => d.id === socket.id);
        if (device) {
            device.lastSeen = Date.now();
        }
    });

    // --- C. THE FASTER PART (WebRTC Signaling) ---
    // This allows devices to "shake hands" for direct P2P transfer
    socket.on('p2p_signal', (data) => {
        // Pass the signal directly to the target (skip the server processing)
        io.to(data.targetId).emit('p2p_signal', {
            senderId: socket.id,
            signal: data.signal
        });
    });

    // --- D. SMART SWIPES ---
    socket.on('swipe_event', (data) => {
        // (Keep your existing swipe logic here)
        socket.broadcast.emit('swipe_event', data); 
    });

    socket.on('disconnect', () => {
        // Don't remove immediately! Wait 5s in case it's just a weak signal.
        setTimeout(() => {
            const device = devices.find(d => d.id === socket.id);
            // Only remove if they haven't reconnected
            if (device && Date.now() - device.lastSeen > 5000) {
                console.log(`Node Lost: ${device.name}`);
                devices = devices.filter(d => d.id !== socket.id);
                io.emit('device_list', devices);
            }
        }, 5000);
    });
});

http.listen(3000, () => console.log(`NEURAL CORE v2.0 running on ${MY_IP}`));
