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
import 'package:video_thumbnail/video_thumbnail.dart'; 

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  
  // --- CONNECTION ---
  bool _isConnected = false;
  bool _isScanning = false;
  Timer? _heartbeatTimer; 

  // --- UI STATE ---
  bool _isReceiving = false; 
  bool _isConferenceMode = false; // <--- RESTORED
  Uint8List? _incomingThumbnail; 
  String? _incomingPlaceholderType; 

  // --- FILE DATA ---
  Map<String, dynamic>? _incomingSwipeData;
  String? _lastReceivedFilePath; 
  String? _incomingContentType;
  String _transferStatus = "IDLE"; 
  String? _incomingSenderId; 

  // --- MOUSE ---
  Offset _virtualMousePos = const Offset(200, 400);
  bool _showVirtualCursor = false;

  // --- STAGING ---
  List<File> _stagedFiles = []; 
  String _stagedFileType = 'file';

  // --- GETTERS ---
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isConferenceMode => _isConferenceMode; // <--- RESTORED
  List<dynamic> get activeDevices => _activeDevices;
  String? get myId => _myId;
  bool get isReceiving => _isReceiving;
  Uint8List? get incomingThumbnail => _incomingThumbnail; 
  String? get incomingPlaceholderType => _incomingPlaceholderType;
  String? get lastReceivedFilePath => _lastReceivedFilePath; 
  String? get incomingContentType => _incomingContentType;
  String get transferStatus => _transferStatus;
  Offset get virtualMousePos => _virtualMousePos;
  bool get showVirtualCursor => _showVirtualCursor;
  Map<String, dynamic>? get incomingSwipeData => _incomingSwipeData;

  // --- NETWORK LOGIC ---
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
    } catch (e) { print("UDP Error: $e"); }
  }

  void connectToSpecificIP(String ip) async {
    if (_isConnected) return; 
    _socket = IO.io("http://$ip:3000", <String, dynamic>{
      'transports': ['websocket'], 'autoConnect': true, 'maxHttpBufferSize': 1e8 
    });
    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async {
      print('Connected to Neural Core');
      _isConnected = true;
      _isScanning = false;
      _startHeartbeat(); 
      _registerDevice();
    });

    _socket!.on('register_confirm', (data) => _myId = data['id']);
    _socket!.on('device_list', (data) { _activeDevices = data; notifyListeners(); });
    _socket!.on('disconnect', (_) { _isConnected = false; notifyListeners(); });

    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            if (data['action'] == 'release') {
                _isReceiving = true;
                _transferStatus = "INCOMING...";
                notifyListeners();
            } else {
               notifyListeners();
            }
        }
    });

    _socket!.on('transfer_request', (data) => _executeFileTransfer(data['targetId']));

    // 1. RECEIVE HOLOGRAM
    _socket!.on('preview_header', (data) {
       String base64Thumb = data['thumbnail'];
       _incomingThumbnail = base64Decode(base64Thumb);
       _incomingPlaceholderType = data['fileType'];
       _incomingSenderId = data['senderId'];
       _isReceiving = true; 
       _lastReceivedFilePath = null; 
       notifyListeners();
    });

    // 2. RECEIVE FILE
    _socket!.on('content_transfer', (data) async {
       try {
         String base64Data = data['fileData'];
         String originalName = data['fileName'];
         String type = data['fileType'];
         
         Uint8List bytes = base64Decode(base64Data);
         String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
         String uniqueFileName = "${originalName.split('.').first}_$timestamp.${originalName.split('.').last}";
         
         final tempDir = await getTemporaryDirectory();
         final tempFile = File('${tempDir.path}/$uniqueFileName');
         await tempFile.writeAsBytes(bytes, flush: true);

         if (Platform.isAndroid || Platform.isIOS) {
             Gal.putImage(tempFile.path).then((_) { if(type=='video') Gal.putVideo(tempFile.path); });
         } else {
             final docDir = await getApplicationDocumentsDirectory();
             File('${docDir.path}/SpatialFlow/$uniqueFileName').create(recursive: true).then((f) => f.writeAsBytes(bytes));
         }

         _lastReceivedFilePath = tempFile.path;
         _incomingContentType = type;
         _transferStatus = "RECEIVED";
         notifyListeners(); 

       } catch (e) {
         print("Save Error: $e");
         _transferStatus = "FAILED";
         notifyListeners();
       }
    });

    _socket!.on('clipboard_sync', (data) => Clipboard.setData(ClipboardData(text: data['text'])));
    _socket!.on('mouse_teleport', (data) {
       _showVirtualCursor = true;
       _virtualMousePos += Offset((data['dx'] as num).toDouble(), (data['dy'] as num).toDouble());
       notifyListeners();
    });
  }

  // --- ACTIONS ---
  void triggerSwipeTransfer(double vx, double vy) {
    if (_stagedFiles.isEmpty) return;
    var target = _findTarget(vx);
    if (target != null) _executeFileTransfer(target['id']); 
  }
  
  dynamic _findTarget(double vx) {
     var me = _activeDevices.firstWhere((d) => d['id'] == _myId, orElse: () => null);
     if (me == null) return null;
     int myX = me['x'] ?? 0;
     return _activeDevices.firstWhere((d) {
        if (d['id'] == _myId) return false;
        int tX = d['x'] ?? 0;
        return (vx > 0 && tX > myX) || (vx < 0 && tX < myX);
     }, orElse: () => null);
  }

  Future<void> _executeFileTransfer(String targetId) async {
     _transferStatus = "SENDING...";
     notifyListeners();
     try {
       for (var file in _stagedFiles) {
         
         // GENERATE HOLOGRAM
         Uint8List? thumbBytes;
         if (_stagedFileType == 'video') {
            try {
              thumbBytes = await VideoThumbnail.thumbnailData(
                video: file.path, imageFormat: ImageFormat.JPEG, maxWidth: 300, quality: 50,
              );
            } catch(e) { print("Thumbnail Error: $e"); }
         } else {
            thumbBytes = await file.readAsBytes(); 
         }

         if (thumbBytes != null) {
            _socket!.emit('preview_header', {
               'targetId': targetId, 'senderId': _myId,
               'thumbnail': base64Encode(thumbBytes),
               'fileType': _stagedFileType
            });
         }

         // SEND FILE
         List<int> bytes = await file.readAsBytes();
         _socket!.emit('file_payload', {
           'targetId': targetId, 'senderId': _myId, 'fileData': base64Encode(bytes),
           'fileName': file.path.split('/').last, 'fileType': _stagedFileType
         });
         
         await Future.delayed(const Duration(milliseconds: 300));
       }
       _transferStatus = "SENT";
       notifyListeners();
       Future.delayed(const Duration(seconds: 2), () { _transferStatus = "IDLE"; notifyListeners(); });
     } catch (e) {
       _transferStatus = "ERROR";
       notifyListeners();
     }
  }

  void _registerDevice() async {
      DeviceInfoPlugin d = DeviceInfoPlugin();
      String name = "Unknown";
      String type = Platform.isWindows ? "desktop" : "mobile";
      if (Platform.isAndroid) name = (await d.androidInfo).model;
      if (Platform.isWindows) name = (await d.windowsInfo).computerName;
      if (name.contains(RegExp(r'[^\x00-\x7F]'))) name = type == "mobile" ? "Android" : "PC";
      _socket!.emit('register', {'name': name, 'type': type});
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_socket != null && _socket!.connected) _socket!.emit('heartbeat'); 
    });
  }

  void clearStagedFiles() { _stagedFiles = []; _transferStatus = "IDLE"; notifyListeners(); }
  void clearView() { _isReceiving = false; _lastReceivedFilePath = null; _incomingThumbnail = null; notifyListeners(); }
  void broadcastContent(List<File> f, String t) { _stagedFiles = f; _stagedFileType = t; _transferStatus = "READY"; notifyListeners(); }
  void sendSwipeData(Map<String, dynamic> d) { d['senderId'] = _myId; _socket!.emit('swipe_event', d); }
  void syncClipboard(String t) { _socket!.emit('clipboard_sync', {'text': t}); }
  void sendMouseTeleport(String t, double x, double y) { _socket!.emit('mouse_teleport', {'targetId': t, 'dx': x, 'dy': y}); }
  void openLastFile() { if (_lastReceivedFilePath != null) OpenFilex.open(_lastReceivedFilePath!); }
  
  // RESTORED METHOD
  void toggleConferenceMode(bool value) { 
    _isConferenceMode = value; 
    notifyListeners(); 
  }
}
