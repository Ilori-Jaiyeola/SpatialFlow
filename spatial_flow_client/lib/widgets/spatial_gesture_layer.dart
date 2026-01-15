import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';

class SpatialGestureLayer extends StatefulWidget {
  final Widget child;
  const SpatialGestureLayer({Key? key, required this.child}) : super(key: key);

  @override
  State<SpatialGestureLayer> createState() => _SpatialGestureLayerState();
}

class _SpatialGestureLayerState extends State<SpatialGestureLayer> {
  // We track the last position to calculate velocity manually if needed
  Offset _lastPosition = Offset.zero;
  DateTime _lastTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final size = MediaQuery.of(context).size;

    return Listener(
      // 1. When the user touches the screen
      onPointerDown: (event) {
        _lastPosition = event.position;
        _lastTime = DateTime.now();
      },

      // 2. As the user moves their finger (Real-time tracking)
      onPointerMove: (event) {
        final currentPos = event.position;
        final currentTime = DateTime.now();

        // Calculate Velocity (Pixels per millisecond)
        // AI needs this to predict if you are "throwing" the file.
        final timeDelta = currentTime.difference(_lastTime).inMilliseconds;
        double velocity = 0;
        
        if (timeDelta > 0) {
          final distance = (currentPos - _lastPosition).distance;
          velocity = (distance / timeDelta) * 1000; // pixels per second
        }

        // Check if we are at an edge (The "Portal" Logic)
        String? activeEdge;
        double edgeThreshold = 20.0; // pixels from edge

        if (currentPos.dx > size.width - edgeThreshold) activeEdge = "RIGHT";
        else if (currentPos.dx < edgeThreshold) activeEdge = "LEFT";
        else if (currentPos.dy < edgeThreshold) activeEdge = "TOP";
        else if (currentPos.dy > size.height - edgeThreshold) activeEdge = "BOTTOM";

        // Send Data to the Neural Core
        if (activeEdge != null || velocity > 500) {
           // We normalize X and Y to 0.0 - 1.0 (Percentage of screen)
           // This ensures a phone (small) maps correctly to a laptop (big)
           socketService.sendSwipeData({
             'x': currentPos.dx / size.width, 
             'y': currentPos.dy / size.height,
             'velocity': velocity,
             'edge': activeEdge, // activeEdge is null if not at edge
             'isDragging': true
           });
        }

        _lastPosition = currentPos;
        _lastTime = currentTime;
      },

      // 3. When user lifts finger
      onPointerUp: (event) {
        socketService.sendSwipeData({
          'isDragging': false,
          'action': 'release'
        });
      },

      child: widget.child,
    );
  }
}