import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:provider/provider.dart';
import '../services/socket_service.dart';

class SpatialGestureLayer extends StatefulWidget {
  final Widget child;
  final Function(DragUpdateDetails)? onDragUpdate;
  final Map<String, dynamic> extraData; // Added to pass fileType
  
  const SpatialGestureLayer({
      Key? key, 
      required this.child, 
      this.onDragUpdate, 
      this.extraData = const {}
  }) : super(key: key);

  @override
  State<SpatialGestureLayer> createState() => _SpatialGestureLayerState();
}

class _SpatialGestureLayerState extends State<SpatialGestureLayer> {
  Offset _startPos = Offset.zero;
  Offset _lastPosition = Offset.zero;
  DateTime _startTime = DateTime.now();
  DateTime _lastTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final size = MediaQuery.of(context).size;

    return Listener(
      // 1. TOUCH DOWN
      onPointerDown: (event) {
        _startPos = event.position;
        _lastPosition = event.position;
        _startTime = DateTime.now();
        _lastTime = DateTime.now();
      },

      // 2. DRAGGING (Real-time Physics)
      onPointerMove: (event) {
        // Pass event up to parent (for dragging the UI preview)
        if (widget.onDragUpdate != null) {
            widget.onDragUpdate!(DragUpdateDetails(
                globalPosition: event.position, 
                delta: event.delta
            ));
        }

        final currentPos = event.position;
        final currentTime = DateTime.now();

        // Calculate Instant Velocity
        final timeDelta = currentTime.difference(_lastTime).inMilliseconds;
        double velocity = 0;
        
        if (timeDelta > 0) {
          final distance = (currentPos - _lastPosition).distance;
          velocity = (distance / timeDelta) * 1000; 
        }

        // Edge Detection ("Portals")
        String? activeEdge;
        double edgeThreshold = 20.0; 

        if (currentPos.dx > size.width - edgeThreshold) activeEdge = "RIGHT";
        else if (currentPos.dx < edgeThreshold) activeEdge = "LEFT";
        else if (currentPos.dy < edgeThreshold) activeEdge = "TOP";
        else if (currentPos.dy > size.height - edgeThreshold) activeEdge = "BOTTOM";

        // Send Data to Neural Core (Visuals Only)
        if (activeEdge != null || velocity > 500) {
           socketService.sendSwipeData({
             'x': currentPos.dx / size.width, 
             'y': currentPos.dy / size.height,
             'velocity': velocity,
             'edge': activeEdge,
             'isDragging': true,
             'action': 'move',
             ...widget.extraData // Sends 'fileType' so receiver shows correct icon
           });
        }

        _lastPosition = currentPos;
        _lastTime = currentTime;
      },

      // 3. RELEASE (The "Throw" Trigger)
      onPointerUp: (event) {
        final duration = DateTime.now().difference(_startTime).inMilliseconds;
        if (duration < 50) return; // Ignore taps

        // Calculate Overall Throw Velocity
        double dx = event.position.dx - _startPos.dx;
        double dy = event.position.dy - _startPos.dy;
        
        // Pixels per second
        double vx = (dx / duration) * 1000;
        double vy = (dy / duration) * 1000;

        // Tell Core we let go (hides the Ghost Hand)
        socketService.sendSwipeData({
            'isDragging': false, 
            'action': 'release', 
            'vx': vx, 
            'vy': vy, 
            ...widget.extraData
        });

        // --- THE MISSING LOGIC (TRANSFER TRIGGER) ---
        bool isFast = vx.abs() > 300 || vy.abs() > 300; 
        bool isFar = dx.abs() > (size.width * 0.3); 

        if (isFast || isFar) {
            // Haptic "Pop" to feel the throw
            HapticFeedback.mediumImpact();
            
            // Actually send the file
            print("Throw Detected! Velocity: $vx");
            socketService.triggerSwipeTransfer(vx, vy).catchError((e) {
               print("Transfer Failed: $e");
            });
        }
      },

      child: widget.child,
    );
  }
}
