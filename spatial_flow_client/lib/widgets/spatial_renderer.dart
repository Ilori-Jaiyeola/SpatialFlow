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

class _SpatialRendererState extends State<SpatialRenderer> with TickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  AnimationController? _pulseController;
  AnimationController? _entryController;
  Animation<Offset>? _slideAnimation;
  
  String? _currentFilePath;
  bool _isVideoInitialized = false;
  // STATE TRACKER
  bool _isAnimatingIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller != null && _controller!.value.isInitialized) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
        _controller!.pause();
      }
    }
  }

  @override
  void didUpdateWidget(SpatialRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final service = Provider.of<SocketService>(context, listen: false);
    
    // 1. TRIGGER START (When isReceiving turns True)
    if (service.isReceiving && !_isAnimatingIn) {
       _isAnimatingIn = true;
       _currentFilePath = null; // Clear old file
       _calculateEntryDirection(service);
       _entryController!.forward(from: 0); // SLIDE IN NOW
    }

    // 2. TRIGGER STOP/RESET
    if (!service.isReceiving) {
      _isAnimatingIn = false;
      _currentFilePath = null;
    }

    // 3. FILE ARRIVED
    if (service.isReceiving && service.lastReceivedFilePath != null && service.lastReceivedFilePath != _currentFilePath) {
       _currentFilePath = service.lastReceivedFilePath; 
       
       // Force Cache Clear
       if (service.incomingContentType != 'video') {
         FileImage(File(_currentFilePath!)).evict();
       }

       if (service.incomingContentType == 'video') {
         _initializeVideo(File(service.lastReceivedFilePath!));
       }
       // Note: We don't trigger animation here because it already ran in Step 1
    }
  }

  Future<void> _initializeVideo(File file) async {
    setState(() => _isVideoInitialized = false);
    final oldController = _controller;
    if (oldController != null) await oldController.dispose();

    _controller = VideoPlayerController.file(file);
    await _controller!.initialize();
    
    if (!mounted) return;
    
    setState(() {
       _isVideoInitialized = true;
       _controller!.play();
       _controller!.setLooping(true);
       _controller!.setVolume(1.0);
    });
  }

  void _calculateEntryDirection(SocketService service) {
    if (service.incomingSenderId == null) return;
    var sender = service.activeDevices.firstWhere((d) => d['id'] == service.incomingSenderId, orElse: () => null);
    var me = service.activeDevices.firstWhere((d) => d['id'] == service.myId, orElse: () => null);

    if (sender != null && me != null) {
       double dx = (sender['x'] ?? 0).toDouble() - (me['x'] ?? 0).toDouble();
       double startX = dx > 0 ? 1.0 : -1.0; 
       _slideAnimation = Tween<Offset>(begin: Offset(startX, 0), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    
    // Is the Container Active?
    bool showContainer = socketService.isReceiving;

    return Stack(
      children: [
        // 1. RADAR
        ..._buildNetworkMap(socketService, context),

        // 2. GHOST HAND
        if (swipeData != null && swipeData['isDragging'] == true)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width),
            top: (swipeData['y'] * MediaQuery.of(context).size.height),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Transform.rotate(
                angle: -0.2, 
                child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF00E676), width: 2)),
                  child: Center(child: Icon(contentType == 'video' ? Icons.videocam : Icons.image, color: Colors.white, size: 50)),
                ),
              ),
            ),
          ),

        // 3. FULL SCREEN UNIFIED CONTAINER
        if (showContainer)
          SlideTransition(
            position: _slideAnimation!,
            child: Positioned.fill(
              child: Stack(
                children: [
                  Container(color: Colors.black), 

                  Center(
                    child: _currentFilePath == null
                        // A. LOADING STATE (Placeholder Slide-In)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                               CircularProgressIndicator(color: const Color(0xFF00E676)),
                               const SizedBox(height: 20),
                               Text("Incoming ${socketService.incomingPlaceholderType}...", style: const TextStyle(color: Colors.white70, letterSpacing: 2))
                            ],
                          )
                        // B. CONTENT STATE (File Arrived)
                        : (contentType == 'video' 
                            ? (_isVideoInitialized && _controller != null && _controller!.value.size.width > 0
                                ? FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: _controller!.value.size.width,
                                      height: _controller!.value.size.height,
                                      child: VideoPlayer(_controller!),
                                    ),
                                  )
                                : const CircularProgressIndicator(color: Color(0xFF00E676))) 
                            : InteractiveViewer(
                                 minScale: 1.0, maxScale: 4.0,
                                 child: Image.file(
                                    File(_currentFilePath!), 
                                    key: ValueKey(_currentFilePath), 
                                    fit: BoxFit.contain, 
                                    gaplessPlayback: true,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.red, size: 50),
                                 )
                              )
                          ),
                  ),
                  
                  // CLOSE BUTTON
                  Positioned(
                    top: 50, right: 20,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white24,
                      onPressed: () {
                         socketService.clearView();
                         _controller?.pause(); 
                      },
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),

                  // OPEN BUTTON
                  if (_currentFilePath != null)
                    Positioned(
                      bottom: 40, left: 0, right: 0,
                      child: Center(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
                          onPressed: () => socketService.openLastFile(),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text("Open in Gallery")
                        ),
                      ),
                    )
                ],
              ),
            ),
          ),

        // 4. MOUSE
        if (socketService.showVirtualCursor)
           Positioned(left: socketService.virtualMousePos.dx, top: socketService.virtualMousePos.dy, child: const MouseCursorWidget()),
      ],
    );
  }

  // ... (Helpers Unchanged)
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
