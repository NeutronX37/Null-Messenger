import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../hotspot_service.dart';
import '../session.dart';
import 'chat_screen.dart';

class HostScreen extends StatefulWidget {
  final String deviceName;
  const HostScreen({super.key, required this.deviceName});
  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final _hotspot = HotspotService();
  HotspotInfo? _info;
  MeshSession? _session;
  String? _error;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() { _starting = true; _error = null; });
    try {
      final info = await _hotspot.startHost();
      final session = MeshSession(role: Role.host, deviceName: widget.deviceName);
      await session.startHost(port: info.port);
      session.addListener(_onSession);
      if (!mounted) {
        session.dispose();
        _hotspot.stopHost();
        return;
      }
      setState(() { _info = info; _session = session; _starting = false; });
    } catch (e) {
      await _hotspot.stopHost();
      if (mounted) setState(() { _error = '$e'; _starting = false; });
    }
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _session?.dispose();
    _hotspot.stopHost();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hosting')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _starting
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Starting hotspot…')],
                )
              : _error != null
                  ? _errorView()
                  : _readyView(),
        ),
      ),
    );
  }

  Widget _errorView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _start, child: const Text('Try again')),
        ],
      );

  Widget _readyView() {
    final info = _info!;
    final session = _session!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Ask the other phone to tap "Join a network" and scan this code',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: info.toQrPayload(), size: 240),
          ),
          const SizedBox(height: 16),
          SelectableText('Network: ${info.ssid}'),
          SelectableText('Password: ${info.password}'),
          const SizedBox(height: 16),
          Chip(
            avatar: const Icon(Icons.people_outline, size: 18),
            label: Text('${session.peers} connected'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(session: session, ownsSession: false)),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Open chat'),
          ),
        ],
      ),
    );
  }
}
