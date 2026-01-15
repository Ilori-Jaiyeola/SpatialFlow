import 'dart:convert';
import 'dart:io';
import 'dart:async'; // Added for Stream/Timer if needed
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

  // --- RESTORED MISSING VARIABLES ---
  Map<String, dynamic>? _incomingSwipeData;
  dynamic _incomingContent; // File path or data
  String? _incomingContentType; // 'image' or 'video'
  int _currentVideoTimestamp = 0;

  // --- GETTERS (This fixes the "getter not defined" errors) ---
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  dynamic get incomingContent => _incomingContent;
  String? get incomingContentType => _incomingContentType;
  int get currentVideoTimestamp => _currentVideoTimestamp;

  // --- 1. START DISCOVERY ---
  void startDiscovery() async {
    _isScanning = true;
    notifyListeners();

    // HARDCODE FALLBACK (Uncomment if needed)
  connectToSpecificIP("192.168.199.203"); return;

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

        // Broadcast ping
        List<int> data = utf8.encode("SPATIAL_DISCOVER");
        try {
            socket.send(data, InternetAddress("255.255.255.255"), 3000);
        } catch (e) {
            // Handle network permission errors gracefully
            print("Broadcast failed (expected on some networks): $e");
        }
      });
    } catch (e) {
      print("UDP Error: $e");
    }
  }

  // --- 2. CONNECT LOGIC ---
  void connectToSpecificIP(String ip) async {
    if (_isConnected) return;
    String url = "http://$ip:3000";
    print("Connecting to: $url");

    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      
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

    // --- 3. RESTORED DATA LISTENERS ---
    
    // Listen for incoming swipes (Ghost hand)
    _socket!.on('swipe_event', (data) {
        // Only update if it's from another device
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            notifyListeners();
        }
    });

    // Listen for file transfers
    _socket!.on('content_transfer', (data) {
        _incomingContent = data['content']; // Base64 or path
        _incomingContentType = data['type'];
        notifyListeners();
    });

    // Listen for video sync
    _socket!.on('video_sync', (data) {
        _currentVideoTimestamp = data['timestamp'];
        notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _activeDevices = [];
      notifyListeners();
      startDiscovery();
    });
  }

  // --- 4. SENDING ACTIONS ---
  
  void broadcastContent(File file, String type) {
    if (_socket == null) return;
    // For prototype, we simulate sending a signal. 
    // In production, convert file to Base64 or upload to server.
    _socket!.emit('content_transfer', {
        'type': type,
        'content': 'dummy_path_for_demo', 
        // 'data': base64Encode(file.readAsBytesSync()) // If implementing real transfer
    });
  }

  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      // Add my ID so I don't receive my own echo
      data['senderId'] = _myId;
      _socket!.emit('swipe_event', data);
    }
  }

  void toggleConferenceMode(bool value) {
    _isConferenceMode = value;
    notifyListeners();
  }

  // --- 5. CALIBRATION METHOD (Fixes the Calibration Screen error) ---
  void updateLayout(Map<String, dynamic> layoutConfig) {
      if (_socket != null) {
          _socket!.emit('update_layout', layoutConfig);
      }
  }
}
