import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../widgets/glass_box.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({Key? key}) : super(key: key);

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  // Mock representation of connected screens
  // In a real app, this would be populated by the server's device list
  List<Map<String, dynamic>> _screenPositions = [
    {'id': '1', 'name': 'My Phone', 'x': 0.0, 'y': 0.0, 'color': Colors.blue},
    {'id': '2', 'name': 'PC Node', 'x': 150.0, 'y': 0.0, 'color': Colors.purple},
  ];

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Spatial Calibration"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
              ),
            ),
          ),
          
          // Draggable Grid
          Stack(
            children: _screenPositions.map((screen) {
              return Positioned(
                left: 100 + (screen['x'] as double), // Center offset
                top: 200 + (screen['y'] as double),
                child: Draggable(
                  feedback: _buildScreenNode(screen, 1.1),
                  childWhenDragging: Opacity(opacity: 0.3, child: _buildScreenNode(screen, 1.0)),
                  onDragEnd: (details) {
                    setState(() {
                      // Update local position relative to origin
                      screen['x'] = details.offset.dx - 100;
                      screen['y'] = details.offset.dy - 200;
                    });
                    
                    // FIX IS HERE: Wrap the List in a Map
                    socketService.updateLayout({
                        'screens': _screenPositions
                    });
                  },
                  child: _buildScreenNode(screen, 1.0),
                ),
              );
            }).toList(),
          ),

          // Instructions
          Positioned(
            bottom: 50, left: 20, right: 20,
            child: GlassBox(
              child: const Text(
                "Drag nodes to arrange your physical setup.\nSpatialFlow will calculate swipe trajectories.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildScreenNode(Map<String, dynamic> screen, double scale) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 100, height: 160,
        decoration: BoxDecoration(
          color: screen['color'],
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
          border: Border.all(color: Colors.white, width: 2)
        ),
        child: Center(
          child: Text(screen['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
