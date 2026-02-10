import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- HIGH-PERFORMANCE UDP SERVICE SINGLETON ---
class UdpService {
  static final UdpService _instance = UdpService._internal();
  factory UdpService() => _instance;
  UdpService._internal();

  RawDatagramSocket? _socket;
  String _serverIp = "127.0.0.1";
  final int port = 5005;

  final StreamController<Datagram> _dataStreamController =
      StreamController<Datagram>.broadcast();
  Stream<Datagram> get dataStream => _dataStreamController.stream;

  Future<void> init() async {
    if (_socket != null) return;
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? dg = _socket!.receive();
        if (dg != null) _dataStreamController.add(dg);
      }
    });
  }

  void setServerIp(String ip) => _serverIp = ip;
  void send(String message) =>
      _socket?.send(utf8.encode(message), InternetAddress(_serverIp), port);
  void sendBroadcast(String message) => _socket?.send(
    utf8.encode(message),
    InternetAddress("255.255.255.255"),
    port,
  );

  void dispose() {
    _socket?.close();
    _socket = null;
    _dataStreamController.close();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: UnifiedVmcScreen(),
    ),
  );
}

class UnifiedVmcScreen extends StatefulWidget {
  const UnifiedVmcScreen({super.key});
  @override
  State<UnifiedVmcScreen> createState() => _UnifiedVmcScreenState();
}

class _UnifiedVmcScreenState extends State<UnifiedVmcScreen> {
  final UdpService _udp = UdpService();
  StreamSubscription? _subscription;
  Timer? _discoveryTimer, _pingTimer, _healthCheckTimer;
  final Stopwatch _pingStopwatch = Stopwatch();

  // Connection State
  bool _isConnected = false;
  bool _isSearching = false;
  bool _isLocked = true;
  String _currentIp = "";
  int _latency = 0;
  DateTime _lastPingResponse = DateTime.now();
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initUdp();
  }

  Future<void> _initUdp() async {
    await _udp.init();
    _subscription = _udp.dataStream.listen((dg) {
      String msg = utf8.decode(dg.data);
      if (msg == "DISCOVER_VMC_RESPONSE" && !_isConnected) {
        _handleConnection(dg.address.address);
      } else if (msg == "pong" && mounted) {
        _lastPingResponse = DateTime.now(); // Perbarui detak jantung
        setState(() {
          _latency = _pingStopwatch.elapsedMilliseconds;
          _pingStopwatch.stop();
          _pingStopwatch.reset();
        });
      }
    });
  }

  void _startDiscovery() {
    setState(() => _isSearching = true);
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isConnected) _udp.sendBroadcast("DISCOVER_VMC_REQUEST");
    });
  }

  void _handleConnection(String ip) {
    _udp.setServerIp(ip);
    _discoveryTimer?.cancel();
    setState(() {
      _currentIp = ip;
      _isConnected = true;
      _isSearching = false;
      _lastPingResponse = DateTime.now();
    });
    _startControllerLoops();
    _startWatchdog();
  }

  void _startControllerLoops() {
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isConnected) {
        _pingStopwatch.start();
        _udp.send("ping");
      }
    });
  }

  void _startWatchdog() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_isConnected) {
        final diff = DateTime.now().difference(_lastPingResponse).inSeconds;
        if (diff > 3) {
          // Jika 3 detik tanpa pong, anggap mati
          _disconnect();
        }
      }
    });
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _healthCheckTimer?.cancel();
    _discoveryTimer?.cancel();
    setState(() {
      _isConnected = false;
      _isSearching = false;
      _isLocked = true;
      _currentIp = "";
      _latency = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: _isConnected ? _buildTransparentAppBar() : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _isConnected
            ? _buildGamepad()
            : (_isSearching ? _buildSearching() : _buildConnectMenu()),
      ),
    );
  }

  Widget _buildConnectMenu() {
    return Center(
      key: const ValueKey("menu"),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.cyanAccent.withOpacity(0.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.2),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.videogame_asset,
              size: 80,
              color: Colors.cyanAccent,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            "VGAMEPAD",
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
          ),
          const Text(
            "VIRTUAL CONTROLLER",
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 60),
          _buildMenuButton(
            icon: Icons.search,
            label: "AUTO SEARCH",
            onPressed: _startDiscovery,
            color: Colors.cyanAccent,
          ),
          const SizedBox(height: 16),
          _buildMenuButton(
            icon: Icons.edit,
            label: "MANUAL IP",
            onPressed: _showManualIpDialog,
            color: Colors.white,
            isOutlined: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
    bool isOutlined = false,
  }) {
    return SizedBox(
      width: 220,
      height: 50,
      child: isOutlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }

  Widget _buildSearching() {
    return Center(
      key: const ValueKey("searching"),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: Colors.cyanAccent,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            "SEARCHING FOR SERVER...",
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Make sure the server is running on your PC",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 40),
          TextButton.icon(
            onPressed: () {
              _discoveryTimer?.cancel();
              setState(() => _isSearching = false);
            },
            icon: const Icon(Icons.close, size: 16),
            label: const Text("CANCEL"),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
        ],
      ),
    );
  }

  void _showManualIpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Manual Connection",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter the IP address of the VMC server.",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _ipController,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: "192.168.1.100",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.lan,
                  color: Colors.cyanAccent,
                  size: 20,
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final ip = _ipController.text.trim();
              if (ip.isNotEmpty) {
                Navigator.pop(context);
                _handleConnection(ip);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text("CONNECT"),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTransparentAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 50,
      leadingWidth: 60,
      leading: IconButton(
        icon: Icon(
          Icons.link_off,
          color: _isLocked ? Colors.white10 : Colors.redAccent.withOpacity(0.7),
          size: 22,
        ),
        onPressed: _isLocked ? null : _disconnect,
        tooltip: _isLocked ? "Unlock to disconnect" : "Disconnect",
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "IP: $_currentIp",
            style: const TextStyle(
              color: Colors.white24,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            "${_latency}ms",
            style: TextStyle(
              color: _latency < 50 ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: _isLocked ? Colors.cyanAccent : Colors.white24,
            size: 20,
          ),
          onPressed: () => setState(() => _isLocked = true),
          onLongPress: () => setState(() => _isLocked = !_isLocked),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildGamepad() {
    return Padding(
      key: const ValueKey("gamepad"),
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildKeyRow(
                  [
                    "esc",
                    "f1",
                    "f2",
                    "f3",
                    "f4",
                    "f5",
                    "f6",
                    "f7",
                    "f8",
                    "f9",
                    "f10",
                    "f11",
                    "f12",
                  ],
                  flexes: [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                ),
                _buildKeyRow(
                  [
                    "`",
                    "1",
                    "2",
                    "3",
                    "4",
                    "5",
                    "6",
                    "7",
                    "8",
                    "9",
                    "0",
                    "-",
                    "=",
                    "backspace",
                  ],
                  flexes: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.2],
                ),
                _buildKeyRow(
                  [
                    "tab",
                    "q",
                    "w",
                    "e",
                    "r",
                    "t",
                    "y",
                    "u",
                    "i",
                    "o",
                    "p",
                    "[",
                    "]",
                    "\\",
                  ],
                  flexes: [1.6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                ),
                _buildKeyRow(
                  [
                    "caps",
                    "a",
                    "s",
                    "d",
                    "f",
                    "g",
                    "h",
                    "j",
                    "k",
                    "l",
                    ";",
                    "'",
                    "enter",
                  ],
                  flexes: [2.0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.0],
                ),
                _buildKeyRow(
                  [
                    "shift",
                    "z",
                    "x",
                    "c",
                    "v",
                    "b",
                    "n",
                    "m",
                    ",",
                    ".",
                    "/",
                    "shift",
                  ],
                  flexes: [2.6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.6],
                ),
                _buildKeyRow(
                  [
                    "fn",
                    "ctrl",
                    "alt",
                    "cmd",
                    "space",
                    "cmd",
                    "alt",
                    "left",
                    "up",
                    "down",
                    "right",
                  ],
                  flexes: [1, 1, 1, 1.2, 5.5, 1.2, 1, 1, 0.8, 0.8, 1],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys, {required List<double> flexes}) {
    return Expanded(
      child: Row(
        children: List.generate(keys.length, (i) {
          if (keys[i] == "up") {
            return Expanded(
              flex: (flexes[i] * 100).toInt(),
              child: Column(
                children: [
                  _buildKey("up", isStacked: true),
                  _buildKey("down", isStacked: true),
                ],
              ),
            );
          }
          if (keys[i] == "down") return const SizedBox.shrink();
          return _buildKey(keys[i], flex: flexes[i]);
        }),
      ),
    );
  }

  Widget _buildKey(
    String keyName, {
    double flex = 1.0,
    bool isStacked = false,
  }) {
    return Expanded(
      flex: isStacked ? 1 : (flex * 100).toInt(),
      child: Padding(
        padding: const EdgeInsets.all(1.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(3),
            onTapDown: (_) {
              HapticFeedback.vibrate();
              _udp.send("${keyName.toLowerCase()}:1.0");
            },
            onTapUp: (_) => _udp.send("${keyName.toLowerCase()}:0.0"),
            onTapCancel: () => _udp.send("${keyName.toLowerCase()}:0.0"),
            splashColor: Colors.white24,
            child: Container(
              decoration: BoxDecoration(
                color: _getButtonColor(keyName),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white10, width: 0.5),
              ),
              child: Center(
                child: Text(
                  keyName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: keyName.length > 3 ? 5 : 7,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getButtonColor(String key) {
    const modifiers = [
      'esc',
      'tab',
      'caps',
      'shift',
      'ctrl',
      'alt',
      'cmd',
      'fn',
      'backspace',
      'enter',
    ];
    return modifiers.contains(key.toLowerCase())
        ? const Color(0xFF2A2A2A)
        : const Color(0xFF1A1A1A);
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _pingTimer?.cancel();
    _healthCheckTimer?.cancel();
    _subscription?.cancel();
    _ipController.dispose();
    _udp.dispose();
    super.dispose();
  }
}
