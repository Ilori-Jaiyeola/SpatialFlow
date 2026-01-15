import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';

class GhostOverlay extends StatelessWidget {
  const GhostOverlay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final data = socketService.incomingSwipeData;
    final size = MediaQuery.of(context).size;

    // If no data is coming in, show nothing.
    if (data == null || data['isDragging'] == false) {
      return const SizedBox.shrink();
    }

    // --- COORDINATE MAPPING LOGIC ---
    // If the sender is at "Right Edge" (x=1.0), we should appear at "Left Edge" (x=0.0).
    
    double ghostX = 0;
    double ghostY = (data['y'] ?? 0.5).toDouble() * size.height; // Match Y height

    // Determine entrance side based on sender's edge
    // Note: This logic assumes the Laptop is to the RIGHT of the Phone.
    if (data['edge'] == 'RIGHT') {
      // Incoming from Left side of THIS screen
      ghostX = 0;
    } else if (data['edge'] == 'LEFT') {
      // Incoming from Right side of THIS screen
      ghostX = size.width - 100;
    } else {
      // Default fallback: map the normalized X directly
      ghostX = (data['x'] ?? 0.5).toDouble() * size.width;
    }

    // AI Prediction Visuals
    // If the AI predicts a "Throw", we make the ghost glow or move faster.
    bool isHighVelocity = (data['aiPrediction']?['urgency'] == 'high');

    return Positioned(
      left: ghostX,
      top: ghostY - 50, // center vertically on finger
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50), // Smooth updates
        width: 100,
        height: 100,
        decoration: BoxDecoration(
            color: isHighVelocity ? Colors.redAccent.withOpacity(0.8) : Colors.blueAccent.withOpacity(0.6),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              if (isHighVelocity)
                const BoxShadow(color: Colors.red, blurRadius: 20, spreadRadius: 5)
            ]
        ),
        child: const Center(
          child: Icon(Icons.file_present, color: Colors.white, size: 40),
        ),
      ),
    );
  }
}