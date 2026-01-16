import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../widgets/glass_box.dart';
import 'dart:math' as math; // Needed for animations

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({Key? key}) : super(key: key);

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> with SingleTickerProviderStateMixin {
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    // Creates the rotating radar effect
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final size = MediaQuery.of(context).size;
    
    // Find "ME" to center the map around myself
    final myId = socketService.myId;
    final me = socketService.activeDevices.firstWhere(
        (d) => d['id'] == myId, 
        orElse: () => {'x': 0, 'y': 0}
    );
    
    // Server coordinates of "ME"
    double myServerX = (me['x'] ?? 0).toDouble();
    double myServerY = (me['y'] ?? 0).toDouble();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("NEURAL TOPOLOGY", style: TextStyle(letterSpacing: 2, fontSize: 14)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 1. BACKGROUND GRID
          _buildGridBackground(),

          // 2. RADAR SCANNER
          Center(
            child: RotationTransition(
              turns: _radarController,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      const Color(0xFF00E676).withOpacity(0.0),
                      const Color(0xFF00E676).withOpacity(0.1),
                    ],
                    stops: const [0.8, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. DEVICES (The Nodes)
          ...socketService.activeDevices.map((device) {
            bool isMe = device['id'] == myId;

            // CALCULATE RELATIVE POSITION
            // If I am at (0,0) and Peer is at (-1,0), they should appear to my Left.
            double relX = (device['x'] ?? 0).toDouble() - myServerX;
            double relY = (device['y'] ?? 0).toDouble() - myServerY;

            // SCALE TO SCREEN (1 Unit = 120 pixels)
            double screenX = (size.width / 2) + (relX * 120) - 40; // -40 is half widget width
            double screenY = (size.height / 2) + (relY * 120) - 50; 

            return Positioned(
              left: screenX,
              top: screenY,
              child: _buildDeviceNode(device, isMe),
            );
          }).toList(),

          // 4. STATUS FOOTER
          Positioned(
            bottom: 40, left: 20, right: 20,
            child: GlassBox(
              child: Column(
                children: [
                   const Text("SYSTEM STATUS: ONLINE", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                   const SizedBox(height: 5),
                   Text(
                     "Tracking ${socketService.activeDevices.length} Active Nodes\nPositioning Auto-Calibrated",
                     textAlign: TextAlign.center,
                     style: const TextStyle(color: Colors.white54, fontSize: 10),
                   )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGridBackground() {
    return Container(
      color: Colors.black,
      child: CustomPaint(
        painter: GridPainter(),
        child: Container(),
      ),
    );
  }

  Widget _buildDeviceNode(dynamic device, bool isMe) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // CONNECTION LINE (Visual only)
        if (!isMe)
          Container(height: 20, width: 2, color: Colors.white24),
          
        // THE DEVICE ICON
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF00E676).withOpacity(0.2) : Colors.white10,
            shape: BoxShape.circle,
            border: Border.all(
              color: isMe ? const Color(0xFF00E676) : Colors.white30,
              width: isMe ? 2 : 1
            ),
            boxShadow: isMe ? [
               BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 20, spreadRadius: 5)
            ] : []
          ),
          child: Icon(
            device['type'] == 'mobile' ? Icons.smartphone : Icons.computer,
            color: Colors.white,
            size: 30,
          ),
        ),
        
        const SizedBox(height: 10),
        
        // THE BANNER (NAME)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24)
          ),
          child: Text(
            device['name'].toString().split(' [')[0], // Clean name
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          isMe ? "(You)" : "${device['x']}, ${device['y']}",
          style: const TextStyle(color: Colors.white38, fontSize: 9),
        )
      ],
    );
  }
}

// Simple Painter to draw a sci-fi grid
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white10..strokeWidth = 1;
    double step = 40;
    for(double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for(double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(old) => false;
}
