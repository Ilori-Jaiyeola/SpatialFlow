import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async'; // For Timer

class SocketService with ChangeNotifier {
  late IO.Socket _socket;

  // --- Connection State ---
  bool _isConnected = false;
  bool _isScanning = true; // Starts in scanning mode
  String _serverIp = "Searching...";
  String? _myId;

  // --- Logic State ---
  bool _isConferenceMode = false; // New: Toggle for broadcast mode

  // --- Data State ---
  List<dynamic> _activeDevices = [];
  Map<String, dynamic>? _incomingSwipeData;
  
  // --- Content/Media State ---
  String? _incomingContentType; // 'image' or 'video'
  dynamic _incomingContent;     // File object (video) or Base64 String (image)
  Duration _currentVideoTimestamp = Duration.zero; 

  // --- Getters ---
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  String get serverIp => _serverIp;
  String? get myId => _myId;
  bool get isConferenceMode => _isConferenceMode;
  
  List<dynamic> get activeDevices => _activeDevices;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  dynamic get incomingContent => _incomingContent;
  String? get incomingContentType => _incomingContentType;
  Duration get currentVideoTimestamp => _currentVideoTimestamp;

  // ------------------------------------------------------------------------
  // 1. INITIALIZATION & DISCOVERY
  // ------------------------------------------------------------------------

  void startDiscovery() {
    // TEMPORARY: Force connect to your PC's IP (Replace with YOUR numbers from ipconfig)
    connectToSocket("http://192.168.199.203:3000"); 
    return; // <--- Stop the rest of the scanning logic
  }

  /// Listens for UDP Beacon from the Node.js Server on Port 4444
  void _scanForServer() async {
    print("📡 Scanning for Neural Core on UDP 4444...");
    
    try {
      // Bind to the discovery port to listen for the beacon
      var socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4444);
      
      socket.listen((RawSocketEvent e) {
        if (e == RawSocketEvent.read) {
          Datagram? d = socket.receive();
          if (d != null) {
            String message = String.fromCharCodes(d.data);
            try {
              // Parse the beacon JSON
              var data = jsonDecode(message);
              if (data['service'] == 'spatial_flow_core') {
                String ip = data['ip'];
                String port = data['port'].toString();
                String foundUrl = "http://$ip:$port";

                // If we found a new server, connect to it
                if (_serverIp != foundUrl) {
                  print("✅ Found Core at: $foundUrl");
                  _serverIp = foundUrl;
                  _isScanning = false;
                  notifyListeners();
                  
                  socket.close(); // Stop listening once found
                  _connectToSocket(foundUrl);
                }
              }
            } catch (e) {
              // Ignore non-JSON packets
            }
          }
        }
      });
    } catch (e) {
      print("⚠️ UDP Error: $e");
      // Fallback: If UDP fails (e.g., Emulator restrictions), try localhost
      // Use 'http://10.0.2.2:3000' for Android Emulator to Host PC
      _connectToSocket('http://192.168.1.189:3000'); 
    }
  }

  // ------------------------------------------------------------------------
  // 2. WEBSOCKET CONNECTION
  // ------------------------------------------------------------------------

  void _connectToSocket(String url) {
    _socket = IO.io(url, IO.OptionBuilder()
        .setTransports(['websocket']) // Force WebSocket (faster than polling)
        .enableAutoConnect()
        .build());

    // --- CONNECTION EVENTS ---
    
    _socket.onConnect((_) async {
      print('✅ Connected to Neural Core');
      _isConnected = true;
      _myId = _socket.id;
      notifyListeners();
      await _registerDevice();
    });

    _socket.onDisconnect((_) {
      print('❌ Disconnected');
      _isConnected = false;
      _isScanning = true; // Go back to scanning mode
      notifyListeners();
      _scanForServer(); // Restart discovery loop
    });

    // --- LOGIC EVENTS ---

    // 1. Device List Update
    _socket.on('device_list_update', (data) {
      _activeDevices = data;
      notifyListeners();
    });

    // 2. Mode Update (Conference vs Spatial)
    _socket.on('mode_update', (data) {
      // Server tells us the mode changed
      _isConferenceMode = data['conference'];
      notifyListeners();
    });

    // 3. Render Ghost/Coordinates
    _socket.on('render_split', (data) {
      _incomingSwipeData = data;
      // If timestamp is present (Video Sync), update it
      if (data['timestamp'] != null) {
        _currentVideoTimestamp = Duration(milliseconds: data['timestamp']);
      }
      notifyListeners();
    });

    // 4. Receive Actual File Content
    _socket.on('receive_content', (data) async {
      print("📦 Receiving ${data['type']}...");
      _incomingContentType = data['type'];

      if (_incomingContentType == 'image') {
        // Images are sent as Base64 strings
        _incomingContent = data['fileData'];
      } 
      else if (_incomingContentType == 'video') {
        // Videos are sent as Base64, but must be written to a temp file to play
        final bytes = base64Decode(data['fileData']);
        final tempDir = await getTemporaryDirectory();
        // Create a temp file (e.g., temp_stream_123.mp4)
        final file = await File('${tempDir.path}/temp_stream_${DateTime.now().millisecondsSinceEpoch}.mp4').create();
        await file.writeAsBytes(bytes);
        
        _incomingContent = file; // Save the File object
      }
      notifyListeners();
    });
  }

  // ------------------------------------------------------------------------
  // 3. ACTIONS (METHODS CALLED BY UI)
  // ------------------------------------------------------------------------

  /// Identifies the device type (Mobile/Desktop) and sends it to Server
  Future<void> _registerDevice() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String deviceName = "Unknown Device";
    String type = "desktop";

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceName = "${androidInfo.brand} ${androidInfo.model}";
      type = "mobile";
    } else if (Platform.isIOS) {
       IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
       deviceName = iosInfo.name;
       type = "mobile";
    } else if (Platform.isMacOS) {
      deviceName = "MacBook";
    } else if (Platform.isWindows) {
      deviceName = "Windows PC";
    }

    _socket.emit('register', {
      'name': deviceName, 
      'type': type
    });
  }

  /// Sends swipe coordinates + velocity + active edge to Server
  void sendSwipeData(Map<String, dynamic> data) {
    if (!_isConnected) return;
    _socket.emit('swipe_update', data);
  }

  /// Saves the physical layout (Calibration) to Server
  void updateLayout(List<Map<String, dynamic>> layoutData) {
    _socket.emit('update_layout', layoutData);
  }

  /// Toggles between Spatial Mode (Neighbors) and Conference Mode (Broadcast)
  void toggleConferenceMode(bool isEnabled) {
    if (!_isConnected) return;
    _socket.emit('toggle_conference_mode', isEnabled);
    
    // Optimistic update (UI updates instantly)
    _isConferenceMode = isEnabled; 
    notifyListeners();
  }

  /// Encodes file to Base64 and sends it to the mesh
  void broadcastContent(File file, String type) async {
    if (!_isConnected) return;

    List<int> bytes = await file.readAsBytes();
    String base64Data = base64Encode(bytes);

    _socket.emit('broadcast_content', {
      'type': type,
      'fileData': base64Data
    });
  }

}
