import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// What the Host shows as a QR code and the Client scans.
class HotspotInfo {
  final String ssid;
  final String password;
  final int port;
  const HotspotInfo({required this.ssid, required this.password, this.port = 8765});

  String toQrPayload() => jsonEncode({'app': 'offline-mesh', 's': ssid, 'p': password, 'port': port});

  /// Throws FormatException if the QR isn't ours.
  factory HotspotInfo.fromQrPayload(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (m['app'] != 'offline-mesh') throw const FormatException('Not an Offline Mesh QR');
    return HotspotInfo(ssid: m['s'] as String, password: m['p'] as String, port: (m['port'] as int?) ?? 8765);
  }
}

class HotspotException implements Exception {
  final String message;
  HotspotException(this.message);
  @override
  String toString() => message;
}

class HotspotService {
  static const _ch = MethodChannel('offline_mesh/hotspot');

  // ---------------- HOST ----------------
  Future<HotspotInfo> startHost() async {
    await _ensureHostPermissions();
    try {
      final r = Map<String, dynamic>.from(await _ch.invokeMethod('startHotspot') as Map);
      return HotspotInfo(ssid: r['ssid'] as String, password: r['password'] as String);
    } on PlatformException catch (e) {
      throw HotspotException(e.message ?? 'Could not start hotspot');
    }
  }

  Future<void> stopHost() async {
    try {
      await _ch.invokeMethod('stopHotspot');
    } catch (_) {}
  }

  // ---------------- CLIENT ----------------
  /// Joins the AP (Android shows a system approval dialog) and returns the Host IP (the gateway).
  Future<String> join(HotspotInfo info) async {
    try {
      final r = Map<String, dynamic>.from(await _ch
          .invokeMethod('joinNetwork', {'ssid': info.ssid, 'password': info.password}) as Map);
      return r['gateway'] as String;
    } on PlatformException catch (e) {
      throw HotspotException(e.message ?? 'Could not join network');
    }
  }

  Future<void> leave() async {
    try {
      await _ch.invokeMethod('leaveNetwork');
    } catch (_) {}
  }

  Future<void> acquireMulticastLock() async {
    try {
      await _ch.invokeMethod('acquireMulticastLock');
    } catch (_) {}
  }

  // ---------------- helpers ----------------
  Future<void> _ensureHostPermissions() async {
    final sdk = await _ch.invokeMethod<int>('sdkInt') ?? 0;
    final perms = <Permission>[
      Permission.locationWhenInUse,
      if (sdk >= 33) Permission.nearbyWifiDevices,
    ];
    final statuses = await perms.request();
    if (statuses.values.any((s) => !s.isGranted)) {
      throw HotspotException(
          'Permission denied. Location${sdk >= 33 ? ' and Nearby devices are' : ' is'} required to create a hotspot.');
    }
    final locOn = await _ch.invokeMethod<bool>('isLocationEnabled') ?? true;
    if (!locOn) {
      throw HotspotException('Turn on Location (GPS) in quick settings. Android requires it to create a hotspot.');
    }
  }
}
