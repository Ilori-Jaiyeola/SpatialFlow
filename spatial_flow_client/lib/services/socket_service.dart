import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isConferenceMode = false;
  Timer? _heartbeatTimer; 

  File? _stagedFile; 
  String? _stagedFileType;

  Map<String, dynamic>? _incomingSwipeData;
  dynamic _incomingContent;
  String? _incomingContentType;
  String _transferStatus = "IDLE"; // <--- NEW STATUS TRACKER

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  dynamic get incomingContent => _incomingContent;
  String? get incomingContentType => _incomingContentType;
  String get transferStatus => _transferStatus; // Getter for UI

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
        Timer.periodic(const Duration(seconds: 1), (timer) {
           if (_isConnected) timer.cancel();
           else {
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

  void connectToSpecificIP(String ip) async {
    if (_isConnected) return; 
    String url = "http://$ip:3000";
    
    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 9999,
      'reconnectionDelay': 500,
      'maxHttpBufferSize': 1e8 // Match server buffer size (100MB)
    });

    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      _startHeartbeat(); 
      
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
      _isConnected = false;
      notifyListeners();
    });

    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            notifyListeners();
        }
    });

    _socket!.on('transfer_request', (data) async {
       String targetId = data['targetId'];
       print("Sending file to $targetId...");
       _transferStatus = "SENDING..."; // Update UI
       notifyListeners();
       
       if (_stagedFile != null) {
         try {
           List<int> bytes = await _stagedFile!.readAsBytes();
           String base64Data = base64Encode(bytes);
           
           _socket!.emit('file_payload', {
             'targetId': targetId,
             'fileData': base64Data,
             'fileName': _stagedFile!.path.split('/').last,
             'fileType': _stagedFileType
           });
           print("Payload sent!");
           _transferStatus = "SENT";
           notifyListeners();
           
           // Reset status after 2 seconds
           Future.delayed(const Duration(seconds: 2), () {
             _transferStatus = "IDLE";
             notifyListeners();
           });

         } catch (e) {
           print("Error sending: $e");
           _transferStatus = "ERROR SENDING";
           notifyListeners();
         }
       }
    });

    // --- UPDATED RECEIVING LOGIC (WITH ERROR HANDLING) ---
    _socket!.on('content_transfer', (data) async {
       print(">>> INCOMING DATA RECEIVED <<<");
       _transferStatus = "RECEIVING...";
       notifyListeners();

       try {
         String base64Data = data['fileData'];
         String fileName = data['fileName'];
         String type = data['fileType'];

         print("Decoding ${base64Data.length} bytes...");
         
         // 1. Decode
         Uint8List bytes = base64Decode(base64Data);
         
         // 2. Get Path
         final directory = await getTemporaryDirectory();
         final newFile = File('${directory.path}/$fileName');
         
         // 3. Write File
         print("Saving to: ${newFile.path}");
         await newFile.writeAsBytes(bytes);

         // 4. Update UI
         _incomingContent = newFile.path;
         _incomingContentType = type;
         _transferStatus = "RECEIVED";
         notifyListeners();
         print("File Saved Successfully!");

       } catch (e) {
         print("!!! ERROR SAVING FILE: $e");
         _transferStatus = "SAVE FAILED";
         notifyListeners();
       }
    });
  }

  void broadcastContent(File file, String type) {
    _stagedFile = file;
    _stagedFileType = type;
    _transferStatus = "READY TO SEND";
    notifyListeners();
    print("File staged. Swipe to send.");
  }

  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      data['senderId'] = _myId;
      _socket!.emit('swipe_event', data);
    }
  }

  void toggleConferenceMode(bool value) {
    _isConferenceMode = value;
    notifyListeners();
  }

  void updateLayout(Map<String, dynamic> config) {
     if (_socket != null) _socket!.emit('update_layout', config);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('heartbeat'); 
      }
    });
  }
}
