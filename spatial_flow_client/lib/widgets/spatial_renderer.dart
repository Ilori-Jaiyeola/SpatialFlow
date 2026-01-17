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
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
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
    final contentPath = socketService.lastReceivedFilePath;
    final contentType = socketService.incomingContentType;

    return Stack(
      children: [
        // 1. RADAR
        ..._buildNetworkMap(socketService, context),

        // 2. GHOST HAND (Swipe Indicator)
        if (swipeData != null && swipeData['isDragging'] == true)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width),
            top: (swipeData['y'] * MediaQuery.of(context).size.height),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Transform.rotate(
                angle: -0.2, 
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                    boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 20, spreadRadius: 2)]
                  ),
                  child: Center(
                    child: Icon(contentType == 'video' ? Icons.videocam : Icons.image, color: Colors.white, size: 40)
                  ),
                ),
              ),
            ),
          ),

        // 3. RECEIVED MEDIA (FULL SCREEN & INTERACTIVE)
        if (contentPath != null)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // OPEN FILE ON TAP
                socketService.openLastFile();
              },
              child: Container(
                color: Colors.black, // Background to hide app
                child: Stack(
                  children: [
                    // A. THE CONTENT
                    Center(
                      child: contentType == 'video' 
                          ? _buildVideoPlayer(File(contentPath))
                          : Image.file(File(contentPath), fit: BoxFit.contain, width: double.infinity, height: double.infinity),
                    ),
                    
                    // B. OVERLAY UI (Open Button)
                    Positioned(
                      bottom: 50, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                          child: const Text("Tap anywhere to Open", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    
                    // C. SORTING BADGE
                    Positioned(
                      top: 50, right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        color: const Color(0xFF00E676),
                        child: Text(
                          contentType == 'video' ? "Saved to SpatialVideos" : "Saved to SpatialImages", 
                          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),

        // 4. VIRTUAL MOUSE
        if (socketService.showVirtualCursor)
           Positioned(
             left: socketService.virtualMousePos.dx,
             top: socketService.virtualMousePos.dy,
             child: const MouseCursorWidget(), 
           ),
      ],
    );
  }

  List<Widget> _buildNetworkMap(SocketService service, BuildContext context) {
    // (Keep same Radar logic as before)
    var me = service.activeDevices.firstWhere((d) => d['id'] == service.myId, orElse: () => null);
    if (me == null) return [];
    double myX = (me['x'] ?? 0).toDouble();
    double myY = (me['y'] ?? 0).toDouble();
    final size = MediaQuery.of(context).size;
    
    return service.activeDevices.map<Widget>((device) {
      if (device['id'] == service.myId) return const SizedBox(); 
      double relX = (device['x'] ?? 0).toDouble() - myX;
      double relY = (device['y'] ?? 0).toDouble() - myY;
      double screenX = (size.width / 2) + (relX * 150);
      double screenY = (size.height / 2) + (relY * 150);
      screenX = screenX.clamp(40.0, size.width - 40.0);
      screenY = screenY.clamp(120.0, size.height - 120.0);

      return Positioned(
        left: screenX - 30, top: screenY - 30,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
              child: Icon(device['type'] == 'mobile' ? Icons.smartphone : Icons.computer, color: Colors.white70, size: 20),
            ),
            const SizedBox(height: 4),
            Text(device['name'].toString().split(' [')[0], style: const TextStyle(color: Colors.white30, fontSize: 10))
          ],
        ),
      );
    }).toList();
  }

  Widget _buildVideoPlayer(File file) {
    if (_controller == null || _controller?.dataSource != file.path) {
        _controller?.dispose();
        _controller = VideoPlayerController.file(file)..initialize().then((_) { setState(() {}); _controller!.play(); _controller!.setLooping(true); });
    }
    if (!_controller!.value.isInitialized) return const CircularProgressIndicator(color: Color(0xFF00E676));
    return AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!));
  }
}

class MouseCursorWidget extends StatelessWidget {
  const MouseCursorWidget({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-5, -5), 
      child: Stack(children: [
        const Icon(Icons.near_me, color: Colors.black54, size: 32),
        const Icon(Icons.near_me, color: Color(0xFF00E676), size: 30),
      ]),
    );
  }
}
