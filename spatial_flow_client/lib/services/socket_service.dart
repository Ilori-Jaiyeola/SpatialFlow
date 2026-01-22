import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui'; // Required for Isolate communication
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:gal/gal.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class SocketService with ChangeNotifier {
  IO.Socket? _socket;
  String? _myId;
  List<dynamic> _activeDevices = [];
  
  // STATE
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isReceiving = false; 
  bool _isConferenceMode = false;
  
  // DATA
  Uint8List? _incomingThumbnail; 
  String? _incomingPlaceholderType; 
  Map<String, dynamic>? _incomingSwipeData;
  String? _lastReceivedFilePath; 
  String? _incomingContentType;
  String _transferStatus = "IDLE"; 
  String? _incomingSenderId; 

  // MOUSE
  Offset _virtualMousePos = const Offset(200, 400);
  bool _showVirtualCursor = false;

  // STAGING
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

  // =========================================================
  // 1. INITIALIZATION & BACKGROUND SERVICE
  // =========================================================
  
  SocketService() {
    _initBackgroundService();
  }

  Future<void> _initBackgroundService() async {
    if (!Platform.isAndroid) return; // Background service mainly for Android

    await Permission.notification.request();
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'spatial_flow_service', 
      'SpatialFlow Core',
      description: 'Keeps connection alive for transfers',
      importance: Importance.low, 
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (Platform.isIOS || Platform.isAndroid) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundStart, // Standard entry point
        autoStart: true,
        isForegroundMode: true, // CRITICAL: Keeps app alive in foreground
        notificationChannelId: 'spatial_flow_service',
        initialNotificationTitle: 'SpatialFlow',
        initialNotificationContent: 'Neural Core Active',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onBackgroundStart,
      ),
    );

    service.startService();
    log("Background Service Initialized");
  }

  // Used by FlutterBackgroundService to keep the isolate alive
  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    // This function keeps the Dart Isolate alive.
    // We don't need complex logic here because isForegroundMode: true
    // keeps our main SocketService alive in the main isolate.
  }

  // =========================================================
  // 2. EXPORT SERVICE (Saving Files)
  // =========================================================

  Future<void> _saveToGallery(String filePath, String type) async {
    try {
      log("Exporting to Gallery: $filePath");
      // Request permissions first
      if (Platform.isAndroid) {
         await Permission.storage.request();
         await Permission.photos.request();
         await Permission.videos.request();
         await Permission.manageExternalStorage.request();
      }

      if (type == 'video') {
        await Gal.putVideo(filePath);
      } else {
        await Gal.putImage(filePath);
      }
      log("Export Successful");
    } catch (e) {
      log("Export Error (Gal): $e");
      // Fallback: The file is already in App Doc/Temp dir, so it's safe.
    }
  }

  // =========================================================
  // 3. LOGGING (Telemetry)
  // =========================================================
  void log(String message) {
    print("[LOCAL] $message");
    if (_socket != null && _socket!.connected) {
      _socket!.emit('remote_log', {'message': message});
    }
  }

  // =========================================================
  // 4. NETWORK LOGIC (Discovery & Socket)
  // =========================================================

  void startDiscovery() async {
    _isScanning = true;
    notifyListeners();
    log("Starting UDP Beacon Discovery...");

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
                  String serverIp = parts[1];
                  if (_socket == null || !_socket!.connected || !_socket!.io.uri.contains(serverIp)) {
                     log("Beacon Found! Connecting to $serverIp");
                     connectToSpecificIP(serverIp);
                     socket.close(); 
                  }
                }
              }
            }
          }
        });
      });
    } catch (e) { log("UDP Error: $e"); }
  }

  void connectToSpecificIP(String ip) async {
    if (_isConnected) return; 
    log("Connecting to $ip...");
    
    _socket = IO.io("http://$ip:3000", <String, dynamic>{
      'transports': ['websocket'], 'autoConnect': true, 'maxHttpBufferSize': 1e8 
    });
    if (!_socket!.connected) _socket!.connect();

    _socket!.onConnect((_) async {
      log("Connected to Neural Core");
      _isConnected = true;
      _isScanning = false;
      _startHeartbeat(); 
      _registerDevice();
    });

    _socket!.on('register_confirm', (data) => _myId = data['id']);
    _socket!.on('device_list', (data) { _activeDevices = data; notifyListeners(); });
    
    _socket!.on('disconnect', (_) { 
       log("Disconnected from Core");
       _isConnected = false; 
       notifyListeners(); 
    });

    _socket!.on('debug_broadcast', (data) {
       print("\x1b[33m[${data['sender']}] ${data['message']}\x1b[0m");
    });

    _socket!.on('swipe_event', (data) {
        if (data['senderId'] != _myId) {
            _incomingSwipeData = data;
            if (data['action'] == 'release') {
                log("Swipe Release Detected. Velocity: ${data['vx']}");
                _isReceiving = true;
                _transferStatus = "INCOMING...";
                _incomingSwipeData!['isDragging'] = false; 
                notifyListeners();
            } else {
               notifyListeners();
            }
        }
    });

    _socket!.on('transfer_request', (data) => _executeFileTransfer(data['targetId']));

    // --- RECEIVE HOLOGRAM ---
    _socket!.on('preview_header', (data) {
       log("Received Hologram Header.");
       String base64Thumb = data['thumbnail'];
       _incomingThumbnail = base64Decode(base64Thumb);
       _incomingPlaceholderType = data['fileType'];
       _incomingSenderId = data['senderId'];
       _isReceiving = true; 
       _lastReceivedFilePath = null; 
       notifyListeners();
    });

    // --- RECEIVE FILE (Includes Export Service) ---
    _socket!.on('content_transfer', (data) async {
       try {
         log("Received Full Payload. Saving...");
         String base64Data = data['fileData'];
         String originalName = data['fileName'];
         String type = data['fileType'];
         
         Uint8List bytes = base64Decode(base64Data);
         String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
         String uniqueFileName = "${originalName.split('.').first}_$timestamp.${originalName.split('.').last}";
         
         // 1. Save to Temp/Docs
         final tempDir = await getTemporaryDirectory();
         final tempFile = File('${tempDir.path}/$uniqueFileName');
         await tempFile.writeAsBytes(bytes, flush: true);

         // 2. EXPORT SERVICE (Save to Gallery)
         if (Platform.isAndroid || Platform.isIOS) {
             await _saveToGallery(tempFile.path, type);
         } else {
             final docDir = await getApplicationDocumentsDirectory();
             File('${docDir.path}/SpatialFlow/$uniqueFileName').create(recursive: true).then((f) => f.writeAsBytes(bytes));
         }

         log("File Saved & Exported: $uniqueFileName");
         _lastReceivedFilePath = tempFile.path;
         _incomingContentType = type;
         _transferStatus = "RECEIVED";
         notifyListeners(); 

       } catch (e) {
         log("Save Error: $e");
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

  // =========================================================
  // 5. ACTIONS
  // =========================================================

  void triggerSwipeTransfer(double vx, double vy) {
    if (_stagedFiles.isEmpty) return;
    log("Triggering Transfer. Velocity: $vx");
    var target = _findTarget(vx);
    if (target != null) {
       log("Target Found: ${target['name']}");
       _executeFileTransfer(target['id']); 
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

  Future<void> _executeFileTransfer(String targetId) async {
     _transferStatus = "SENDING...";
     notifyListeners();
     try {
       for (var file in _stagedFiles) {
         // Generate Hologram
         log("Generating Hologram...");
         Uint8List? thumbBytes;
         if (_stagedFileType == 'video') {
            try {
              thumbBytes = await VideoThumbnail.thumbnailData(
                video: file.path, imageFormat: ImageFormat.JPEG, maxWidth: 300, quality: 50,
              );
            } catch(e) { log("Thumbnail Error: $e"); }
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

         // Send File
         log("Sending Payload...");
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
       log("Transfer Error: $e");
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
  void toggleConferenceMode(bool value) { _isConferenceMode = value; notifyListeners(); }
}
