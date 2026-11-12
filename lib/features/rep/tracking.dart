import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/providers.dart';
import '../../data/repository.dart';

enum TrackingState { off, on, denied, gpsOff }

/// التتبع الإجباري أثناء يوم العمل.
/// على أندرويد بيشتغل كـ Foreground Service (إشعار ثابت) علشان يكمّل لو المندوب قفل التطبيق.
class TrackingController extends Notifier<TrackingState> {
  StreamSubscription<Position>? _sub;
  DateTime? _lastSent;

  @override
  TrackingState build() {
    ref.onDispose(() => _sub?.cancel());
    return TrackingState.off;
  }

  MadarRepository get _repo => ref.read(repositoryProvider);

  Future<TrackingState> start() async {
    if (_sub != null) return state;
    if (!await Geolocator.isLocationServiceEnabled()) return state = TrackingState.gpsOff;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return state = TrackingState.denied;
    }

    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20,
            intervalDuration: const Duration(seconds: 30),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'مدار — يوم العمل شغال',
              notificationText: 'موقعك بيتسجل لحد ما تنهي اليوم',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(_send, onError: (_) {});
    // أول نقطة فوراً
    try {
      await _send(await Geolocator.getCurrentPosition());
    } catch (_) {}
    return state = TrackingState.on;
  }

  Future<void> _send(Position p) async {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < const Duration(seconds: 20)) return;
    _lastSent = now;
    try {
      await _repo.pushLocation(p.latitude, p.longitude, p.accuracy, p.speed);
    } catch (_) {
      // النقطة بتضيع لو مفيش نت — الجاية هتتبعت عادي
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    state = TrackingState.off;
  }
}

final trackingProvider = NotifierProvider<TrackingController, TrackingState>(TrackingController.new);
