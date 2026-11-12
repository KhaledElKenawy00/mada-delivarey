import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// هوية الجهاز اللي الترخيص بيتربط بيها.
/// - Windows: سيريال الـ BIOS + MachineGuid
/// - Android: ANDROID_ID (أندرويد 10+ مابيسمحش بقراءة السيريال الحقيقي للتطبيقات)
class DeviceIdentity {
  final String serial; // اللي بيتعرض للمستخدم
  final String deviceName;
  final String platform; // windows | android
  final String osLabel;
  final String fingerprint; // SHA-256 — ده اللي بيتربط بالترخيص

  const DeviceIdentity({
    required this.serial,
    required this.deviceName,
    required this.platform,
    required this.osLabel,
    required this.fingerprint,
  });

  static Future<DeviceIdentity> read() async {
    final info = DeviceInfoPlugin();
    if (!kIsWeb && Platform.isWindows) {
      final w = await info.windowsInfo;
      final bios = await _windowsBiosSerial();
      final machineId = w.deviceId.replaceAll(RegExp(r'[{}]'), '');
      final serial = bios ?? machineId.split('-').first.toUpperCase();
      return DeviceIdentity(
        serial: serial,
        deviceName: w.computerName,
        platform: 'windows',
        osLabel: w.productName,
        fingerprint: _hash('windows|$bios|$machineId'),
      );
    }
    if (!kIsWeb && Platform.isAndroid) {
      final a = await info.androidInfo;
      final id = await const AndroidId().getId() ?? a.id;
      final brand = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
      return DeviceIdentity(
        serial: id.toUpperCase(),
        deviceName: '$brand${a.model}',
        platform: 'android',
        osLabel: 'Android ${a.version.release}',
        fingerprint: _hash('android|$id|${a.board}|${a.hardware}'),
      );
    }
    // منصات تانية (للتطوير بس)
    final host = kIsWeb ? 'web' : Platform.localHostname;
    return DeviceIdentity(
      serial: host.toUpperCase(),
      deviceName: host,
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      osLabel: kIsWeb ? 'Web' : Platform.operatingSystemVersion,
      fingerprint: _hash('dev|$host'),
    );
  }

  static Future<String?> _windowsBiosSerial() async {
    try {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', '(Get-CimInstance Win32_BIOS).SerialNumber'],
      );
      final v = (r.stdout as String).trim();
      const junk = ['', 'to be filled by o.e.m.', 'default string', 'system serial number', '0', 'none'];
      if (r.exitCode != 0 || junk.contains(v.toLowerCase())) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  static String _hash(String v) => sha256.convert(utf8.encode('madar::$v')).toString();
}
