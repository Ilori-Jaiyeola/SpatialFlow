import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../services/socket_service.dart';
import 'dart:io';

class SpatialRenderer extends StatefulWidget {
  const SpatialRenderer({Key? key}) : super(key: key);

  @override
  State<SpatialRenderer> createState() => _SpatialRendererState();
}

class _SpatialRendererState extends State<SpatialRenderer> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final swipeData = socketService.incomingSwipeData;
    
    // --- 1. VISUALIZE NETWORK MAP (Automatic) ---
    // This draws the little dots showing where other devices are relative to you
    List<Widget> networkMap = _buildNetworkMap(socketService, context);

    return Stack(
      children: [
        ...networkMap,

        // --- 2. GHOST HAND (Incoming Swipe) ---
        if (swipeData != null && swipeData['isDragging'] == true)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width),
            top: (swipeData['y'] * MediaQuery.of(context).size.height),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Column(
                children: [
                   Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00E676).withOpacity(0.6), blurRadius: 30, spreadRadius: 5)
                      ]
                    ),
                    child: const Icon(Icons.touch_app, color: Colors.white, size: 30),
                  ),
                  // Show who is swiping
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
                    child: Text("Incoming Signal", style: const TextStyle(color: Colors.white, fontSize: 10)),
                  )
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildNetworkMap(SocketService service, BuildContext context) {
    // This finds MY position
    var me = service.activeDevices.firstWhere((d) => d['id'] == service.myId, orElse: () => null);
    if (me == null) return [];

    double myX = (me['x'] ?? 0).toDouble();
    double myY = (me['y'] ?? 0).toDouble();
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    return service.activeDevices.map<Widget>((device) {
      if (device['id'] == service.myId) return const SizedBox(); // Don't draw myself

      // Calculate relative position
      double relX = (device['x'] ?? 0).toDouble() - myX;
      double relY = (device['y'] ?? 0).toDouble() - myY;

      // Scale it for the screen (1 unit = 150 pixels)
      double screenX = centerX + (relX * 150);
      double screenY = centerY + (relY * 150);

      // Clamp to screen edges so they don't disappear
      screenX = screenX.clamp(20.0, size.width - 20.0);
      screenY = screenY.clamp(100.0, size.height - 100.0);

      return Positioned(
        left: screenX - 25,
        top: screenY - 25,
        child: Column(
          children: [
            const Icon(Icons.router, color: Colors.white54),
            Text(
              device['name'].toString().split(' [')[0], // Show simple name
              style: const TextStyle(color: Colors.white30, fontSize: 10)
            )
          ],
        ),
      );
    }).toList();
  }
}
