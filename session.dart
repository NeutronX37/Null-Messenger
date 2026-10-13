import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'lan_node.dart';

enum Role { host, client }

class ChatItem {
  final String from;
  final String? text;
  final String? fileName;
  final int? size;
  final bool mine;
  final DateTime time = DateTime.now();
  String? localPath;
  double? progress; // null = idle, 0 = starting/indeterminate, 0..1 = in progress
  String? error;

  ChatItem({
    required this.from,
    this.text,
    this.fileName,
    this.size,
    required this.mine,
    this.localPath,
    this.progress,
  });

  bool get isFile => fileName != null;
}

String _randomId() {
  final r = Random.secure();
  return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
}

class MeshSession extends ChangeNotifier {
  final Role role;
  final String deviceName;
  final String id = _randomId();
  final List<ChatItem> items = [];
  int peers = 0;
  bool connected = false;
  late String saveDir;

  /// Extra cleanup supplied by the owner (e.g. leave the Wi-Fi network).
  Future<void> Function()? onClose;

  HostNode? _host;
  ClientNode? _client;
  bool _disposed = false;

  MeshSession({required this.role, required this.deviceName});

  Future<void> _initDir() async {
    final base = (await getExternalStorageDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(base, 'received'));
    await dir.create(recursive: true);
    saveDir = dir.path;
  }

  // ---------------- lifecycle ----------------
  Future<void> startHost({int port = 8765}) async {
    await _initDir();
    _host = HostNode(
      saveDir: saveDir,
      onEvent: _onEvent,
      onPeers: (n) { peers = n; _notify(); },
    );
    await _host!.start(port: port);
    try {
      await Discovery.startBeacon(deviceName, port);
    } catch (_) {/* discovery is best-effort */}
    connected = true;
    _notify();
  }

  Future<void> connectClient(String ip, int port) async {
    await _initDir();
    final c = ClientNode(id: id, name: deviceName);
    await c.connect(ip, port: port, onEvent: _onEvent, onClosed: () {
      connected = false;
      _notify();
    });
    _client = c;
    connected = true;
    peers = 1;
    _notify();
  }

  // ---------------- sending ----------------
  void sendText(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final event = {'type': 'text', 'id': id, 'from': deviceName, 'text': t};
    if (_host != null) {
      _host!.broadcast(event);
    } else {
      _client?.send(event);
    }
    _add(ChatItem(from: deviceName, text: t, mine: true));
  }

  Future<void> sendFile(File f) async {
    final name = p.basename(f.path);
    final item = ChatItem(
      from: deviceName,
      fileName: name,
      size: await f.length(),
      mine: true,
      localPath: f.path,
      progress: 0,
    );
    _add(item);
    try {
      if (_host != null) {
        await _host!.shareFile(f, id, deviceName);
      } else {
        await _client!.sendFile(f, (pr) => _setProgress(item, pr));
      }
    } catch (e) {
      item.error = 'Send failed: $e';
    }
    item.progress = null;
    _notify();
  }

  Future<void> download(ChatItem item) async {
    if (_client == null || item.progress != null || item.fileName == null) return;
    item.progress = 0;
    item.error = null;
    _notify();
    try {
      final f = await _client!.download(item.fileName!, saveDir, (pr) => _setProgress(item, pr));
      item.localPath = f.path;
    } catch (e) {
      item.error = 'Download failed';
    }
    item.progress = null;
    _notify();
  }

  // ---------------- receiving ----------------
  void _onEvent(Map<String, dynamic> e) {
    if (e['id'] == id) return; // our own echo
    switch (e['type']) {
      case 'text':
        _add(ChatItem(from: '${e['from']}', text: '${e['text']}', mine: false));
        break;
      case 'file':
        final name = '${e['name']}';
        _add(ChatItem(
          from: '${e['from']}',
          fileName: name,
          size: (e['size'] as num?)?.toInt(),
          mine: false,
          // On the host, received files are already on disk.
          localPath: role == Role.host ? p.join(saveDir, name) : null,
        ));
        break;
    }
  }

  // ---------------- helpers ----------------
  void _add(ChatItem item) {
    items.add(item);
    _notify();
  }

  void _setProgress(ChatItem item, double value) {
    // Only repaint when the whole-percent value changes.
    final before = ((item.progress ?? 0) * 100).floor();
    final after = (value * 100).floor();
    item.progress = value;
    if (after != before) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _host?.stop();
    Discovery.stopBeacon();
    _client?.close();
    onClose?.call();
    super.dispose();
  }
}
