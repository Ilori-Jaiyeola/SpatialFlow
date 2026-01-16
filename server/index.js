const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http);
const dgram = require('dgram');
const ip = require('ip');

// --- 1. NETWORK DISCOVERY (BEACON) ---
const udpSocket = dgram.createSocket('udp4');
const BROADCAST_ADDR = "255.255.255.255";
const UDP_PORT = 8888;
const TCP_PORT = 3000;
const MY_IP = ip.address();

// Beacon Loop: Shouts "I AM HERE" every 2 seconds
// This fixes the "Searching..." issue by being aggressive
setInterval(() => {
    const message = Buffer.from(`SPATIAL_ANNOUNCE|${MY_IP}`);
    try {
        udpSocket.setBroadcast(true);
        udpSocket.send(message, 0, message.length, UDP_PORT, BROADCAST_ADDR);
    } catch (e) {
        // Ignore broadcast errors
    }
}, 2000);

// --- 2. SPATIAL TOPOLOGY LOGIC ---
let devices = [];
const SLOT_POSITIONS = [
    { x: 0, y: 0, label: "CORE" },   // Slot 0: The PC Server (Center)
    { x: -1, y: 0, label: "LEFT" },  // Slot 1: First Phone
    { x: 1, y: 0, label: "RIGHT" },  // Slot 2: Second Phone
    { x: 0, y: -1, label: "TOP" },   // Slot 3: Third Device
    { x: 0, y: 1, label: "BOTTOM" }  // Slot 4: Fourth Device
];

function assignSpatialSlot(device) {
    // Find the first empty slot
    for (let i = 0; i < SLOT_POSITIONS.length; i++) {
        const slot = SLOT_POSITIONS[i];
        const isOccupied = devices.some(d => d.spatialSlot === i);
        if (!isOccupied) {
            device.spatialSlot = i;
            device.x = slot.x;
            device.y = slot.y;
            return;
        }
    }
    // Overflow: Just put them far right
    device.spatialSlot = 99;
    device.x = 2;
    device.y = 0;
}

// --- 3. VECTOR ROUTING (THE MATH) ---
function findTargetDevice(sender, swipeData) {
    const { velocityX, velocityY } = swipeData;
    
    // Normalize swipe vector
    const magnitude = Math.sqrt(velocityX * velocityX + velocityY * velocityY);
    const normVx = velocityX / magnitude;
    const normVy = velocityY / magnitude;

    let bestTarget = null;
    let maxDotProduct = -1.0; // Start low

    devices.forEach(target => {
        if (target.id === sender.id) return; // Don't send to self

        // Calculate vector from Sender to Target
        const dx = target.x - sender.x;
        const dy = target.y - sender.y;
        
        // Normalize direction to target
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist === 0) return;
        const normDx = dx / dist;
        const normDy = dy / dist;

        // Dot Product determines how well the swipe aligns with the target
        // 1.0 = Perfect alignment, 0.0 = 90 degrees off, -1.0 = Opposite direction
        const dotProduct = (normVx * normDx) + (normVy * normDy);

        // Threshold: Must be somewhat aligned (> 0.5 means within ~60 degrees)
        if (dotProduct > 0.5 && dotProduct > maxDotProduct) {
            maxDotProduct = dotProduct;
            bestTarget = target;
        }
    });

    return bestTarget;
}

// --- 4. SOCKET LOGIC ---
io.on('connection', (socket) => {
    console.log('Node connected:', socket.id);

    socket.on('register', (info) => {
        // Generate Unique Name: "Pixel 7 [8F]"
        const uniqueSuffix = socket.id.substr(0, 4).toUpperCase();
        const smartName = `${info.name} [${uniqueSuffix}]`;

        const newDevice = {
            id: socket.id,
            name: smartName,
            type: info.type,
            ip: socket.handshake.address
        };

        // AUTO-POSITION THE DEVICE
        assignSpatialSlot(newDevice);
        
        devices.push(newDevice);
        
        // Send back their ID and config
        socket.emit('register_confirm', { 
            id: socket.id, 
            x: newDevice.x, 
            y: newDevice.y 
        });

        // Update everyone's map
        io.emit('device_list', devices);
        console.log(`Auto-positioned ${smartName} at (${newDevice.x}, ${newDevice.y})`);
    });

    socket.on('swipe_event', (data) => {
        const sender = devices.find(d => d.id === socket.id);
        if (!sender) return;

        // Calculate "Kick" Vector from raw touch data
        const velocityX = data.vx || 0;
        const velocityY = data.vy || 0;

        if (data.action === 'release' && (Math.abs(velocityX) > 100 || Math.abs(velocityY) > 100)) {
            // The user actually swiped hard! Let's find the target.
            const target = findTargetDevice(sender, { velocityX, velocityY });

            if (target) {
                console.log(`Routed swipe from ${sender.name} -> ${target.name}`);
                
                // Tell Sender: "Transfer Started"
                socket.emit('transfer_ack', { targetName: target.name });

                // Tell Receiver: "Here comes the ghost hand!"
                io.to(target.id).emit('swipe_event', {
                    ...data,
                    senderId: sender.id,
                    isTarget: true // Special flag for the "Ghost Hand"
                });
            } else {
                console.log("Swipe detected, but no device in that direction.");
            }
        } else {
            // Just a dragging motion, broadcast to all (for visual effect only)
            socket.broadcast.emit('swipe_event', data);
        }
    });

    socket.on('disconnect', () => {
        devices = devices.filter(d => d.id !== socket.id);
        io.emit('device_list', devices);
    });
});

http.listen(TCP_PORT, () => {
    console.log(`NEURAL CORE ONLINE at ${MY_IP}:${TCP_PORT}`);
});
