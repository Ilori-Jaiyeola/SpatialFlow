import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:gal/gal.dart'; 

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  
  // STATE
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isConferenceMode = false;
  Timer? _heartbeatTimer; 

  // MULTI-FILE
  List<File> _stagedFiles = []; 
  String _stagedFileType = 'file';

  // INCOMING
  Map<String, dynamic>? _incomingSwipeData;
  String? _lastReceivedFilePath; 
  String? _incomingContentType;
  String _transferStatus = "IDLE"; 
  String? _incomingSenderId; 

  // UNIFIED CANVAS (Mouse)
  Offset _virtualMousePos = const Offset(200, 400);
  bool _showVirtualCursor = false;

  // GETTERS
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isConferenceMode => _isConferenceMode;
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;
  String? get lastReceivedFilePath => _lastReceivedFilePath; 
  String? get incomingContentType => _incomingContentType;
  String? get incomingSenderId => _incomingSenderId;
  String get transferStatus => _transferStatus;
  Offset get virtualMousePos => _virtualMousePos;
  bool get showVirtualCursor => _showVirtualCursor;

  // --- 1. DISCOVERY ---
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
      });
    } catch (e) { print("UDP: $e"); }
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
      'maxHttpBufferSize': 1e8 
    });

    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      _startHeartbeat(); 
      
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceName = "Unknown Node";
      String type = Platform.isAndroid || Platform.isIOS ? "mobile" : "desktop";
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
      } else if (Platform.isWindows) {
        WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
        deviceName = winInfo.computerName;
      }

      _socket!.emit('register', {'name': deviceName, 'type': type});
      notifyListeners();
    });

    _socket!.on('register_confirm', (data) => _myId = data['id']);
    _socket!.on('device_list', (data) { _activeDevices = data; notifyListeners(); });
    _socket!.on('disconnect', (_) { _isConnected = false; notifyListeners(); });

    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            notifyListeners();
        }
    });

    // --- SENDING ---
    _socket!.on('transfer_request', (data) async {
       String targetId = data['targetId'];
       if (_stagedFiles.isNotEmpty) {
         _transferStatus = "SENDING ${_stagedFiles.length} FILES...";
         notifyListeners();

         try {
           for (var file in _stagedFiles) {
             List<int> bytes = await file.readAsBytes();
             String base64Data = base64Encode(bytes);
             
             _socket!.emit('file_payload', {
               'targetId': targetId,
               'senderId': _myId, 
               'fileData': base64Data,
               'fileName': file.path.split('/').last,
               'fileType': _stagedFileType
             });
             await Future.delayed(const Duration(milliseconds: 200)); 
           }
           _transferStatus = "SENT";
           notifyListeners();
           Future.delayed(const Duration(seconds: 2), () {
             _transferStatus = "IDLE";
             notifyListeners();
           });
         } catch (e) {
           _transferStatus = "ERROR";
           notifyListeners();
         }
       }
    });

    // --- RECEIVING ---
    _socket!.on('content_transfer', (data) async {
       _transferStatus = "RECEIVING...";
       notifyListeners();

       try {
         String base64Data = data['fileData'];
         String fileName = data['fileName'];
         String type = data['fileType'];
         String senderId = data['senderId'] ?? "";
         
         Uint8List bytes = base64Decode(base64Data);
         
         final tempDir = await getTemporaryDirectory();
         final tempFile = File('${tempDir.path}/$fileName');
         await tempFile.writeAsBytes(bytes);

         // Save to Gallery/Downloads
         if (Platform.isAndroid || Platform.isIOS) {
             try {
                await Gal.putImage(tempFile.path); 
                if (type == 'video') await Gal.putVideo(tempFile.path);
             } catch (e) { print("Gallery Error: $e"); }
         } else {
             final downloadsDir = await getApplicationDocumentsDirectory(); 
             final saveDir = Directory('${downloadsDir.path}/SpatialFlow');
             if (!await saveDir.exists()) await saveDir.create(recursive: true);
             final permFile = File('${saveDir.path}/$fileName');
             await permFile.writeAsBytes(bytes);
         }

         // Update UI
         _lastReceivedFilePath = tempFile.path;
         _incomingContentType = type;
         _incomingSenderId = senderId; 
         _transferStatus = "RECEIVED";
         notifyListeners();

       } catch (e) {
         print("Save Error: $e");
         _transferStatus = "SAVE FAILED";
         notifyListeners();
       }
    });

    _socket!.on('clipboard_sync', (data) {
       Clipboard.setData(ClipboardData(text: data['text']));
    });

    _socket!.on('mouse_teleport', (data) {
       double dx = (data['dx'] as num).toDouble();
       double dy = (data['dy'] as num).toDouble();
       _showVirtualCursor = true;
       _virtualMousePos += Offset(dx, dy);
       notifyListeners();
    });
  }

  // --- ACTIONS ---
  
  // NEW: CLEAR VIEW FOR CLOSE BUTTON
  void clearView() {
    _lastReceivedFilePath = null;
    _incomingContentType = null;
    notifyListeners();
  }

  void broadcastContent(List<File> files, String type) {
    _stagedFiles = files;
    _stagedFileType = type;
    _transferStatus = "READY (${files.length})";
    notifyListeners();
  }

  void sendSwipeData(Map<String, dynamic> data) {
    if (_socket != null) {
      data['senderId'] = _myId;
      _socket!.emit('swipe_event', data);
    }
  }

  void syncClipboard(String text) {
    if (_socket != null) _socket!.emit('clipboard_sync', {'text': text});
  }

  void sendMouseTeleport(String targetId, double dx, double dy) {
    if (_socket != null) {
      _socket!.emit('mouse_teleport', {'targetId': targetId, 'dx': dx, 'dy': dy});
    }
  }

  void toggleConferenceMode(bool value) {
    _isConferenceMode = value;
    notifyListeners();
  }

  void openLastFile() {
    if (_lastReceivedFilePath != null) {
      OpenFilex.open(_lastReceivedFilePath!);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_socket != null && _socket!.connected) _socket!.emit('heartbeat'); 
    });
  }
}
