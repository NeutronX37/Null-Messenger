import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../session.dart';

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
}

class ChatScreen extends StatefulWidget {
  final MeshSession session;

  /// True for clients (leaving the chat ends the session). The host's session lives on the host screen.
  final bool ownsSession;
  const ChatScreen({super.key, required this.session, required this.ownsSession});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  MeshSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onChange);
  }

  @override
  void dispose() {
    s.removeListener(_onChange);
    if (widget.ownsSession) s.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    s.sendText(_input.text);
    _input.clear();
  }

  Future<void> _attach() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    for (final f in res.files) {
      if (f.path != null) s.sendFile(File(f.path!)); // runs concurrently, progress shown per file
    }
  }

  Future<void> _open(String path) async {
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved at $path')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = s.role == Role.host
        ? 'Hosting · ${s.peers} connected'
        : (s.connected ? 'Connected' : 'Disconnected');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(children: [
        if (!s.connected && s.role == Role.client)
          MaterialBanner(
            content: const Text('Lost connection to the host. Go back and join again.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Leave'))],
          ),
        Expanded(
          child: s.items.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: s.items.length,
                  itemBuilder: (_, i) => _bubble(s.items[i]),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.attach_file), onPressed: s.connected ? _attach : null),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()),
                ),
              ),
              IconButton.filled(icon: const Icon(Icons.send), onPressed: s.connected ? _send : null),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(ChatItem it) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: it.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: it.mine ? cs.primaryContainer : cs.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!it.mine)
              Text(it.from, style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary, fontSize: 12)),
            if (it.isFile) _fileBody(it) else SelectableText(it.text ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _fileBody(ChatItem it) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.insert_drive_file_outlined),
        const SizedBox(width: 8),
        Flexible(child: Text(it.fileName!, overflow: TextOverflow.ellipsis)),
      ]),
      if (it.size != null) Text(fmtSize(it.size!), style: const TextStyle(fontSize: 12)),
      if (it.progress != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: it.progress == 0 ? null : it.progress),
        )
      else if (it.localPath != null)
        TextButton.icon(
          onPressed: () => _open(it.localPath!),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Open'),
        )
      else
        TextButton.icon(
          onPressed: () => s.download(it),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download'),
        ),
      if (it.error != null) Text(it.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
    ]);
  }
}
