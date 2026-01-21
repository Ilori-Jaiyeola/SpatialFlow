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
  AnimationController? _entryController;
  AnimationController? _pulseController;
  Animation<Offset>? _slideAnimation;
  bool _isVideoReady = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
  }

  @override
  void didUpdateWidget(SpatialRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final service = Provider.of<SocketService>(context, listen: false);
    
    // OPEN CANVAS: Only on Release (Receiving)
    if (service.isReceiving && _entryController!.status == AnimationStatus.dismissed) {
        _calculateEntryDirection(service);
        _entryController!.forward();
    }
    
    // CLOSE CANVAS
    if (!service.isReceiving && _entryController!.status == AnimationStatus.completed) {
        _entryController!.reverse();
        _controller?.dispose();
        _controller = null;
        _isVideoReady = false;
    }

    // LOAD VIDEO
    if (service.lastReceivedFilePath != null && service.incomingContentType == 'video' && _controller == null) {
        _initVideo(File(service.lastReceivedFilePath!));
    }
  }

  Future<void> _initVideo(File file) async {
    _controller = VideoPlayerController.file(file);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {
      _isVideoReady = true;
      _controller!.play();
      _controller!.setLooping(true);
    });
  }

  void _calculateEntryDirection(SocketService service) {
    double startX = 1.0; 
    _slideAnimation = Tween<Offset>(begin: Offset(startX, 0), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _entryController?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<SocketService>(context);
    final swipeData = service.incomingSwipeData;
    
    // SAFETY CHECK 1: PREVENT SELF-RENDERING
    // If I am the sender, do not render this view (it blocks the dashboard)
    if (swipeData != null && swipeData['senderId'] == service.myId) {
      return const SizedBox();
    }

    bool isDragging = swipeData != null && swipeData['isDragging'] == true;
    
    // LOGIC: Show Canvas only if NOT dragging and (Receiving OR Has File)
    // This ensures Layer 3 (Black BG) doesn't cover Layer 2 (Ghost Hand)
    bool showCanvas = !isDragging && (service.isReceiving || service.lastReceivedFilePath != null);

    return Stack(
      children: [
        // LAYER 1: RADAR (Background)
        ..._buildNetworkMap(service, context),

        // LAYER 2: GHOST HAND (Interaction)
        if (isDragging)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width).clamp(0.0, MediaQuery.of(context).size.width - 120),
            top: (swipeData['y'] * MediaQuery.of(context).size.height).clamp(0.0, MediaQuery.of(context).size.height - 160),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Transform.rotate(
                angle: -0.2, 
                child: Container(
                  width: 120, height: 160,
                  decoration: BoxDecoration(
                    color: Colors.black54, 
                    borderRadius: BorderRadius.circular(20), 
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                    boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.3), blurRadius: 20, spreadRadius: 2)]
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       Icon(swipeData['fileType'] == 'video' ? Icons.videocam : Icons.image, color: Colors.white, size: 40),
                       const SizedBox(height: 10),
                       const Text("Incoming...", style: TextStyle(color: Colors.white, fontSize: 10))
                    ],
                  ),
                ),
              ),
            ),
          ),
          
        // LAYER 2.5: MOUSE
        if (service.showVirtualCursor)
           Positioned(
             left: service.virtualMousePos.dx, 
             top: service.virtualMousePos.dy, 
             child: const MouseCursorWidget()
           ),

        // LAYER 3: UNIFIED CANVAS (Content)
        if (showCanvas)
          SlideTransition(
            position: _slideAnimation!,
            child: Positioned.fill(
              child: Stack(
                children: [
                  // A. BLACK BACKGROUND
                  Container(color: Colors.black),

                  // B. CONTENT
                  Center(child: _buildContent(service)),

                  // C. CLOSE BUTTON
                  Positioned(
                    top: 50, right: 20,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white24,
                      onPressed: () => service.clearView(),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),

                  // D. STATUS
                  if (service.transferStatus == "INCOMING..." || service.transferStatus == "RECEIVING...")
                     Positioned(
                       bottom: 100, 
                       child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), 
                         color: Colors.black54, 
                         child: const Text("Syncing...", style: TextStyle(color: Colors.white))
                       )
                     )
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(SocketService service) {
    // 1. VIDEO
    if (service.incomingContentType == 'video' && _isVideoReady && _controller != null) {
       return AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!));
    }
    // 2. FILE (High Res)
    if (service.lastReceivedFilePath != null && service.incomingContentType != 'video') {
       return Image.file(File(service.lastReceivedFilePath!), key: ValueKey(service.lastReceivedFilePath), fit: BoxFit.contain);
    }
    // 3. HOLOGRAM (RAM Preview)
    if (service.incomingThumbnail != null) {
       return Image.memory(service.incomingThumbnail!, fit: BoxFit.contain, gaplessPlayback: true);
    }
    // 4. LOADING
    return const CircularProgressIndicator(color: Color(0xFF00E676));
  }

  // --- HELPERS ---
  List<Widget> _buildNetworkMap(SocketService service, BuildContext context) {
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
}

class MouseCursorWidget extends StatelessWidget {
  const MouseCursorWidget({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Transform.translate(offset: const Offset(-5, -5), child: Stack(children: [const Icon(Icons.near_me, color: Colors.black54, size: 32), const Icon(Icons.near_me, color: Color(0xFF00E676), size: 30)]));
  }
}
