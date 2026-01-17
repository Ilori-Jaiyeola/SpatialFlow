import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for Clipboard
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

  // --- FILE TRANSFER STATE ---
  File? _stagedFile; 
  String? _stagedFileType;
  Map<String, dynamic>? _incomingSwipeData;
  dynamic _incomingContent;
  String? _incomingContentType;
  String _transferStatus = "IDLE"; 

  // --- UNIFIED CANVAS STATE (New) ---
  Offset _virtualMousePos = const Offset(200, 400);
  bool _showVirtualCursor = false;

  // --- GETTERS ---
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  dynamic get incomingContent => _incomingContent;
  String? get incomingContentType => _incomingContentType;
  String get transferStatus => _transferStatus;
  
  Offset get virtualMousePos => _virtualMousePos;
  bool get showVirtualCursor => _showVirtualCursor;

  // =========================================================
  // 1. DISCOVERY & CONNECTION
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
      'maxHttpBufferSize': 1e8 // 100MB Limit
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

    // =========================================================
    // 2. FILE & GESTURE LISTENERS
    // =========================================================
    
    // Swipe Coordinates
    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            notifyListeners();
        }
    });

    // Sending File Logic
    _socket!.on('transfer_request', (data) async {
       String targetId = data['targetId'];
       _transferStatus = "SENDING..."; 
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
           _transferStatus = "SENT";
           notifyListeners();
           Future.delayed(const Duration(seconds: 2), () {
             _transferStatus = "IDLE";
             notifyListeners();
           });
         } catch (e) {
           _transferStatus = "ERROR SENDING";
           notifyListeners();
         }
       }
    });

    // Receiving File Logic
    _socket!.on('content_transfer', (data) async {
       _transferStatus = "RECEIVING...";
       notifyListeners();

       try {
         String base64Data = data['fileData'];
         String fileName = data['fileName'];
         String type = data['fileType'];
         
         Uint8List bytes = base64Decode(base64Data);
         final directory = await getTemporaryDirectory();
         final newFile = File('${directory.path}/$fileName');
         await newFile.writeAsBytes(bytes);

         _incomingContent = newFile.path;
         _incomingContentType = type;
         _transferStatus = "RECEIVED";
         notifyListeners();

       } catch (e) {
         _transferStatus = "SAVE FAILED";
         notifyListeners();
       }
    });

    // =========================================================
    // 3. UNIFIED CANVAS LISTENERS (New)
    // =========================================================

    // Clipboard Listener
    _socket!.on('clipboard_sync', (data) {
       String text = data['text'];
       print("Clipboard Received: $text");
       Clipboard.setData(ClipboardData(text: text));
       // We notify listeners so the UI can show a snackbar/toast if needed
       notifyListeners();
    });

    // Mouse Teleport Listener
    _socket!.on('mouse_teleport', (data) {
       // Only update if we are receiving (Phone side usually)
       double dx = (data['dx'] as num).toDouble();
       double dy = (data['dy'] as num).toDouble();
       
       _showVirtualCursor = true;
       _virtualMousePos += Offset(dx, dy);
       notifyListeners();
       
       // Auto-hide cursor after 5 seconds of inactivity
       Timer(const Duration(seconds: 5), () { 
          // Check if position hasn't changed recently (omitted for simplicity)
          // _showVirtualCursor = false; 
          // notifyListeners();
       });
    });
  }

  // =========================================================
  // 4. ACTIONS & METHODS
  // =========================================================

  void broadcastContent(File file, String type) {
    _stagedFile = file;
    _stagedFileType = type;
    _transferStatus = "READY";
    notifyListeners();
  }

  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      data['senderId'] = _myId;
      _socket!.emit('swipe_event', data);
    }
  }

  // New: Sync Clipboard
  void syncClipboard(String text) {
    if (_socket != null) {
      _socket!.emit('clipboard_sync', {'text': text});
    }
  }

  // New: Send Mouse Delta
  void sendMouseTeleport(String targetId, double dx, double dy) {
    if (_socket != null) {
      _socket!.emit('mouse_teleport', {
        'targetId': targetId,
        'dx': dx,
        'dy': dy
      });
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
