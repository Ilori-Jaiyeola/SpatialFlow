import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Android Notification Channel Setup
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'spatial_flow_service', // id
    'SpatialFlow Core', // title
    description: 'Maintains neural connection in background', // description
    importance: Importance.low, // low = silent notification
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // This is the entry point (must be a static function)
      onStart: onStart,

      // Auto start the service? Yes.
      autoStart: true,
      isForegroundMode: true,
      
      notificationChannelId: 'spatial_flow_service',
      initialNotificationTitle: 'SpatialFlow Active',
      initialNotificationContent: 'Neural Core is monitoring gestures...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// Required for iOS (even if empty)
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// The Background Logic Entry Point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure Dart is ready
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Keep the service alive with a timer tick
  // This prevents the OS from killing the associated process
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "SpatialFlow Active",
          content: "Neural Core Online",
        );
      }
    }
    
    // In a production app, you might move the Socket logic here.
    // For this prototype, just running this timer keeps the MAIN app alive.
    print('❤️ Background Heartbeat');
  });
}