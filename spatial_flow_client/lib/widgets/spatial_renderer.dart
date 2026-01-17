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
    final content = socketService.incomingContent;
    final contentType = socketService.incomingContentType;

    return Stack(
      children: [
        // --- 1. NETWORK RADAR (Visualizes Device Topology) ---
        ..._buildNetworkMap(socketService, context),

        // --- 2. GHOST HAND (The Swipe Indicator) ---
        if (swipeData != null && swipeData['isDragging'] == true)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width),
            top: (swipeData['y'] * MediaQuery.of(context).size.height),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Transform.rotate(
                angle: -0.2, // Slight tilt for dynamic feel
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
                    ]
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background Grid Pattern
                        Opacity(
                          opacity: 0.1,
                          child: GridView.count(
                            crossAxisCount: 4,
                            children: List.generate(16, (_) => Container(
                              margin: const EdgeInsets.all(2),
                              color: Colors.white,
                            )),
                          ),
                        ),
                        // The Content Icon
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getIconForType(socketService.incomingContentType), 
                              color: Colors.white, 
                              size: 40
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              "INCOMING", 
                              style: TextStyle(
                                color: Color(0xFF00E676), 
                                fontSize: 10, 
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5
                              )
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // --- 3. RECEIVED MEDIA (The Actual File) ---
        
        // VIDEO PLAYER
        if (contentType == 'video' && content != null)
           _buildVideoPlayer(socketService), 
           
        // IMAGE VIEWER
        if (contentType == 'image' && content != null)
          Center(
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00E676), width: 2),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
                image: DecorationImage(
                   image: FileImage(File(content)), 
                   fit: BoxFit.cover
                )
              ),
            ),
          )
      ],
    );
  }

  // --- HELPER: RADAR MAP ---
  List<Widget> _buildNetworkMap(SocketService service, BuildContext context) {
    // 1. Find MY position in the server's list
    var me = service.activeDevices.firstWhere(
      (d) => d['id'] == service.myId, 
      orElse: () => null
    );
    if (me == null) return [];

    double myX = (me['x'] ?? 0).toDouble();
    double myY = (me['y'] ?? 0).toDouble();
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    return service.activeDevices.map<Widget>((device) {
      if (device['id'] == service.myId) return const SizedBox(); // Don't draw self

      // 2. Calculate Relative Position
      double relX = (device['x'] ?? 0).toDouble() - myX;
      double relY = (device['y'] ?? 0).toDouble() - myY;

      // 3. Map to Screen Coordinates (1 Unit = 150 Pixels)
      double screenX = centerX + (relX * 150);
      double screenY = centerY + (relY * 150);

      // Clamp to keep onscreen
      screenX = screenX.clamp(40.0, size.width - 40.0);
      screenY = screenY.clamp(120.0, size.height - 120.0);

      return Positioned(
        left: screenX - 30, // Center the widget
        top: screenY - 30,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white10,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24)
              ),
              child: Icon(
                device['type'] == 'mobile' ? Icons.smartphone : Icons.computer, 
                color: Colors.white70,
                size: 20
              ),
            ),
            const SizedBox(height: 4),
            Text(
              device['name'].toString().split(' [')[0], // Show simple name
              style: const TextStyle(color: Colors.white30, fontSize: 10)
            )
          ],
        ),
      );
    }).toList();
  }

  // --- HELPER: VIDEO PLAYER ---
  Widget _buildVideoPlayer(SocketService socketService) {
    // Initialize logic
    if (_controller == null || _controller?.dataSource != socketService.incomingContent) {
        _controller?.dispose();
        _controller = VideoPlayerController.file(File(socketService.incomingContent))
          ..initialize().then((_) {
            setState(() {});
            _controller!.play();
            _controller!.setLooping(true);
          });
    }
    
    // Sync Logic (Snap to timestamp if drifting)
    if (_controller!.value.isInitialized) {
       int remoteTime = socketService.currentVideoTimestamp;
       int localTime = _controller!.value.position.inMilliseconds;
       if ((remoteTime - localTime).abs() > 500) {
         _controller!.seekTo(Duration(milliseconds: remoteTime));
       }
    }

    if (!_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)));
    }

    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00E676), width: 1),
          boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 50)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }

  // --- HELPER: ICON TYPE ---
  IconData _getIconForType(String? type) {
    if (type == 'video') return Icons.videocam;
    if (type == 'image') return Icons.image;
    return Icons.insert_drive_file;
  }
}
