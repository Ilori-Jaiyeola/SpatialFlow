const express = require('express');
const http = require('http');
const { Server } = require("socket.io");
const ip = require('ip');
const dgram = require('dgram');

// --- THE NEURAL CORE (AI + TOPOLOGY) ---
class NeuralEngine {
    constructor() {
        this.networkHealth = 'optimal';
        this.topology = {}; // Stores the physical map
        this.conferenceMode = false; // Toggle for "Send to All"
    }

    updateTopology(layoutData) {
        this.topology = {};
        console.log("🧠 AI: Recalculating Spatial Topology...");
        for (let devA of layoutData) {
            this.topology[devA.id] = {};
            for (let devB of layoutData) {
                if (devA.id === devB.id) continue;
                // Calculate relative positions
                const xDiff = devB.x - devA.x;
                const yDiff = devB.y - devA.y;
                
                // Define Neighbors (Threshold 0.5 grid units)
                if (xDiff > 0.5 && Math.abs(yDiff) < 0.5) this.topology[devA.id].right = devB.id;
                if (xDiff < -0.5 && Math.abs(yDiff) < 0.5) this.topology[devA.id].left = devB.id;
                if (yDiff > 0.5 && Math.abs(xDiff) < 0.5) this.topology[devA.id].bottom = devB.id;
                if (yDiff < -0.5 && Math.abs(xDiff) < 0.5) this.topology[devA.id].top = devB.id;
            }
        }
        console.log("🗺️  Current Map:", this.topology);
    }

    // Determine where to send the "Ghost" visuals
    routePacket(senderId, packet) {
        const direction = packet.edge;
        const neighbors = this.topology[senderId];
        
        // If no map, or conference mode, fallback to broadcast
        if (!neighbors || this.conferenceMode) return { target: 'broadcast' };

        const targetId = neighbors[direction.toLowerCase()];
        return targetId ? { target: 'single', id: targetId } : { target: 'none' };
    }

    // Determine where to send the HEAVY CONTENT (Video/Image)
    getContentTargets(senderId) {
        if (this.conferenceMode) {
            return 'broadcast';
        }

        const neighbors = this.topology[senderId];
        if (!neighbors) return 'broadcast'; // No map? Send to all.

        // Get all unique neighbor IDs (Left, Right, Top, Bottom)
        // We pre-load content to neighbors so the "swipe" is instant.
        const targets = Object.values(neighbors);
        return [...new Set(targets)]; // Remove duplicates
    }
}

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
const aiCore = new NeuralEngine();

const SERVER_PORT = 3000;
const DISCOVERY_PORT = 4444;

console.log("------------------------------------------------");
console.log("🚀 SpatialFlow: Position-Based Connection Active");
console.log("------------------------------------------------");

// --- UDP DISCOVERY ---
const udpSocket = dgram.createSocket('udp4');
udpSocket.bind(() => {
    udpSocket.setBroadcast(true);
    setInterval(() => {
        const msg = JSON.stringify({ service: 'spatial_flow_core', ip: ip.address(), port: SERVER_PORT });
        udpSocket.send(msg, 0, msg.length, DISCOVERY_PORT, '255.255.255.255');
    }, 1000);
});

// --- WEBSOCKET LOGIC ---
io.on('connection', (socket) => {
    console.log(`> [Net] Device Connected: ${socket.id}`);

    socket.on('register', (data) => {
        // ... (Same as before)
    });

    socket.on('update_layout', (layoutData) => {
        aiCore.updateTopology(layoutData);
        io.emit('layout_confirmed', layoutData);
    });

    // 1. DIRECTIONAL SWIPE ROUTING
    socket.on('swipe_update', (data) => {
        const routing = aiCore.routePacket(socket.id, data);
        
        if (routing.target === 'single') {
            // SPATIAL PEERING: Only talk to the specific neighbor
            io.to(routing.id).emit('render_split', data);
        } else if (routing.target === 'broadcast') {
            socket.broadcast.volatile.emit('render_split', data);
        }
        // If target is 'none', we block the packet.
        // This ensures if you swipe left into nothingness, nothing happens.
    });

    // 2. POSITION-BASED CONTENT TRANSFER
    socket.on('broadcast_content', (data) => {
        const targets = aiCore.getContentTargets(socket.id);

        if (targets === 'broadcast') {
            console.log(`📡 Conference Mode: Sending content to ALL.`);
            socket.broadcast.emit('receive_content', data);
        } else {
            console.log(`📍 Spatial Mode: Sending content to neighbors: ${targets}`);
            targets.forEach(targetId => {
                io.to(targetId).emit('receive_content', data);
            });
        }
    });

    socket.on('toggle_conference_mode', (isEnabled) => {
        aiCore.conferenceMode = isEnabled;
        console.log(`🔄 Conference Mode set to: ${isEnabled}`);
        io.emit('mode_update', { conference: isEnabled });
    });
});

server.listen(SERVER_PORT, () => {
    console.log(`\n✅ Core Ready.`);
});