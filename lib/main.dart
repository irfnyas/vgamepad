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
  String _currentIp = "";
  int _latency = 0;
  DateTime _lastPingResponse = DateTime.now();

  @override
  void initState() {
    super.initState();
    _setupDiscovery();
  }

  Future<void> _setupDiscovery() async {
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

    _discoveryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isConnected) _udp.sendBroadcast("DISCOVER_VMC_REQUEST");
    });
  }

  void _handleConnection(String ip) {
    _udp.setServerIp(ip);
    setState(() {
      _currentIp = ip;
      _isConnected = true;
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
    setState(() {
      _isConnected = false;
      _currentIp = "";
      _latency = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _isConnected ? _buildGamepad() : _buildConnecting(),
      ),
    );
  }

  Widget _buildConnecting() {
    return Center(
      key: const ValueKey("connecting"),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_tethering, size: 60, color: Colors.cyanAccent),
          const SizedBox(height: 20),
          const Text(
            "Searching for VMC Server...",
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 25),
          const CircularProgressIndicator(
            color: Colors.cyanAccent,
            strokeWidth: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildGamepad() {
    return Stack(
      key: const ValueKey("gamepad"),
      children: [
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 35),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
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
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 15,
          right: 15,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _disconnect,
                child: const Icon(
                  Icons.link_off,
                  color: Colors.white24,
                  size: 18,
                ),
              ),
              Text(
                "IP: $_currentIp | ${_latency}ms",
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
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
    _udp.dispose();
    super.dispose();
  }
}
