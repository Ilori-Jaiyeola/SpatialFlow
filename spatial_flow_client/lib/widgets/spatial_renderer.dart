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
      duration: const Duration(seconds: 2),
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
        // 1. Ghost Hand (The Swipe Indicator)
        if (swipeData != null && swipeData['isDragging'] == true)
          Positioned(
            left: (swipeData['x'] * MediaQuery.of(context).size.width),
            top: (swipeData['y'] * MediaQuery.of(context).size.height),
            child: FadeTransition(
              opacity: _pulseController!,
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00E676).withOpacity(0.5), blurRadius: 20, spreadRadius: 5)
                  ]
                ),
                child: const Icon(Icons.touch_app, color: Colors.white, size: 30),
              ),
            ),
          ),

        // 2. Incoming Video Stream
        if (contentType == 'video' && content != null)
           _buildVideoPlayer(socketService), // Pass service to helper
           
        // 3. Incoming Image
        if (contentType == 'image' && content != null)
          Center(
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00E676), width: 2),
                borderRadius: BorderRadius.circular(20),
                image: DecorationImage(
                   // In a real app, this would be a NetworkImage or FileImage
                   // For this prototype, we assume it's a local file path sent over
                   image: FileImage(File(content)), 
                   fit: BoxFit.cover
                )
              ),
            ),
          )
      ],
    );
  }

  Widget _buildVideoPlayer(SocketService socketService) {
    // If controller is missing or pointing to wrong file, re-initialize
    if (_controller == null) {
        _controller = VideoPlayerController.file(File(socketService.incomingContent))
          ..initialize().then((_) {
            setState(() {});
            _controller!.play();
          });
    }
    
    // SYNC LOGIC: If the timestamp drifts, snap it back
    // FIX IS HERE: We wrap the int in Duration()
    if (_controller!.value.isInitialized) {
       int remoteTime = socketService.currentVideoTimestamp;
       int localTime = _controller!.value.position.inMilliseconds;
       if ((remoteTime - localTime).abs() > 500) {
         _controller!.seekTo(Duration(milliseconds: remoteTime));
       }
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}
