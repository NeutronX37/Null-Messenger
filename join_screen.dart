import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
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
  MobileScannerController? _scanner;
  bool? _camOk; // null = still asking
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _askCamera();
  }

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  /// Ask for camera permission ourselves BEFORE starting the scanner.
  Future<void> _askCamera() async {
    var st = await Permission.camera.status;
    if (!st.isGranted) st = await Permission.camera.request();
    if (!mounted) return;
    if (st.isGranted) {
      _scanner ??= MobileScannerController(formats: [BarcodeFormat.qrCode]);
    }
    setState(() => _camOk = st.isGranted);
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

      if (mounted) setState(() => _status = 'Connecting to host ($gateway)…');
      session = MeshSession(role: Role.client, deviceName: widget.deviceName)
        ..onClose = _hotspot.leave;
      try {
        await session.connectClient(gateway, info.port);
      } catch (e) {
        // Gateway guess failed: listen for the host's UDP beacon instead.
        final found = await Discovery.find(timeout: const Duration(seconds: 8));
        if (found == null) {
          throw 'Joined Wi-Fi OK (host IP $gateway) but could not open a connection: $e';
        }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not connect: $e'), duration: const Duration(seconds: 12)),
      );
    }
  }

  Widget _noCamera() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Camera permission is needed to scan the QR code.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _askCamera, child: const Text('Allow camera')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: openAppSettings, child: const Text('Open app settings')),
            const SizedBox(height: 8),
            TextButton(onPressed: _manualEntry, child: const Text('Enter network manually')),
          ]),
        ),
      );

  Widget _scannerView() => Stack(children: [
        MobileScanner(controller: _scanner!, onDetect: _onDetect),
        ValueListenableBuilder<MobileScannerState>(
          valueListenable: _scanner!,
          builder: (context, state, _) {
            final err = state.error;
            if (err == null) return const SizedBox.shrink();
            return Container(
              color: Theme.of(context).colorScheme.surface,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  'Camera error: ${err.errorCode.name}\n${err.errorDetails?.message ?? ''}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => _scanner?.start(), child: const Text('Retry')),
                TextButton(onPressed: _manualEntry, child: const Text('Enter network manually')),
              ]),
            );
          },
        ),
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
      ]);

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
        if (_camOk == null)
          const Center(child: CircularProgressIndicator())
        else if (_camOk == false)
          _noCamera()
        else
          _scannerView(),
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
