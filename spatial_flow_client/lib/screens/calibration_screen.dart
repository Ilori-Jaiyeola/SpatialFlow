import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({Key? key}) : super(key: key);

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  // Local state to track where user drags the boxes
  // Map<SocketID, Offset(x,y)>
  Map<String, Offset> devicePositions = {}; 

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final devices = socketService.activeDevices;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Spatial Calibration"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.green),
            onPressed: () {
              // Convert Offset (pixels) to Grid Coordinates (0, 1, 2)
              List<Map<String, dynamic>> layoutPayload = [];
              
              devicePositions.forEach((id, offset) {
                // We divide by 150 to create a rough "grid" unit
                layoutPayload.add({
                  'id': id,
                  'x': offset.dx / 150, 
                  'y': offset.dy / 150
                });
              });

              socketService.updateLayout(layoutPayload);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Topology Saved to Neural Core"))
              );
            },
          )
        ],
      ),
      body: Stack(
        children: [
          // Background Grid
          CustomPaint(
            size: Size.infinite,
            painter: GridPainter(),
          ),
          
          // Draggable Device Icons
          ...devices.map((device) {
            String id = device['id'];
            String name = device['name'];
            bool isMe = id == socketService.myId;

            // Default position if not moved yet
            if (!devicePositions.containsKey(id)) {
              devicePositions[id] = const Offset(100, 100);
            }

            return Positioned(
              left: devicePositions[id]!.dx,
              top: devicePositions[id]!.dy,
              child: Draggable(
                feedback: _buildDeviceNode(name, isMe, true),
                childWhenDragging: Container(), // disappear when dragging
                onDragEnd: (details) {
                  setState(() {
                    // Snap to grid (optional, but keeps it clean)
                    // Adjust 'details.offset' to account for AppBar height if needed
                    devicePositions[id] = details.offset; 
                  });
                },
                child: _buildDeviceNode(name, isMe, false),
              ),
            );
          }).toList(),
          
          const Positioned(
            bottom: 20, 
            left: 20, 
            child: Text("Drag devices to match physical layout.", style: TextStyle(color: Colors.grey))
          )
        ],
      ),
    );
  }

  Widget _buildDeviceNode(String name, bool isMe, bool isFeedback) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF00E676) : const Color(0xFF444444),
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
          border: isFeedback ? Border.all(color: Colors.white, width: 2) : null
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isMe ? Icons.phone_android : Icons.computer, size: 40, color: Colors.white),
            const SizedBox(height: 10),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
            if (isMe) const Text("(You)", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }
}

// Simple Grid Background
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white10..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}