import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:gal/gal.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart'; 
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  
  Timer? _heartbeatTimer; 
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isReceiving = false; 
  bool _isConferenceMode = false; 
  
  Uint8List? _incomingThumbnail; 
  String? _incomingPlaceholderType; 
  Map<String, dynamic>? _incomingSwipeData; 
  String? _lastReceivedFilePath; 
  String? _incomingContentType;
  String _transferStatus = "IDLE"; 
  String? _incomingSenderId; 

  Offset _virtualMousePos = const Offset(200, 400);
  bool _showVirtualCursor = false;

  List<File> _stagedFiles = []; 
  String _stagedFileType = 'file';

  // GETTERS
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isConferenceMode => _isConferenceMode;
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

  SocketService() { _initBackgroundService(); }

  Future<void> _initBackgroundService() async {
    if (!Platform.isAndroid) return;
    await Permission.notification.request();
    final service = FlutterBackgroundService();
    const AndroidNotificationChannel channel = AndroidNotificationChannel('spatial_flow_service', 'SpatialFlow Core', importance: Importance.low);
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    if (Platform.isIOS || Platform.isAndroid) await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'spatial_flow_service',
        initialNotificationTitle: 'SpatialFlow',
        initialNotificationContent: 'Neural Core Active',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(autoStart: true, onForeground: onBackgroundStart),
    );
    service.startService();
  }

  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async { DartPluginRegistrant.ensureInitialized(); }

  Future<void> _saveToGallery(String filePath, String type) async {
    try {
      if (Platform.isAndroid) { await Permission.storage.request(); await Permission.photos.request(); await Permission.videos.request(); await Permission.manageExternalStorage.request(); }
      if (type == 'video') await Gal.putVideo(filePath); else await Gal.putImage(filePath);
    } catch (e) { log("Export Error: $e"); }
  }

  void log(String message) {
    print("[LOCAL] $message");
    if (_socket != null && _socket!.connected) _socket!.emit('remote_log', {'message': message});
  }

  // --- FIX 1: ACTIVE NEURAL DISCOVERY (SHOUT & LISTEN) ---
  void startDiscovery() async {
    _isScanning = true; notifyListeners();
    log("Initializing Neural Discovery...");

    try {
      // Bind to ANY available port (0) to listen for the reply
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
        socket.broadcastEnabled = true;

        // 1. LISTEN FOR REPLY
        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = socket.receive();
            if (dg != null) {
              String message = utf8.decode(dg.data);
              if (message.startsWith("SPATIAL_ANNOUNCE")) {
                var parts = message.split("|");
                if (parts.length > 1) {
                  String serverIp = parts[1];
                  if (_socket == null || !_socket!.connected || !_socket!.io.uri.contains(serverIp)) {
                      log("Neural Core Found at $serverIp");
                      connectToSpecificIP(serverIp);
                      socket.close(); 
                  }
                }
              }
            }
          }
        });

        // 2. SHOUT TO THE NETWORK (Active Discovery)
        // Send "FIND_NEURAL_CORE" to Port 41234
        String discoveryMsg = "FIND_NEURAL_CORE";
        List<int> data = utf8.encode(discoveryMsg);
        
        try {
           socket.send(data, InternetAddress("255.255.255.255"), 41234);
           log("Shouting: FIND_NEURAL_CORE...");
        } catch(e) {
           log("Broadcast failed, checking backup...");
        }
      });
    } catch (e) { log("UDP Error: $e"); }
  }

  void connectToSpecificIP(String ip) async {
    if (_isConnected) return; 
    _socket = IO.io("http://$ip:3000", <String, dynamic>{ 'transports': ['websocket'], 'autoConnect': true, 'maxHttpBufferSize': 1e8 });
    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async { _isConnected = true; _isScanning = false; _startHeartbeat(); _registerDevice(); });
    _socket!.on('register_confirm', (data) => _myId = data['id']);
    _socket!.on('device_list', (data) { _activeDevices = data; notifyListeners(); });
    _socket!.on('disconnect', (_) { _isConnected = false; notifyListeners(); });
    _socket!.on('debug_broadcast', (data) => print("\x1b[33m[${data['sender']}] ${data['message']}\x1b[0m"));

    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            if (data['action'] == 'release') {
                _incomingSwipeData = null; 
                notifyListeners(); 
                return;
            }
            _incomingSwipeData = data;
            _incomingSwipeData!['isDragging'] = true; 
            notifyListeners();
        }
    });

    _socket!.on('transfer_request', (data) => _executeFileTransfer(data['targetId']));

    _socket!.on('preview_header', (data) {
       log("Hologram Arrived (Size: ${data['thumbnail'].length}).");
       String base64Thumb = data['thumbnail'];
       _incomingThumbnail = base64Decode(base64Thumb);
       _incomingPlaceholderType = data['fileType'];
       _incomingSenderId = data['senderId'];
       _isReceiving = true; 
       _lastReceivedFilePath = null; 
       _incomingSwipeData = null; 
       notifyListeners();
    });

    _socket!.on('content_transfer', (data) async {
       try {
         Uint8List bytes = base64Decode(data['fileData']);
         String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
         String uniqueFileName = "${data['fileName'].split('.').first}_$timestamp.${data['fileName'].split('.').last}";
         final tempDir = await getTemporaryDirectory();
         final tempFile = File('${tempDir.path}/$uniqueFileName');
         await tempFile.writeAsBytes(bytes, flush: true);

         if (Platform.isAndroid || Platform.isIOS) await _saveToGallery(tempFile.path, data['fileType']);
         else {
             final docDir = await getApplicationDocumentsDirectory();
             File('${docDir.path}/SpatialFlow/$uniqueFileName').create(recursive: true).then((f) => f.writeAsBytes(bytes));
         }

         _lastReceivedFilePath = tempFile.path;
         _incomingContentType = data['fileType'];
         _transferStatus = "RECEIVED";
         notifyListeners(); 
       } catch (e) { log("Save Error: $e"); }
    });

    _socket!.on('clipboard_sync', (data) => Clipboard.setData(ClipboardData(text: data['text'])));
    _socket!.on('mouse_teleport', (data) { 
        _showVirtualCursor = true; 
        _virtualMousePos += Offset((data['dx'] as num).toDouble(), (data['dy'] as num).toDouble()); 
        notifyListeners(); 
    });
  }

  Future<void> triggerSwipeTransfer(double vx, double vy) async {
    if (_stagedFiles.isEmpty) return;
    log("Triggering Transfer. Velocity: $vx");
    var target = _findTarget(vx);
    if (target != null) {
        await _executeFileTransfer(target['id']); 
    } else {
        log("No Target Found for Direction");
    }
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

  // --- FIX 2: GREY SCREEN SAFETY NET ---
  Future<void> _executeFileTransfer(String targetId) async {
     _transferStatus = "SENDING...";
     notifyListeners();
     
     // Safety Timer: If transfer takes >10s, force reset UI
     Timer safetyTimer = Timer(const Duration(seconds: 10), () {
        if (_transferStatus == "SENDING...") {
             _transferStatus = "ERROR (Timeout)";
             notifyListeners();
             Future.delayed(const Duration(seconds: 2), () { _transferStatus = "IDLE"; notifyListeners(); });
        }
     });

     try {
       for (var file in _stagedFiles) {
         Uint8List? thumbBytes;
         
         if (_stagedFileType == 'video') {
            try { 
              thumbBytes = await VideoThumbnail.thumbnailData(
                video: file.path, imageFormat: ImageFormat.JPEG, maxWidth: 300, quality: 50
              ); 
            } catch(e) {}
         } 
         else if (_stagedFileType == 'image') {
            try {
              thumbBytes = await FlutterImageCompress.compressWithFile(
                file.path, minWidth: 300, minHeight: 300, quality: 50,
              );
            } catch (e) { log("Image Compress Error: $e"); }
            if (thumbBytes == null) thumbBytes = await file.readAsBytes();
         } 
         else { 
            thumbBytes = await file.readAsBytes(); 
         }

         if (thumbBytes != null) {
            log("Sending Hologram (Size: ${thumbBytes.length} bytes)...");
            _socket!.emit('preview_header', { 
               'targetId': targetId, 
               'senderId': _myId, 
               'thumbnail': base64Encode(thumbBytes), 
               'fileType': _stagedFileType 
            });
         }

         // SEND ACTUAL FILE
         List<int> bytes = await file.readAsBytes();
         _socket!.emit('file_payload', { 
           'targetId': targetId, 
           'senderId': _myId, 
           'fileData': base64Encode(bytes), 
           'fileName': file.path.split('/').last, 
           'fileType': _stagedFileType 
         });
         
         await Future.delayed(const Duration(milliseconds: 300));
       }
       _transferStatus = "SENT";
       notifyListeners();
       
       safetyTimer.cancel(); // Cancel safety timer on success

       Future.delayed(const Duration(seconds: 2), () { _transferStatus = "IDLE"; notifyListeners(); });
     } catch (e) { 
        log("Transfer Error: $e"); 
        _transferStatus = "ERROR"; 
        notifyListeners(); 
        safetyTimer.cancel();
     }
  }

  void _registerDevice() async {
      DeviceInfoPlugin d = DeviceInfoPlugin();
      String name = "Unknown";
      String type = Platform.isWindows ? "desktop" : "mobile";
      if (Platform.isAndroid) name = (await d.androidInfo).model;
      if (Platform.isWindows) name = (await d.windowsInfo).computerName;
      _socket!.emit('register', {'name': name, 'type': type});
  }

  void _startHeartbeat() { _heartbeatTimer?.cancel(); _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (_socket != null && _socket!.connected) _socket!.emit('heartbeat'); }); }
  
  void clearStagedFiles() { _stagedFiles = []; _transferStatus = "IDLE"; notifyListeners(); }
  
  void clearView() { 
      _isReceiving = false; 
      _lastReceivedFilePath = null; 
      _incomingThumbnail = null; 
      _incomingSwipeData = null; 
      notifyListeners(); 
  }
  
  void broadcastContent(List<File> f, String t) { _stagedFiles = f; _stagedFileType = t; _transferStatus = "READY"; notifyListeners(); }
  void sendSwipeData(Map<String, dynamic> d) { d['senderId'] = _myId; _socket!.emit('swipe_event', d); }
  void syncClipboard(String t) { _socket!.emit('clipboard_sync', {'text': t}); }
  void sendMouseTeleport(String t, double x, double y) { _socket!.emit('mouse_teleport', {'targetId': t, 'dx': x, 'dy': y}); }
  void openLastFile() { if (_lastReceivedFilePath != null) OpenFilex.open(_lastReceivedFilePath!); }
  void toggleConferenceMode(bool value) { _isConferenceMode = value; notifyListeners(); } 
}
