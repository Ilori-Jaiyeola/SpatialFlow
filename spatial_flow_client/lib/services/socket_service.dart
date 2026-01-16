import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isConferenceMode = false;
  Timer? _heartbeatTimer; // <--- KEEPS CONNECTION ALIVE

  // Data Getters (Keep these from previous version)
  Map<String, dynamic>? _incomingSwipeData;
  dynamic _incomingContent;
  String? _incomingContentType;
  int _currentVideoTimestamp = 0;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  dynamic get incomingContent => _incomingContent;
  String? get incomingContentType => _incomingContentType;
  int get currentVideoTimestamp => _currentVideoTimestamp;

  // --- 1. AGGRESSIVE DISCOVERY ---
  void startDiscovery() async {
    if (_isConnected) return;
    _isScanning = true;
    notifyListeners();

    try {
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888).then((socket) {
        socket.broadcastEnabled = true;
        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = socket.receive();
            if (dg != null) {
              String message = utf8.decode(dg.data);
              if (message.startsWith("SPATIAL_ANNOUNCE")) {
                var parts = message.split("|");
                if (parts.length > 1) {
                  connectToSpecificIP(parts[1]);
                  socket.close();
                }
              }
            }
          }
        });
        
        // Shout louder and more often
        Timer.periodic(const Duration(seconds: 1), (timer) {
           if (_isConnected) {
             timer.cancel();
           } else {
             try {
                List<int> data = utf8.encode("SPATIAL_DISCOVER");
                socket.send(data, InternetAddress("255.255.255.255"), 3000);
             } catch(e) {}
           }
        });
      });
    } catch (e) {
      print("UDP Error: $e");
    }
  }

  // --- 2. UNBREAKABLE CONNECTION ---
  void connectToSpecificIP(String ip) async {
    if (_isConnected) return; // Prevent double connection
    String url = "http://$ip:3000";
    
    // Configure socket to be sticky
    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 9999, // Never give up
      'reconnectionDelay': 500,     // Retry instantly
    });

    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      _startHeartbeat(); // <--- START THE PULSE
      
      // Identify
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceName = "Unknown Node";
      String type = "mobile";
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
      } else if (Platform.isWindows) {
        WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
        deviceName = winInfo.computerName;
        type = "desktop";
      }

      _socket!.emit('register', {'name': deviceName, 'type': type});
      notifyListeners();
    });

    _socket!.on('register_confirm', (data) {
      _myId = data['id'];
      notifyListeners();
    });

    _socket!.on('device_list', (data) {
      _activeDevices = data;
      notifyListeners();
    });

    _socket!.on('disconnect', (_) {
      print('Connection unstable... attempting reconnect');
      _isConnected = false;
      notifyListeners();
      // Do NOT clear _activeDevices immediately. 
      // The user might just be walking between rooms.
    });

    // --- DATA LISTENERS ---
    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            notifyListeners();
        }
    });
    
    // Placeholder for WebRTC Signal
    _socket!.on('p2p_signal', (data) {
        print("Received P2P Signal from ${data['senderId']}");
        // Here we will trigger the WebRTC handshake later
    });
  }

  // --- 3. THE HEARTBEAT (The fix for walking) ---
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('heartbeat'); // "I am still here!"
      }
    });
  }

  // --- 4. SENDING ---
  void broadcastContent(File file, String type) {
    // Phase 1: Send via Server (Reliable)
    // Phase 2: We will upgrade this to 'p2p_signal' for WebRTC
    print("Broadcasting $type...");
  }

  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      data['senderId'] = _myId;
      _socket!.emit('swipe_event', data);
    }
  }
  
  void updateLayout(Map<String, dynamic> config) {
     if (_socket != null) _socket!.emit('update_layout', config);
  }
}
