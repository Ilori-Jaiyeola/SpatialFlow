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

class _SpatialRendererState extends State<SpatialRenderer> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  AnimationController? _pulseController;
  
  // UNIFIED CANVAS ANIMATION
  AnimationController? _entryController;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    
    // Setup Entry Animation
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
  }

  @override
  void didUpdateWidget(SpatialRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger animation when new file arrives
    final service = Provider.of<SocketService>(context, listen: false);
    if (service.lastReceivedFilePath != null && !_entryController!.isCompleted) {
       _calculateEntryDirection(service);
       _entryController!.forward(from: 0);
    }
  }

  void _calculateEntryDirection(SocketService service) {
    if (service.incomingSenderId == null) return;
    
    // Find Sender
    var sender = service.activeDevices.firstWhere((d) => d['id'] == service.incomingSenderId, orElse: () => null);
    var me = service.activeDevices.firstWhere((d) => d['id'] == service.myId, orElse: () => null);

    if (sender != null && me != null) {
       double dx = (sender['x'] ?? 0) - (me['x'] ?? 0);
       // If sender is to my Left (dx < 0), slide from Left (-1.0, 0)
       // If sender is to my Right (dx > 0), slide from Right (1.0, 0)
       double startX = dx > 0 ? 1.0 : -1.0; 
       _slideAnimation = Tween<Offset>(begin: Offset(startX, 0), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pulseController?.dispose();
    _entryController?.dispose();
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
        // 1. RADAR MAP
        ..._buildNetworkMap(socketService, context),

        // 2. GHOST SWIPE INDICATOR
        if (swipeData != null && swipeData['isDragging'] == true)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width),
            top: (swipeData['y'] * MediaQuery.of(context).size.height),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Transform.rotate(
                angle: -0.2, 
                child: Container(
                  width: 150, height: 150, // BIGGER
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF00E676), width: 2)),
                  child: Center(child: Icon(contentType == 'video' ? Icons.videocam : Icons.image, color: Colors.white, size: 50)),
                ),
              ),
            ),
          ),

        // 3. UNIFIED CANVAS: FULL SCREEN CONTENT
        if (contentPath != null)
          SlideTransition(
            position: _slideAnimation!,
            child: Positioned.fill(
              child: GestureDetector(
                onTap: () => socketService.openLastFile(),
                child: Container(
                  color: Colors.black, 
                  child: Stack(
                    children: [
                      Center(
                        child: contentType == 'video' 
                            ? _buildVideoPlayer(File(contentPath))
                            : Image.file(File(contentPath), fit: BoxFit.contain, width: double.infinity, height: double.infinity),
                      ),
                      // CLOSE BUTTON
                      Positioned(
                         top: 40, left: 20,
                         child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () {
                           // Logic to clear view could be added to service, or just let user tap to open
                         })
                      ),
                      Positioned(
                        bottom: 50, left: 0, right: 0,
                        child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)), child: const Text("Tap to Open Gallery", style: TextStyle(color: Colors.white)))),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 4. MOUSE
        if (socketService.showVirtualCursor)
           Positioned(left: socketService.virtualMousePos.dx, top: socketService.virtualMousePos.dy, child: const MouseCursorWidget()),
      ],
    );
  }
  
  // ... (Keep _buildNetworkMap, _buildVideoPlayer, MouseCursorWidget exactly as before)
  List<Widget> _buildNetworkMap(SocketService service, BuildContext context) {
    // (Copy existing logic from previous response)
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
      return Positioned(left: screenX - 30, top: screenY - 30, child: Column(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: Icon(device['type'] == 'mobile' ? Icons.smartphone : Icons.computer, color: Colors.white70, size: 20)), const SizedBox(height: 4), Text(device['name'].toString().split(' [')[0], style: const TextStyle(color: Colors.white30, fontSize: 10))]));
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
    return Transform.translate(offset: const Offset(-5, -5), child: Stack(children: [const Icon(Icons.near_me, color: Colors.black54, size: 32), const Icon(Icons.near_me, color: Color(0xFF00E676), size: 30)]));
  }
}
