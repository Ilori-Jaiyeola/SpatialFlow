import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart'; 
import 'dart:io';
import 'dart:ui'; 
import 'package:wakelock_plus/wakelock_plus.dart'; 
import 'package:desktop_drop/desktop_drop.dart'; 
import 'services/socket_service.dart';
import 'widgets/spatial_renderer.dart';
import 'widgets/glass_box.dart'; 
import 'screens/calibration_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SocketService())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpatialFlow',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black, 
        primaryColor: const Color(0xFF00E676),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<File> _selectedFiles = []; 
  String? _fileType;
  VideoPlayerController? _senderVideoController;
  Offset _dragPosition = const Offset(100, 400);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    Provider.of<SocketService>(context, listen: false).startDiscovery();
  }

  @override
  void dispose() {
    _senderVideoController?.dispose();
    super.dispose();
  }

  void _onFilesDropped(List<XFile> files) => _processFiles(files);
  
  Future<void> _pickMedia(String type) async {
    final picker = ImagePicker();
    List<XFile> pickedFiles = [];
    if (type == 'video') {
      final XFile? vid = await picker.pickVideo(source: ImageSource.gallery);
      if (vid != null) pickedFiles.add(vid);
    } else {
      pickedFiles = await picker.pickMultiImage();
    }
    _processFiles(pickedFiles);
  }

  void _processFiles(List<XFile> files) {
    if (files.isEmpty) return;
    String ext = files.first.path.split('.').last.toLowerCase();
    String type = (['mp4', 'mov', 'avi', 'mkv'].contains(ext) || _fileType == 'video') ? 'video' : 'image';

    setState(() {
      _selectedFiles = files.map((x) => File(x.path)).toList();
      _fileType = type;
      _dragPosition = const Offset(50, 200); 
    });

    if (type == 'video') {
       _initVideoPlayer(_selectedFiles.first);
    }
    
    Provider.of<SocketService>(context, listen: false).broadcastContent(_selectedFiles, type);
  }

  void _initVideoPlayer(File file) async {
    final old = _senderVideoController;
    if (old != null) await old.dispose();

    _senderVideoController = VideoPlayerController.file(file);
    await _senderVideoController!.initialize();
    
    if (!mounted) return;

    setState(() {
      _senderVideoController!.setVolume(0); 
      _senderVideoController!.play();
      _senderVideoController!.setLooping(true);
    });
  }

  void _clearSender() {
    setState(() {
      _selectedFiles = [];
      _senderVideoController?.dispose();
      _senderVideoController = null;
    });
    Provider.of<SocketService>(context, listen: false).clearStagedFiles();
  }
  
  void _manualSend() {
      final service = Provider.of<SocketService>(context, listen: false);
      service.triggerSwipeTransfer(500, 0); 
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);

    return DropTarget(
      onDragDone: (details) => _onFilesDropped(details.files),
      child: SpatialGestureLayer(
        extraData: {
           'fileType': _fileType ?? 'file',
           'timestamp': DateTime.now().millisecondsSinceEpoch
        },
        onDragUpdate: (details) {
          setState(() => _dragPosition += details.delta);
        },
        child: Scaffold(
          extendBodyBehindAppBar: true, 
          appBar: AppBar(
            title: const Text("SpatialFlow", style: TextStyle(fontWeight: FontWeight.w300, letterSpacing: 2)),
            backgroundColor: Colors.transparent, 
            elevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withOpacity(0.2)),
              ),
            ),
            actions: [
               IconButton(
                 icon: const Icon(Icons.grid_view, color: Colors.white70),
                 onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalibrationScreen())),
               ),
            ],
          ),
          floatingActionButton: _buildFab(), 
          body: Stack(
            children: [
              _buildBackground(),

              // 1. DASHBOARD UI
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGlassStatusCard(socketService),
                      const SizedBox(height: 30),
                      const Text("NEURAL MESH", style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12)),
                      const SizedBox(height: 15),
                      Expanded(
                        child: socketService.activeDevices.isEmpty
                            ? const Center(child: Text("Searching for Neural Core...", style: TextStyle(color: Colors.white30)))
                            : ListView.builder(
                                itemCount: socketService.activeDevices.length,
                                itemBuilder: (context, index) {
                                  return _buildGlassDeviceTile(socketService.activeDevices[index], socketService.myId);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. SENDER PREVIEW (Draggable)
              if (_selectedFiles.isNotEmpty)
                Positioned(
                  left: _dragPosition.dx,
                  top: _dragPosition.dy,
                  child: _buildDraggableContent(context), 
                ),

              // 3. RECEIVER RENDERER
              const SpatialRenderer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        FloatingActionButton.small(heroTag: "f1", onPressed: () => _pickMedia('image'), child: const Icon(Icons.image)),
        const SizedBox(height: 10),
        FloatingActionButton(heroTag: "f2", backgroundColor: const Color(0xFF00E676), onPressed: () => _pickMedia('video'), child: const Icon(Icons.play_arrow)),
    ]);
  }

  Widget _buildDraggableContent(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.6, 
        maxHeight: MediaQuery.of(context).size.height * 0.6, 
        minWidth: 150,
        minHeight: 150
      ),
      decoration: BoxDecoration(
        color: Colors.black, 
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, spreadRadius: 5)],
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: InteractiveViewer(
              child: _fileType == 'video' && _senderVideoController != null && _senderVideoController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _senderVideoController!.value.aspectRatio,
                      child: VideoPlayer(_senderVideoController!)
                    )
                  : Image.file(_selectedFiles.first, fit: BoxFit.contain), 
            ),
          ),
          Positioned(
            top: 5, right: 5,
            child: GestureDetector(
              onTap: _clearSender,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
          Positioned(
            bottom: 10, right: 10,
            child: FloatingActionButton.small(
              backgroundColor: const Color(0xFF00E676),
              onPressed: _manualSend,
              child: const Icon(Icons.send, color: Colors.black),
            ),
          ),
          if (_selectedFiles.length > 1)
            Positioned(left: 10, top: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(10)), child: Text("+${_selectedFiles.length - 1}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))))
        ],
      ),
    );
  }

  Widget _buildBackground() => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)])));
  
  Widget _buildGlassStatusCard(SocketService service) { 
    return GlassBox(
      borderGlow: service.isConferenceMode, 
      child: Column(
        children: [
          Row(
            children: [
              Icon(service.isConferenceMode ? Icons.hub : Icons.share_location, color: Colors.white, size: 30),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("NEURAL CORE", style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.5)),
                  GestureDetector(
                    onTap: () { if (!service.isConnected) _showManualConnectDialog(context, service); },
                    child: Text(service.isConnected ? "ONLINE" : "OFFLINE (Tap)", style: TextStyle(color: service.isConnected ? const Color(0xFF00E676) : Colors.amber, fontWeight: FontWeight.bold))
                  ),
                  if (service.transferStatus != "IDLE") Text(service.transferStatus, style: const TextStyle(color: Colors.cyanAccent, fontSize: 10))
                ],
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.copy_all), onPressed: () async {
                  ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data != null) service.syncClipboard(data.text!);
              })
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassDeviceTile(dynamic device, String? myId) {
     return ListTile(title: Text(device['name'], style: const TextStyle(color: Colors.white)), subtitle: Text(device['id'] == myId ? "You" : "Peer", style: const TextStyle(color: Colors.white38)));
  }
  
  void _showManualConnectDialog(BuildContext context, SocketService service) { 
      TextEditingController ipController = TextEditingController(text: "192.168.");
      showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Manual Connection", style: TextStyle(color: Colors.white)), content: TextField(controller: ipController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Enter PC IP", labelStyle: TextStyle(color: Colors.white54))), actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)), onPressed: () { Navigator.pop(context); if (ipController.text.isNotEmpty) service.connectToSpecificIP(ipController.text.trim()); }, child: const Text("Connect", style: TextStyle(color: Colors.black)))]));
  }
}

class SpatialGestureLayer extends StatefulWidget {
  final Widget child;
  final Function(DragUpdateDetails)? onDragUpdate;
  final Map<String, dynamic> extraData; 
  const SpatialGestureLayer({Key? key, required this.child, this.onDragUpdate, this.extraData = const {}}) : super(key: key);
  @override
  State<SpatialGestureLayer> createState() => _SpatialGestureLayerState();
}

class _SpatialGestureLayerState extends State<SpatialGestureLayer> {
  Offset _startPos = Offset.zero;
  DateTime _startTime = DateTime.now();
  
  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final size = MediaQuery.of(context).size;
    
    return Listener(
      onPointerDown: (event) { _startPos = event.position; _startTime = DateTime.now(); },
      onPointerMove: (event) {
        if (widget.onDragUpdate != null) widget.onDragUpdate!(DragUpdateDetails(globalPosition: event.position, delta: event.delta));
        
        socketService.sendSwipeData({
            'x': event.position.dx / size.width, 
            'y': event.position.dy / size.height, 
            'isDragging': true, 
            'action': 'move',
            ...widget.extraData 
        });
        
        if (Platform.isWindows) {
           if (event.position.dx < 5) {
              var left = socketService.activeDevices.firstWhere((d) => (d['x'] ?? 0) < 0, orElse: () => null);
              if (left != null) socketService.sendMouseTeleport(left['id'], event.delta.dx, event.delta.dy);
           }
           if (event.position.dx > size.width - 5) {
              var right = socketService.activeDevices.firstWhere((d) => (d['x'] ?? 0) > 0, orElse: () => null);
              if (right != null) socketService.sendMouseTeleport(right['id'], event.delta.dx, event.delta.dy);
           }
        }
      },
      onPointerUp: (event) {
        final duration = DateTime.now().difference(_startTime).inMilliseconds;
        if (duration < 50) return; 

        double dx = event.position.dx - _startPos.dx;
        double dy = event.position.dy - _startPos.dy;
        double vx = (dx / duration) * 1000;
        double vy = (dy / duration) * 1000;

        socketService.sendSwipeData({'isDragging': false, 'action': 'release', 'vx': vx, 'vy': vy, ...widget.extraData});

        bool isFast = vx.abs() > 100 || vy.abs() > 100; 
        bool isFar = dx.abs() > (size.width * 0.2); 

        if (isFast || isFar) {
            // FIX: Haptic Feedback + Async Handling
            HapticFeedback.mediumImpact();
            socketService.triggerSwipeTransfer(vx, vy).catchError((e) {
               print("Transfer Trigger Failed: $e");
            });
        }
      },
      child: widget.child,
    );
  }
}
