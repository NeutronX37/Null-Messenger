import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Returns a path inside [dir] that doesn't exist yet (name, name_1.ext, name_2.ext ...).
String uniquePath(String dir, String name) {
  var path = p.join(dir, name);
  if (!File(path).existsSync()) return path;
  final base = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var i = 1;
  while (File(path).existsSync()) {
    path = p.join(dir, '${base}_$i$ext');
    i++;
  }
  return path;
}

// ===================================================================
// HOST: WebSocket hub at /ws + streaming file transfer at /file/<name>
// ===================================================================
class HostNode {
  HttpServer? _server;
  final _clients = <WebSocket>{};
  final String saveDir;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(int peers)? onPeers;

  HostNode({required this.saveDir, required this.onEvent, this.onPeers});

  Future<void> start({int port = 8765}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      await _route(req);
    } catch (_) {
      // Aborted upload / dropped client: never let it kill the server.
      try { await req.response.close(); } catch (_) {}
    }
  }

  Future<void> _route(HttpRequest req) async {
    final segs = req.uri.pathSegments;

    if (segs.length == 1 && segs[0] == 'ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.pingInterval = const Duration(seconds: 10);
      _clients.add(ws);
      onPeers?.call(_clients.length);
      ws.listen(
        (data) {
          final event = jsonDecode(data as String) as Map<String, dynamic>;
          onEvent(event);
          for (final c in _clients) {
            if (c != ws) c.add(data); // relay to everyone else
          }
        },
        onDone: () { _clients.remove(ws); onPeers?.call(_clients.length); },
        onError: (_) { _clients.remove(ws); onPeers?.call(_clients.length); },
      );
      return;
    }

    if (segs.length == 2 && segs[0] == 'file') {
      final base = p.basename(segs[1]); // strips any ../ tricks

      if (req.method == 'PUT') {
        final target = uniquePath(saveDir, base);
        final file = File(target);
        await req.pipe(file.openWrite()); // streams to disk, constant memory
        final event = {
          'type': 'file',
          'id': req.uri.queryParameters['id'] ?? '',
          'from': req.uri.queryParameters['from'] ?? 'peer',
          'name': p.basename(target),
          'size': await file.length(),
        };
        req.response.statusCode = HttpStatus.ok;
        await req.response.close(); // client's request.close() waits for this
        onEvent(event);
        broadcast(event);
        return;
      }

      if (req.method == 'GET') {
        final file = File(p.join(saveDir, base));
        if (await file.exists()) {
          req.response.contentLength = await file.length();
          await file.openRead().pipe(req.response); // closes the response
          return;
        }
      }
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void broadcast(Map<String, dynamic> event) {
    final data = jsonEncode(event);
    for (final c in _clients) {
      c.add(data);
    }
  }

  /// Host sharing its own file: copy into saveDir, announce to everyone.
  Future<String> shareFile(File src, String id, String from) async {
    final target = uniquePath(saveDir, p.basename(src.path));
    final copied = await src.copy(target);
    broadcast({
      'type': 'file',
      'id': id,
      'from': from,
      'name': p.basename(target),
      'size': await copied.length(),
    });
    return target;
  }

  Future<void> stop() async {
    for (final c in _clients.toList()) {
      await c.close();
    }
    _clients.clear();
    await _server?.close(force: true);
  }
}

// ===================================================================
// CLIENT
// ===================================================================
class ClientNode {
  final String id;
  final String name;
  WebSocket? _ws;
  late String _host;
  late int _port;

  ClientNode({required this.id, required this.name});

  Future<void> connect(
    String hostIp, {
    int port = 8765,
    required void Function(Map<String, dynamic> event) onEvent,
    void Function()? onClosed,
  }) async {
    _host = hostIp;
    _port = port;
    _ws = await WebSocket.connect('ws://$hostIp:$port/ws').timeout(const Duration(seconds: 8));
    _ws!.pingInterval = const Duration(seconds: 10); // detect dead links
    _ws!.listen(
      (d) => onEvent(jsonDecode(d as String) as Map<String, dynamic>),
      onDone: onClosed,
      onError: (_) => onClosed?.call(),
    );
  }

  void send(Map<String, dynamic> event) => _ws?.add(jsonEncode(event));

  Uri _fileUri(String fileName, [Map<String, String>? query]) => Uri(
        scheme: 'http',
        host: _host,
        port: _port,
        pathSegments: ['file', fileName],
        queryParameters: query,
      );

  Future<void> sendFile(File file, void Function(double) onProgress) async {
    final total = await file.length();
    var sent = 0;
    final http = HttpClient();
    try {
      final req = await http.putUrl(_fileUri(p.basename(file.path), {'id': id, 'from': name}));
      req.contentLength = total;
      await req.addStream(file.openRead().map((chunk) {
        sent += chunk.length;
        if (total > 0) onProgress(sent / total);
        return chunk;
      }));
      final res = await req.close();
      await res.drain();
      if (res.statusCode != HttpStatus.ok) throw HttpException('Host replied ${res.statusCode}');
    } finally {
      http.close();
    }
  }

  Future<File> download(String fileName, String saveDir, void Function(double) onProgress) async {
    final http = HttpClient();
    try {
      final req = await http.getUrl(_fileUri(fileName));
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) throw HttpException('Host replied ${res.statusCode}');
      final out = File(uniquePath(saveDir, fileName));
      var got = 0;
      await res.map((chunk) {
        got += chunk.length;
        if (res.contentLength > 0) onProgress(got / res.contentLength);
        return chunk;
      }).pipe(out.openWrite());
      return out;
    } finally {
      http.close();
    }
  }

  Future<void> close() async => _ws?.close();
}

// ===================================================================
// DISCOVERY: UDP broadcast beacon (fallback if connecting to the gateway fails)
// ===================================================================
class Discovery {
  static const beaconPort = 45454;
  static Timer? _timer;
  static RawDatagramSocket? _tx;

  static Future<void> startBeacon(String deviceName, int wsPort) async {
    stopBeacon();
    _tx = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _tx!.broadcast = true;
    final payload = utf8.encode(jsonEncode({'app': 'offline-mesh', 'name': deviceName, 'port': wsPort}));
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        _tx?.send(payload, InternetAddress('255.255.255.255'), beaconPort);
      } catch (_) {}
    });
  }

  static void stopBeacon() {
    _timer?.cancel();
    _timer = null;
    _tx?.close();
    _tx = null;
  }

  static Future<({InternetAddress ip, int port})?> find(
      {Duration timeout = const Duration(seconds: 10)}) async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort, reuseAddress: true);
    final done = Completer<({InternetAddress ip, int port})?>();
    final sub = sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      try {
        final m = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (m['app'] == 'offline-mesh' && !done.isCompleted) {
          done.complete((ip: dg.address, port: m['port'] as int));
        }
      } catch (_) {}
    });
    final result = await done.future.timeout(timeout, onTimeout: () => null);
    await sub.cancel();
    sock.close();
    return result;
  }
}
