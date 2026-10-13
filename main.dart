import 'dart:math';
import 'package:flutter/material.dart';
import 'screens/host_screen.dart';
import 'screens/join_screen.dart';

void main() => runApp(const MeshApp());

class MeshApp extends StatelessWidget {
  const MeshApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Offline Mesh',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController(text: 'Phone-${1000 + Random().nextInt(9000)}');

  String get _deviceName => _name.text.trim().isEmpty ? 'Phone' : _name.text.trim();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.wifi_tethering, size: 72, color: cs.primary),
              const SizedBox(height: 12),
              Text('Offline Mesh',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('Chat and share files with no internet',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 36),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => HostScreen(deviceName: _deviceName))),
                icon: const Icon(Icons.wifi_tethering),
                label: const Padding(padding: EdgeInsets.all(14), child: Text('Host a network')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => JoinScreen(deviceName: _deviceName))),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Padding(padding: EdgeInsets.all(14), child: Text('Join a network')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
