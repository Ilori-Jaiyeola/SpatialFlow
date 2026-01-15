import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';
import 'dart:io';
import '../services/socket_service.dart';

class SpatialRenderer extends StatefulWidget {
  const SpatialRenderer({Key? key}) : super(key: key);

  @override
  State<SpatialRenderer> createState() => _SpatialRendererState();
}

class _SpatialRendererState extends State<SpatialRenderer> {
  VideoPlayerController? _videoController;
  
  // Track previous content to detect changes
  dynamic _lastContent; 

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _initializeVideo(File file) {
    // If we are already playing this file, don't re-init
    if (_lastContent == file) return;

    _videoController?.dispose();
    _videoController = VideoPlayerController.file(file)
      ..initialize().then((_) {
        setState(() {});
        _videoController!.play(); // Start playing
        _videoController!.setVolume(0); // Mute receiver (optional, avoids echo)
      });
    _lastContent = file;
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    final data = socketService.incomingSwipeData;
    final content = socketService.incomingContent;
    final type = socketService.incomingContentType;
    final size = MediaQuery.of(context).size;

    // Check visibility
    if (data == null || content == null || data['isDragging'] == false) {
      // Pause video if we stop dragging? 
      // For now, let's keep it simple:
      return const SizedBox.shrink(); 
    }

    // --- VIDEO SYNC LOGIC ---
    // If it's a video, sync the time with the sender
    if (type == 'video' && _videoController != null && _videoController!.value.isInitialized) {
       Duration senderTime = socketService.currentVideoTimestamp;
       
       // Only seek if the difference is noticeable (> 500ms) to prevent stuttering
       if ((_videoController!.value.position - senderTime).abs().inMilliseconds > 500) {
          _videoController!.seekTo(senderTime);
       }
    }

    // Initialize video if needed
    if (type == 'video' && content is File) {
      _initializeVideo(content);
    }

    // --- COORDINATE MATH (Same as before) ---
    double normalizedX = (data['x'] ?? 0.5).toDouble();
    double renderX = 0;
    double objectWidth = 300.0; 

    if (data['edge'] == 'RIGHT') {
        double progress = (normalizedX - 0.5) * 2;
        renderX = (progress * objectWidth) - objectWidth;
    }

    return Positioned(
      left: renderX, 
      top: (data['y'] ?? 0.5) * size.height - 150, 
      child: Opacity(
        opacity: 0.9,
        child: Container(
          width: objectWidth,
          height: 300,
          decoration: BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
            borderRadius: BorderRadius.circular(20),
            color: Colors.black // Background for video
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: _buildContent(type, content),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(String? type, dynamic content) {
    if (type == 'image' && content is String) {
      return Image.memory(base64Decode(content), fit: BoxFit.cover);
    } else if (type == 'video' && _videoController != null && _videoController!.value.isInitialized) {
      return VideoPlayer(_videoController!);
    } else {
      return const Center(child: CircularProgressIndicator());
    }
  }
}