import 'dart:convert';
import 'dart:io';
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

  // Getters
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;

  // --- 1. START DISCOVERY (The Scanner) ---
  void startDiscovery() async {
    _isScanning = true;
    notifyListeners();

    // --- HARDCODE TEST (Uncomment the next line to bypass scanning if needed) ---
    connectToSpecificIP("192.168.199.203"); return; 

    // Automatic UDP Discovery logic
    try {
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888).then((socket) {
        socket.broadcastEnabled = true;
        
        // Listen for "SPATIAL_ANNOUNCE"
        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = socket.receive();
            if (dg != null) {
              String message = utf8.decode(dg.data);
              if (message.startsWith("SPATIAL_ANNOUNCE")) {
                // Found the server!
                var parts = message.split("|");
                if (parts.length > 1) {
                  String serverIp = parts[1];
                  connectToSpecificIP(serverIp);
                  socket.close(); // Stop listening once found
                }
              }
            }
          }
        });

        // Send a "Who is there?" ping
        List<int> data = utf8.encode("SPATIAL_DISCOVER");
        socket.send(data, InternetAddress("255.255.255.255"), 3000);
        print("Scanning for Spatial Core...");
      });
    } catch (e) {
      print("UDP Error: $e");
    }
  }

  // --- 2. CONNECT LOGIC (The Fix) ---
  void connectToSpecificIP(String ip) async {
    if (_isConnected) return;

    String url = "http://$ip:3000";
    print("Connecting to Core at: $url");

    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      
      // Identify myself
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceName = "Unknown Node";
      String type = "mobile";
      
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
        type = "mobile";
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

    _socket!.onDisconnect((_) {
      print('Disconnected from Core');
      _isConnected = false;
      _activeDevices = [];
      notifyListeners();
      // If disconnected, start scanning again
      startDiscovery();
    });
  }

  // --- 3. SENDING ACTIONS ---
  void broadcastContent(File file, String type) {
    if (_socket == null) return;
    // Implementation for file sending (omitted for brevity, assume exists)
    // For prototype, we just log it
    print("Broadcasting $type...");
  }

  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      _socket!.emit('swipe_event', data);
    }
  }

  void toggleConferenceMode(bool value) {
    _isConferenceMode = value;
    notifyListeners();
  }
}
