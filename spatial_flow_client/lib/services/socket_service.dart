import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // Needed for file bytes
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart'; // Ensure this is in pubspec.yaml

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isConferenceMode = false;
  Timer? _heartbeatTimer; 

  // --- STAGING AREA (For the file you want to send) ---
  File? _stagedFile; 
  String? _stagedFileType;

  // --- INCOMING DATA (From other devices) ---
  Map<String, dynamic>? _incomingSwipeData;
  dynamic _incomingContent; // Will be a File path string
  String? _incomingContentType;
  int _currentVideoTimestamp = 0;

  // --- GETTERS ---
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  dynamic get incomingContent => _incomingContent;
  String? get incomingContentType => _incomingContentType;
  int get currentVideoTimestamp => _currentVideoTimestamp;

  // =========================================================
  // 1. DISCOVERY LOGIC (UDP)
  // =========================================================
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
        
        // Broadcast "I'm here" every second
        Timer.periodic(const Duration(seconds: 1), (timer) {
           if (_isConnected) {
             timer.cancel();
           } else {
             try {
                List<int> data = utf8.encode("SPATIAL_DISCOVER");
                socket.send(data, InternetAddress("255.255.255.255"), 3000);
             } catch(e) {
               // Ignore permission errors on some networks
             }
           }
        });
      });
    } catch (e) {
      print("UDP Error: $e");
    }
  }

  // =========================================================
  // 2. CONNECTION LOGIC (WebSockets)
  // =========================================================
  void connectToSpecificIP(String ip) async {
    if (_isConnected) return; 
    String url = "http://$ip:3000";
    
    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 9999,
      'reconnectionDelay': 500,
    });

    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      _startHeartbeat(); // <--- STARTS THE PULSE
      
      // Identify Device
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
    });

    // --- DATA LISTENERS ---

    // 1. Swipe Coordinates (Ghost Hand)
    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            notifyListeners();
        }
    });

    // 2. Transfer Request (Server asking for the file)
    _socket!.on('transfer_request', (data) async {
       String targetId = data['targetId'];
       print("Server authorized transfer to $targetId");
       
       if (_stagedFile != null) {
         try {
           // Read bytes and convert to Base64
           List<int> bytes = await _stagedFile!.readAsBytes();
           String base64Data = base64Encode(bytes);
           
           // Send the payload
           _socket!.emit('file_payload', {
             'targetId': targetId,
             'fileData': base64Data,
             'fileName': _stagedFile!.path.split('/').last,
             'fileType': _stagedFileType
           });
           print("File payload sent!");
         } catch (e) {
           print("Error reading file: $e");
         }
       }
    });

    // 3. Receive Content (File arriving from another device)
    _socket!.on('content_transfer', (data) async {
       print("Receiving file...");
       String base64Data = data['fileData'];
       String fileName = data['fileName'];
       String type = data['fileType'];

       try {
         // Decode and Save to Temp
         Uint8List bytes = base64Decode(base64Data);
         final directory = await getTemporaryDirectory();
         final newFile = File('${directory.path}/$fileName');
         await newFile.writeAsBytes(bytes);

         // Update UI to show the new file
         _incomingContent = newFile.path;
         _incomingContentType = type;
         notifyListeners();
       } catch (e) {
         print("Error saving file: $e");
       }
    });

    _socket!.on('p2p_signal', (data) {
        print("Received P2P Signal from ${data['senderId']}");
    });
  }

  // =========================================================
  // 3. ACTIONS & HELPER METHODS
  // =========================================================

  // Stage a file to be sent on the next swipe
  void broadcastContent(File file, String type) {
    _stagedFile = file;
    _stagedFileType = type;
    print("File staged: ${file.path}. Swipe to send.");
  }

  // Send swipe coordinates
  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      data['senderId'] = _myId;
      _socket!.emit('swipe_event', data);
    }
  }

  // Fixes: "The method 'toggleConferenceMode' isn't defined"
  void toggleConferenceMode(bool value) {
    _isConferenceMode = value;
    notifyListeners();
  }

  // Fixes: "The method 'updateLayout' isn't defined"
  void updateLayout(Map<String, dynamic> config) {
     if (_socket != null) _socket!.emit('update_layout', config);
  }

  // Fixes: "where the void _startHeartbeat should start from"
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('heartbeat'); 
      }
    });
  }
}
