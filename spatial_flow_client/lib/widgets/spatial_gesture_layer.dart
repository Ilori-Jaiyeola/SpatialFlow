import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import '../services/socket_service.dart';

class SpatialGestureLayer extends StatefulWidget {
  final Widget child;
  final Function(DragUpdateDetails)? onDragUpdate;
  final Map<String, dynamic> extraData; 
  
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
      // 1. TOUCH START
      onPointerDown: (event) {
        _startPos = event.position;
        _lastPosition = event.position;
        _startTime = DateTime.now();
        _lastTime = DateTime.now();
      },

      // 2. DRAGGING (Visual Feedback Only)
      onPointerMove: (event) {
        if (widget.onDragUpdate != null) {
            widget.onDragUpdate!(DragUpdateDetails(
                globalPosition: event.position, 
                delta: event.delta
            ));
        }

        final currentPos = event.position;
        final currentTime = DateTime.now();

        // Calculate Instant Velocity for the AI/Visuals
        final timeDelta = currentTime.difference(_lastTime).inMilliseconds;
        double velocity = 0;
        if (timeDelta > 0) {
          final distance = (currentPos - _lastPosition).distance;
          velocity = (distance / timeDelta) * 1000; 
        }

        // Detect Screen Edges ("Portals")
        String? activeEdge;
        double edgeThreshold = 30.0; // Sensitivity

        if (currentPos.dx > size.width - edgeThreshold) activeEdge = "RIGHT";
        else if (currentPos.dx < edgeThreshold) activeEdge = "LEFT";
        else if (currentPos.dy < edgeThreshold) activeEdge = "TOP";
        else if (currentPos.dy > size.height - edgeThreshold) activeEdge = "BOTTOM";

        // Send Data to Neural Core
        if (activeEdge != null || velocity > 400) {
           socketService.sendSwipeData({
             'x': currentPos.dx / size.width, 
             'y': currentPos.dy / size.height,
             'velocity': velocity,
             'edge': activeEdge,
             'isDragging': true,
             'action': 'move',
             ...widget.extraData 
           });
        }

        _lastPosition = currentPos;
        _lastTime = currentTime;
      },

      // 3. RELEASE (The Physics Trigger)
      onPointerUp: (event) {
        final duration = DateTime.now().difference(_startTime).inMilliseconds;
        if (duration < 50) return; // Ignore taps

        double dx = event.position.dx - _startPos.dx;
        double dy = event.position.dy - _startPos.dy;
        
        // Calculate Raw Velocity (Pixels/sec)
        double vx = (dx / duration) * 1000;
        double vy = (dy / duration) * 1000;

        // --- AXIS LOCKING (Forgiving UI) ---
        // Determine the user's intent: Horizontal or Vertical?
        bool isHorizontal = vx.abs() > vy.abs();
        
        // Lock the non-dominant axis to 0
        if (isHorizontal) {
           vy = 0; 
        } else {
           vx = 0;
        }

        // Inform Core that drag ended
        socketService.sendSwipeData({
            'isDragging': false, 
            'action': 'release', 
            'vx': vx, 
            'vy': vy, 
            ...widget.extraData
        });

        // Trigger Transfer if velocity is high
        bool isFast = (isHorizontal ? vx.abs() : vy.abs()) > 300; 
        bool isFar = dx.abs() > (size.width * 0.3); // Or if dragged far enough

        if (isFast || isFar) {
            HapticFeedback.mediumImpact();
            // We pass the "Clean" (Locked) velocities to the router
            socketService.triggerSwipeTransfer(vx, vy).catchError((e) {
               print("Transfer Failed: $e");
            });
        }
      },

      child: widget.child,
    );
  }
}
