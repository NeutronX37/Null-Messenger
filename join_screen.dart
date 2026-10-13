import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../hotspot_service.dart';
import '../lan_node.dart';
import '../session.dart';
import 'chat_screen.dart';

class JoinScreen extends StatefulWidget {
  final String deviceName;
  const JoinScreen({super.key, required this.deviceName});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _hotspot = HotspotService();
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    try {
      _join(HotspotInfo.fromQrPayload(raw));
    } catch (_) {
      // Not one of our QR codes: keep scanning.
    }
  }

  Future<void> _manualEntry() async {
    final ssid = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter network manually'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ssid, decoration: const InputDecoration(labelText: 'Network name (SSID)')),
          TextField(controller: pass, decoration: const InputDecoration(labelText: 'Password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok == true && ssid.text.isNotEmpty && pass.text.length >= 8) {
      _join(HotspotInfo(ssid: ssid.text.trim(), password: pass.text));
    }
  }

  Future<void> _join(HotspotInfo info) async {
    if (_busy) return;
    setState(() { _busy = true; _status = 'Joining "${info.ssid}"…\nApprove the Android prompt if it appears.'; });
    MeshSession? session;
    try {
      await _hotspot.acquireMulticastLock();
      final gateway = await _hotspot.join(info);

      if (mounted) setState(() => _status = 'Connecting to host…');
      session = MeshSession(role: Role.client, deviceName: widget.deviceName)
        ..onClose = _hotspot.leave;
      try {
        await session.connectClient(gateway, info.port);
      } catch (_) {
        // Gateway guess failed: listen for the host's UDP beacon instead.
        final found = await Discovery.find(timeout: const Duration(seconds: 8));
        if (found == null) rethrow;
        await session.connectClient(found.ip.address, found.port);
      }

      if (!mounted) { session.dispose(); return; }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(session: session!, ownsSession: true)),
      );
    } catch (e) {
      session?.dispose();
      await _hotspot.leave();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not connect: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a network'), actions: [
        IconButton(
          tooltip: 'Enter manually',
          icon: const Icon(Icons.keyboard),
          onPressed: _busy ? null : _manualEntry,
        ),
      ]),
      body: Stack(children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Camera unavailable (${error.errorCode.name}). Use the keyboard icon to enter the network manually.',
                  textAlign: TextAlign.center),
            ),
          ),
        ),
        if (!_busy)
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Point the camera at the Host\'s QR code'),
                ),
              ),
            ),
          ),
        if (_busy)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ]),
          ),
      ]),
    );
  }
}
