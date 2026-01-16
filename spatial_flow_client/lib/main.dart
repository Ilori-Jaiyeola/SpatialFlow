import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:ui'; // Needed for ImageFilter
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
  File? _selectedFile;
  String? _fileType;
  VideoPlayerController? _senderVideoController;
  Offset _dragPosition = const Offset(100, 400);

  @override
  void initState() {
    super.initState();
    // Start auto-discovery immediately
    Provider.of<SocketService>(context, listen: false).startDiscovery();
  }

  @override
  void dispose() {
    _senderVideoController?.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(String type) async {
    final picker = ImagePicker();
    XFile? pickedFile;
    if (type == 'video') {
      pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      pickedFile = await picker.pickImage(source: ImageSource.gallery);
    }

    if (pickedFile != null) {
      setState(() {
        _selectedFile = File(pickedFile!.path);
        _fileType = type;
      });
      if (type == 'video') {
        _senderVideoController?.dispose();
        _senderVideoController = VideoPlayerController.file(_selectedFile!)
          ..initialize().then((_) {
            setState(() {});
            _senderVideoController!.play();
            _senderVideoController!.setLooping(true);
            _senderVideoController!.setVolume(0);
          });
      }
      // Stage the file in the service so it's ready to send on swipe
      Provider.of<SocketService>(context, listen: false).broadcastContent(_selectedFile!, type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);

    return SpatialGestureLayer(
      extraData: _fileType == 'video' && _senderVideoController != null 
          ? {'timestamp': _senderVideoController!.value.position.inMilliseconds}
          : {},
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
            // --- LAYER 0: BACKGROUND ---
            _buildBackground(),

            // --- LAYER 1: GLASS UI DASHBOARD ---
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

            // --- LAYER 2: SENDER CONTENT ---
            if (_selectedFile != null)
              Positioned(
                left: _dragPosition.dx,
                top: _dragPosition.dy,
                child: _buildDraggableContent(),
              ),

            // --- LAYER 3: RECEIVER GHOST ---
            const SpatialRenderer(),
          ],
        ),
      ),
    );
  }

  // --- VISUAL COMPONENTS ---

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -50, left: -50, child: _buildOrb(Colors.purpleAccent)),
          Positioned(bottom: 100, right: -50, child: _buildOrb(Colors.blueAccent)),
        ],
      ),
    );
  }

  Widget _buildOrb(Color color) {
    return Container(
      width: 200, height: 200,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.4)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.transparent),
      ),
    );
  }

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
                  const SizedBox(height: 5),
                  // --- CLICKABLE STATUS FOR MANUAL CONNECT ---
                  GestureDetector(
                    onTap: () {
                      if (!service.isConnected) {
                        _showManualConnectDialog(context, service);
                      }
                    },
                    child: Text(
                      service.isConnected 
                          ? "ONLINE" 
                          : (service.isScanning ? "SCANNING... (Tap to Edit)" : "OFFLINE"), 
                      style: TextStyle(
                        color: service.isConnected ? const Color(0xFF00E676) : Colors.amber, 
                        fontWeight: FontWeight.bold, 
                        fontSize: 16,
                        decoration: service.isConnected ? null : TextDecoration.underline,
                      )
                    ),
                  ),
                ],
              )
            ],
          ),
          const Divider(color: Colors.white24, height: 25),
          SwitchListTile(
            title: const Text("Conference Mode", style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text("Broadcast to all nodes", style: TextStyle(color: Colors.white38, fontSize: 11)),
            value: service.isConferenceMode,
            activeColor: Colors.purpleAccent,
            onChanged: (val) => service.toggleConferenceMode(val),
          )
        ],
      ),
    );
  }

  Widget _buildGlassDeviceTile(dynamic device, String? myId) {
    bool isMe = device['id'] == myId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassBox(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        opacity: isMe ? 0.2 : 0.05,
        child: Row(
          children: [
            Icon(device['type'] == 'mobile' ? Icons.smartphone : Icons.laptop, color: Colors.white70),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(isMe ? "Host Node" : "Peer Node", style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
            const Spacer(),
            if (!isMe) const Icon(Icons.wifi_tethering, color: Color(0xFF00E676), size: 18)
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableContent() {
    return Container(
      width: 250, height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, spreadRadius: 5)],
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _fileType == 'video' && _senderVideoController != null && _senderVideoController!.value.isInitialized
            ? VideoPlayer(_senderVideoController!)
            : (_selectedFile != null ? Image.file(_selectedFile!, fit: BoxFit.cover) : Container(color: Colors.grey)),
      ),
    );
  }

  Widget _buildFab() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: "f1", backgroundColor: Colors.white12, foregroundColor: Colors.white,
          onPressed: () => _pickMedia('image'), child: const Icon(Icons.image),
        ),
        const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: "f2", backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black,
          onPressed: () => _pickMedia('video'), child: const Icon(Icons.play_arrow),
        ),
      ],
    );
  }

  // --- MANUAL CONNECT DIALOG ---
  void _showManualConnectDialog(BuildContext context, SocketService service) {
    TextEditingController ipController = TextEditingController(text: "192.168.");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Manual Connection", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ipController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Enter PC IP Address",
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: const Color(0xFF00E676))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () {
              Navigator.pop(context);
              if (ipController.text.isNotEmpty) {
                 // Force the connection to the IP you typed
                 service.connectToSpecificIP(ipController.text.trim());
              }
            },
            child: const Text("Connect", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }
}

// --- SMART GESTURE LAYER (With Velocity) ---
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
  Offset _lastPos = Offset.zero;
  DateTime _startTime = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final size = MediaQuery.of(context).size;

    return Listener(
      onPointerDown: (event) {
        _startPos = event.position;
        _lastPos = event.position;
        _startTime = DateTime.now();
      },
      onPointerMove: (event) {
        if (widget.onDragUpdate != null) {
          widget.onDragUpdate!(DragUpdateDetails(globalPosition: event.position, delta: event.delta));
        }
        
        // Broadcast dragging for visual effect
        socketService.sendSwipeData({
            'x': event.position.dx / size.width, 
            'y': event.position.dy / size.height,
            'isDragging': true,
            'action': 'move'
        });
        _lastPos = event.position;
      },
      onPointerUp: (event) {
        // CALCULATE VELOCITY (The "Throw")
        final endTime = DateTime.now();
        final duration = endTime.difference(_startTime).inMilliseconds;
        
        if (duration < 50) return; 

        final dx = event.position.dx - _startPos.dx;
        final dy = event.position.dy - _startPos.dy;
        
        // Pixels per second
        double vx = (dx / duration) * 1000;
        double vy = (dy / duration) * 1000;

        socketService.sendSwipeData({
            'isDragging': false, 
            'action': 'release',
            'vx': vx, 
            'vy': vy,
            ...widget.extraData
        });
      },
      child: widget.child,
    );
  }
}
