import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../services/socket_service.dart';
import 'dart:io';
import 'dart:typed_data';

class SpatialRenderer extends StatefulWidget {
  const SpatialRenderer({Key? key}) : super(key: key);

  @override
  State<SpatialRenderer> createState() => _SpatialRendererState();
}

class _SpatialRendererState extends State<SpatialRenderer> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  AnimationController? _entryController;
  Animation<Offset>? _slideAnimation;
  
  bool _isVideoReady = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
  }

  @override
  void didUpdateWidget(SpatialRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final service = Provider.of<SocketService>(context, listen: false);
    
    // 1. TRIGGER ANIMATION (When receiving starts)
    if (service.isReceiving && _entryController!.status == AnimationStatus.dismissed) {
        _calculateEntryDirection(service);
        _entryController!.forward();
    }
    
    // 2. RESET (When view closes)
    if (!service.isReceiving && _entryController!.status == AnimationStatus.completed) {
        _entryController!.reverse();
        _controller?.dispose();
        _controller = null;
        _isVideoReady = false;
    }

    // 3. INIT VIDEO (Only when full file arrives)
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
    // Basic direction logic
    double startX = 1.0; 
    _slideAnimation = Tween<Offset>(begin: Offset(startX, 0), end: Offset.zero).animate(CurvedAnimation(parent: _entryController!, curve: Curves.easeOutExpo));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _entryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<SocketService>(context);
    
    // If not receiving and no file, hide.
    if (!service.isReceiving && service.lastReceivedFilePath == null) return const SizedBox();

    return Stack(
      children: [
        // RADAR MAP (Background)
        // ... (Keep your radar helper here if needed) ...

        // THE UNIFIED CANVAS
        SlideTransition(
          position: _slideAnimation!,
          child: Positioned.fill(
            child: Stack(
              children: [
                // 1. BLACK BACKGROUND
                Container(color: Colors.black),

                // 2. CONTENT SWITCHER
                Center(
                  child: _buildContent(service),
                ),

                // 3. CLOSE BUTTON
                Positioned(
                  top: 50, right: 20,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white24,
                    onPressed: () => service.clearView(),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                
                // 4. STATUS
                if (service.transferStatus == "INCOMING..." || service.transferStatus == "RECEIVING...")
                   Positioned(
                     bottom: 100,
                     child: Container(
                       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                       color: Colors.black54,
                       child: const Text("Syncing...", style: TextStyle(color: Colors.white)),
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
    // A. IF VIDEO & READY -> SHOW VIDEO PLAYER
    if (service.incomingContentType == 'video' && _isVideoReady && _controller != null) {
       return AspectRatio(
         aspectRatio: _controller!.value.aspectRatio,
         child: VideoPlayer(_controller!),
       );
    }

    // B. IF FILE PATH EXISTS (Full Res Image) -> SHOW FILE
    if (service.lastReceivedFilePath != null && service.incomingContentType != 'video') {
       return Image.file(
         File(service.lastReceivedFilePath!),
         key: ValueKey(service.lastReceivedFilePath),
         fit: BoxFit.contain,
       );
    }

    // C. PRIORITY: SHOW HOLOGRAM (RAM PREVIEW)
    // This renders INSTANTLY because it's in memory, not on disk.
    if (service.incomingThumbnail != null) {
       return Image.memory(
         service.incomingThumbnail!,
         fit: BoxFit.contain,
         gaplessPlayback: true,
       );
    }

    // D. FALLBACK LOADING
    return const CircularProgressIndicator(color: Color(0xFF00E676));
  }
}
