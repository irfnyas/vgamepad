import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  // Layout Engine
  List<dynamic> _layout = [];
  List<dynamic> _manifest = [];
  String _activeLayout = 'keyboard.json';
  bool _isEditedLayout = false;
  List<String> _availableActions = [];
  int? _selectedKeyIndex;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _loadAvailableActions();
    _initUdp();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final savedLayout = _prefs!.getString('active_layout');
    if (savedLayout != null) {
      _activeLayout = savedLayout;
    }
    _loadManifest();
    _loadLayout();
  }

  String _generateNanoId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final rnd = math.Random();
    return String.fromCharCodes(
      Iterable.generate(12, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<void> _loadAvailableActions() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/layout/keyboard.json',
      );
      final List<dynamic> data = jsonDecode(response);
      setState(() {
        _availableActions = [
          ...data.map((e) => e['action'].toString()).toSet(),
          'mouse_left',
          'mouse_middle',
          'mouse_right',
          'mouse_cursor',
        ].toList()..sort();
      });
    } catch (e) {
      debugPrint("Error loading available actions: $e");
    }
  }

  Future<void> _loadManifest() async {
    try {
      // 1. Load asset manifest
      final String response = await rootBundle.loadString(
        'assets/layout/_manifest.json',
      );
      List<dynamic> assets = jsonDecode(response);

      // 2. Scan local documents for custom_*.json
      final directory = await getApplicationDocumentsDirectory();
      final List<FileSystemEntity> files = directory.listSync();
      List<dynamic> customs = [];

      for (var file in files) {
        if (file is File &&
            file.path.endsWith('.json') &&
            file.path.contains('custom_') &&
            !file.path.contains('_edited.json')) {
          final fileName = file.path.split('/').last;

          // Try to read metadata from the file itself
          String title =
              "Custom (${fileName.replaceAll('custom_', '').replaceAll('.json', '')})";
          String icon = "🎨";
          String description = "My created layout";

          try {
            final content = await file.readAsString();
            final data = jsonDecode(content);
            if (data is List &&
                data.isNotEmpty &&
                data[0] is Map &&
                data[0]['isMetadata'] == true) {
              final meta = data[0];
              title = meta['title'] ?? title;
              icon = meta['icon'] ?? icon;
              description = meta['description'] ?? description;
            }
          } catch (e) {
            debugPrint("Error reading metadata for $fileName: $e");
          }

          customs.add({
            "title": title,
            "id": fileName,
            "icon": icon,
            "description": description,
            "isCustom": true,
          });
        }
      }

      setState(() {
        _manifest = [...assets, ...customs];
      });
    } catch (e) {
      debugPrint("Error loading manifest: $e");
    }
  }

  Future<void> _saveAsNewLayout() async {
    final titleController = TextEditingController(text: "New Custom Layout");
    final iconController = TextEditingController(text: "🎨");
    final descController = TextEditingController(text: "User created layout");

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Save Layout", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: iconController,
                    maxLength: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                    decoration: const InputDecoration(
                      labelText: "Icon",
                      labelStyle: TextStyle(color: Colors.white38),
                      counterText: "",
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Title",
                      labelStyle: TextStyle(color: Colors.white38),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: "Description",
                labelStyle: TextStyle(color: Colors.white38),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final id = _generateNanoId();
      final fileName = 'custom_$id.json';
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');

      // Include metadata as the first element
      final fullData = [
        {
          "isMetadata": true,
          "title": titleController.text.trim(),
          "icon": iconController.text.trim(),
          "description": descController.text.trim(),
        },
        ..._layout,
      ];

      await file.writeAsString(jsonEncode(fullData));

      setState(() {
        _activeLayout = fileName;
        _isEditedLayout = false;
        _selectedKeyIndex = null;
      });

      _prefs?.setString('active_layout', fileName);
      _loadManifest(); // Refresh list

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved as new layout: ${titleController.text}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error creating new layout: $e")));
    }
  }

  Future<void> _deleteCustomLayout(String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }

      // Also delete the _edited version if it exists
      final editedFile = File(
        '${directory.path}/${fileName.replaceAll('.json', '')}_edited.json',
      );
      if (await editedFile.exists()) {
        await editedFile.delete();
      }

      if (_activeLayout == fileName) {
        _activeLayout = 'keyboard.json';
        _prefs?.setString('active_layout', _activeLayout);
        _loadLayout();
      }

      _loadManifest();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Custom layout deleted")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting layout: $e")));
    }
  }

  Future<void> _loadLayout() async {
    try {
      String jsonStr;
      final directory = await getApplicationDocumentsDirectory();
      final editedFile = File(
        '${directory.path}/${_activeLayout.replaceAll('.json', '')}_edited.json',
      );

      if (await editedFile.exists()) {
        jsonStr = await editedFile.readAsString();
        final data = jsonDecode(jsonStr);
        setState(() {
          _isEditedLayout = true;
          if (data is List &&
              data.isNotEmpty &&
              data[0] is Map &&
              data[0]['isMetadata'] == true) {
            _layout = data.sublist(1);
          } else {
            _layout = data;
          }
        });
      } else {
        jsonStr = await rootBundle.loadString('assets/layout/$_activeLayout');
        final data = jsonDecode(jsonStr);
        setState(() {
          _isEditedLayout = false;
          if (data is List &&
              data.isNotEmpty &&
              data[0] is Map &&
              data[0]['isMetadata'] == true) {
            _layout = data.sublist(1);
          } else {
            _layout = data;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading layout: $e");

      // fallback to keyboard layout
      _activeLayout = "keyboard.json";
      _loadLayout();
    }
  }

  Future<void> _saveLayout() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/${_activeLayout.replaceAll('.json', '')}_edited.json',
      );
      await file.writeAsString(jsonEncode(_layout));
      setState(() => _isEditedLayout = true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Layout saved locally")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error saving layout: $e")));
    }
  }

  Future<void> _resetLayout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Reset Layout",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to delete your custom mappings and revert to the default layout?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text("Reset"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/${_activeLayout.replaceAll('.json', '')}_edited.json',
      );
      if (await file.exists()) {
        await file.delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reverted to default layout")),
        );
        _loadLayout();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error resetting layout: $e")));
    }
  }

  void _addNewKey() {
    setState(() {
      final newKey = {
        "action": "new_key",
        "label": "NEW",
        "x1": 90,
        "y1": 45,
        "x2": 110,
        "y2": 55,
        "color": null,
      };
      _layout.add(newKey);
      _selectedKeyIndex = _layout.length - 1;
    });
    _saveLayout();
  }

  void _duplicateSelectedKey() {
    if (_selectedKeyIndex == null || _selectedKeyIndex! >= _layout.length) {
      return;
    }

    setState(() {
      final source = _layout[_selectedKeyIndex!];
      final newKey = Map<String, dynamic>.from(source);

      // Offset the duplicate slightly so it's visible
      newKey["x1"] = (newKey["x1"] + 5).clamp(0, 195);
      newKey["x2"] = (newKey["x2"] + 5).clamp(5, 200);
      newKey["y1"] = (newKey["y1"] + 5).clamp(0, 95);
      newKey["y2"] = (newKey["y2"] + 5).clamp(5, 100);
      newKey["color"] = source["color"];

      _layout.add(newKey);
      _selectedKeyIndex = _layout.length - 1;
    });
    _saveLayout();
  }

  void _removeSelectedKey() async {
    if (_selectedKeyIndex == null || _selectedKeyIndex! >= _layout.length) {
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Delete Key", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to remove this key? This cannot be undone.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _layout.removeAt(_selectedKeyIndex!);
      _selectedKeyIndex = null;
    });
    _saveLayout();
  }

  Future<void> _initUdp() async {
    await _udp.init();
    _subscription = _udp.dataStream.listen((dg) {
      String msg = utf8.decode(dg.data);
      if (msg == "DISCOVER_VMC_RESPONSE" && !_isConnected) {
        _handleConnection(dg.address.address);
      } else if (msg == "pong" && mounted) {
        _lastPingResponse = DateTime.now();
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
        if (diff > 3) _disconnect();
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
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.2),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMenuButton(
                icon: Icons.search,
                label: "AUTO SEARCH",
                onPressed: _startDiscovery,
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 16),
              _buildMenuButton(
                icon: Icons.edit,
                label: "MANUAL IP",
                onPressed: _showManualIpDialog,
                color: Colors.white,
                isOutlined: true,
              ),
            ],
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
                side: BorderSide(color: color.withValues(alpha: 0.5)),
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
                fillColor: Colors.white.withValues(alpha: 0.05),
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
          color: _isLocked
              ? Colors.white24
              : Colors.redAccent.withValues(alpha: 0.7),
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
              color: Colors.white38,
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
        if (!_isLocked &&
            _selectedKeyIndex != null &&
            _selectedKeyIndex! < _layout.length)
          Builder(
            builder: (context) {
              final k = _layout[_selectedKeyIndex!];
              return TextButton.icon(
                onPressed: () => _showPositionDialog(k),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(
                  Icons.edit,
                  size: 14,
                  color: Colors.cyanAccent,
                ),
                label: Text(
                  "X(${k["x1"]},${k["x2"]}) Y(${k["y1"]},${k["y2"]})",
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        if (!_isLocked && _selectedKeyIndex != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.copy,
                  size: 18,
                  color: Colors.cyanAccent,
                ),
                onPressed: _duplicateSelectedKey,
                tooltip: "Duplicate key",
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.redAccent,
                ),
                onPressed: _removeSelectedKey,
                tooltip: "Remove key",
              ),
              IconButton(
                icon: const Icon(
                  Icons.palette_outlined,
                  size: 20,
                  color: Colors.cyanAccent,
                ),
                onPressed: () => _showColorDialog(_layout[_selectedKeyIndex!]),
                tooltip: "Edit color",
              ),
            ],
          ),
        if (!_isLocked && _selectedKeyIndex == null)
          IconButton(
            icon: const Icon(Icons.add, size: 20, color: Colors.cyanAccent),
            onPressed: _addNewKey,
            tooltip: "Add new key",
          ),
        if (!_isLocked && _isEditedLayout)
          IconButton(
            icon: const Icon(Icons.save_as, color: Colors.cyanAccent, size: 20),
            tooltip: "Save as new layout",
            onPressed: _saveAsNewLayout,
          ),
        if (!_isLocked && _isEditedLayout)
          IconButton(
            icon: const Icon(
              Icons.restore,
              color: Colors.orangeAccent,
              size: 20,
            ),
            tooltip: "Reset to default",
            onPressed: _resetLayout,
          ),
        if (_selectedKeyIndex == null && !_isLocked)
          IconButton(
            icon: Icon(
              Icons.layers,
              color: _isLocked ? Colors.white24 : Colors.cyanAccent,
              size: 20,
            ),
            onPressed: _isLocked ? null : _showLayoutSheet,
          ),
        IconButton(
          icon: Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: Colors.cyanAccent,
            size: 20,
          ),
          onPressed: () => setState(() {
            _isLocked = true;
            _selectedKeyIndex = null;
          }),
          onLongPress: () => setState(() {
            _isLocked = !_isLocked;
            if (_isLocked) _selectedKeyIndex = null;
          }),
          tooltip: _isLocked ? "Long press to unlock" : "Press to lock",
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildGamepad() {
    if (_layout.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    return LayoutBuilder(
      key: const ValueKey("gamepad"),
      builder: (context, constraints) {
        final double unitW = constraints.maxWidth / 200;
        final double unitH = constraints.maxHeight / 100;

        return GestureDetector(
          onTap: () {
            if (_selectedKeyIndex != null) {
              setState(() => _selectedKeyIndex = null);
            }
          },
          child: Stack(
            children: [
              // Use a transparent background container to catch taps
              Positioned.fill(child: Container(color: Colors.transparent)),
              ..._layout.asMap().entries.map((entry) {
                final int index = entry.key;
                final Map<String, dynamic> k = entry.value;
                final double x = k["x1"].toDouble() * unitW;
                final double y = k["y1"].toDouble() * unitH;
                final double w = (k["x2"] - k["x1"]).toDouble() * unitW;
                final double h = (k["y2"] - k["y1"]).toDouble() * unitH;

                final isSelected = _selectedKeyIndex == index;

                return Positioned(
                  left: x,
                  top: y,
                  width: w,
                  height: h,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: !_isLocked && _selectedKeyIndex == null
                            ? () => _showEditDialog(k)
                            : null,
                        onLongPress: !_isLocked
                            ? () {
                                setState(() {
                                  final selectedKey = _layout.removeAt(index);
                                  _layout.add(selectedKey);
                                  _selectedKeyIndex = _layout.length - 1;
                                });
                              }
                            : null,
                        onPanUpdate: isSelected && !_isLocked
                            ? (details) {
                                setState(() {
                                  double dx = details.delta.dx / unitW;
                                  double dy = details.delta.dy / unitH;

                                  double currentW = (k["x2"] - k["x1"])
                                      .toDouble();
                                  double currentH = (k["y2"] - k["y1"])
                                      .toDouble();

                                  k["x1"] = (k["x1"] + dx)
                                      .clamp(0, 200 - currentW)
                                      .round();
                                  k["x2"] = (k["x1"] + currentW)
                                      .clamp(0, 200)
                                      .round();
                                  k["y1"] = (k["y1"] + dy)
                                      .clamp(0, 100 - currentH)
                                      .round();
                                  k["y2"] = (k["y1"] + currentH)
                                      .clamp(0, 100)
                                      .round();
                                });
                              }
                            : null,
                        onPanEnd: isSelected && !_isLocked
                            ? (_) => _saveLayout()
                            : null,
                        child: Container(
                          decoration: isSelected
                              ? BoxDecoration(
                                  border: Border.all(
                                    color: Colors.cyanAccent,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                )
                              : null,
                          child: _buildKey(k, isSelected),
                        ),
                      ),
                      if (isSelected && !_isLocked)
                        Positioned(
                          right: -24,
                          bottom: -24,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              setState(() {
                                double dx = details.delta.dx / unitW;
                                double dy = details.delta.dy / unitH;
                                k["x2"] = (k["x2"] + dx)
                                    .clamp(k["x1"] + 5, 200)
                                    .round();
                                k["y2"] = (k["y2"] + dy)
                                    .clamp(k["y1"] + 5, 100)
                                    .round();
                              });
                            },
                            onPanEnd: (_) => _saveLayout(),
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.open_in_full,
                                  size: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKey(Map<String, dynamic> k, [bool isSelected = false]) {
    final String action = k["action"];
    final String label = k["label"];

    Color? customColor;
    if (k["color"] != null) {
      try {
        final hexString = k["color"].toString().replaceAll('#', '');
        customColor = Color(int.parse('FF$hexString', radix: 16));
      } catch (e) {
        debugPrint("Invalid hex color: ${k["color"]}");
      }
    }

    if (k["action"] == "mouse_cursor") {
      return MouseWidget(
        k: k,
        isLocked: _isLocked,
        onSend: (msg) {
          if (_isLocked) _udp.send(msg);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.all(1.0),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: customColor ?? _getButtonColor(action),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: !_isLocked
                  ? Colors.cyanAccent.withValues(alpha: 0.3)
                  : Colors.white10,
              width: 0.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(3),
            onDoubleTap: _isLocked && action.contains('mouse_')
                ? () {
                    HapticFeedback.vibrate();
                    _udp.send("${action.toLowerCase()}:double");
                  }
                : null,
            onTap: !_isLocked && _selectedKeyIndex == null
                ? () => _showEditDialog(k)
                : null,
            onTapDown: _isLocked
                ? (_) {
                    HapticFeedback.vibrate();
                    _udp.send("${action.toLowerCase()}:1.0");
                  }
                : null,
            onTapUp: _isLocked
                ? (_) {
                    _udp.send("${action.toLowerCase()}:0.0");
                  }
                : null,
            onTapCancel: _isLocked
                ? () {
                    _udp.send("${action.toLowerCase()}:0.0");
                  }
                : null,
            child: Container(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    !_isLocked ? "$label\n'$action'" : label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: !_isLocked ? Colors.cyanAccent : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: !_isLocked ? 8 : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPositionDialog(Map<String, dynamic> k) {
    final x1Controller = TextEditingController(text: k["x1"].toString());
    final x2Controller = TextEditingController(text: k["x2"].toString());
    final y1Controller = TextEditingController(text: k["y1"].toString());
    final y2Controller = TextEditingController(text: k["y2"].toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Edit Position",
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Grid System: X(0-200), Y(0-100)",
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: Listenable.merge([
                  x1Controller,
                  x2Controller,
                  y1Controller,
                  y2Controller,
                ]),
                builder: (context, _) {
                  final x1 = int.tryParse(x1Controller.text) ?? -1;
                  final x2 = int.tryParse(x2Controller.text) ?? -1;
                  final y1 = int.tryParse(y1Controller.text) ?? -1;
                  final y2 = int.tryParse(y2Controller.text) ?? -1;

                  final bool xRangeValid =
                      x1 >= 0 && x1 <= 200 && x2 >= 0 && x2 <= 200;
                  final bool yRangeValid =
                      y1 >= 0 && y1 <= 100 && y2 >= 0 && y2 <= 100;
                  final bool sizeValid = (x2 - x1) >= 5 && (y2 - y1) >= 5;

                  final bool isValid = xRangeValid && yRangeValid && sizeValid;

                  return Column(
                    children: [
                      Text(
                        "Width: ${x2 - x1}, Height: ${y2 - y1}",
                        style: TextStyle(
                          color: isValid ? Colors.cyanAccent : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!isValid)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            !xRangeValid || !yRangeValid
                                ? "Out of bounds: X(0-200), Y(0-100)"
                                : "Invalid size: width & height must be >= 5",
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 8,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildCoordField("X1", x1Controller)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCoordField("X2", x2Controller)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildCoordField("Y1", y1Controller)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCoordField("Y2", y2Controller)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([
              x1Controller,
              x2Controller,
              y1Controller,
              y2Controller,
            ]),
            builder: (context, _) {
              final x1 = int.tryParse(x1Controller.text) ?? -1;
              final x2 = int.tryParse(x2Controller.text) ?? -1;
              final y1 = int.tryParse(y1Controller.text) ?? -1;
              final y2 = int.tryParse(y2Controller.text) ?? -1;

              final bool isValid =
                  x1 >= 0 &&
                  x1 <= 200 &&
                  x2 >= 0 &&
                  x2 <= 200 &&
                  y1 >= 0 &&
                  y1 <= 100 &&
                  y2 >= 0 &&
                  y2 <= 100 &&
                  (x2 - x1) >= 5 &&
                  (y2 - y1) >= 5;

              return ElevatedButton(
                onPressed: isValid
                    ? () {
                        setState(() {
                          k["x1"] = x1;
                          k["x2"] = x2;
                          k["y1"] = y1;
                          k["y2"] = y2;
                        });
                        _selectedKeyIndex = null;
                        _saveLayout();
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text("Save"),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCoordField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
      ),
      style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
    );
  }

  void _showEditDialog(Map<String, dynamic> k) {
    final labelController = TextEditingController(text: k["label"]);
    final actionController = TextEditingController(text: k["action"]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Edit Key", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Position: X(${k["x1"]},${k["x2"]}) Y(${k["y1"]},${k["y2"]})",
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: "Label",
                        hintText: k["label"],
                        hintStyle: const TextStyle(color: Colors.white24),
                        labelStyle: const TextStyle(color: Colors.white70),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Autocomplete<String>(
                      initialValue: TextEditingValue(text: k["action"]),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return _availableActions;
                        }
                        return _availableActions.where((String option) {
                          return option.contains(
                            textEditingValue.text.toLowerCase(),
                          );
                        });
                      },
                      onSelected: (String selection) {
                        actionController.text = selection;
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            // Sync initial value and manual edits
                            if (controller.text != actionController.text &&
                                actionController.text.isNotEmpty &&
                                controller.text.isEmpty) {
                              controller.text = actionController.text;
                            }
                            controller.addListener(() {
                              actionController.text = controller.text;
                            });

                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: "Action",
                                hintText: k["action"],
                                hintStyle: const TextStyle(
                                  color: Colors.white24,
                                ),
                                labelStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            );
                          },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            color: const Color(0xFF2A2A2A),
                            child: SizedBox(
                              height: 200,
                              width: 200, // Should ideally match field width
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(
                                    index,
                                  );
                                  return ListTile(
                                    title: Text(
                                      option,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([labelController, actionController]),
            builder: (context, _) {
              final bool isValid =
                  labelController.text.trim().isNotEmpty &&
                  actionController.text.trim().isNotEmpty;
              return ElevatedButton(
                onPressed: isValid
                    ? () {
                        setState(() {
                          k["label"] = labelController.text.trim();
                          k["action"] = actionController.text.trim();
                        });
                        _saveLayout();
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text("Save"),
              );
            },
          ),
        ],
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

  void _showLayoutSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      barrierColor: Colors.black54,
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.8,
              expand: false,
              builder: (context, scrollController) {
                return ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    top: 24,
                    left: 16,
                    right: 16,
                    bottom: 24 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: _manifest.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const Text(
                            "SELECT INTERFACE",
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }

                    final item = _manifest[index - 1];
                    final bool isLocked = item["isLocked"] ?? false;

                    if (isLocked) {
                      return _buildLockedOption(
                        item["title"],
                        item["icon"],
                        item["description"] ?? "",
                      );
                    }

                    return _buildLayoutOption(
                      item["title"],
                      item["id"],
                      item["icon"],
                      item["description"] ?? "",
                      isCustom: item["isCustom"] ?? false,
                      onDelete: () {
                        setSheetState(() {});
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLayoutOption(
    String title,
    String fileName,
    String icon,
    String description, {
    bool isCustom = false,
    VoidCallback? onDelete,
  }) {
    final bool isSelected = _activeLayout == fileName;
    return ListSelectionItem(
      title: title,
      icon: icon,
      description:
          '$description (${fileName.replaceAll('custom_', '').replaceAll('.json', '')})',
      isSelected: isSelected,
      onTap: () {
        setState(() => _activeLayout = fileName);
        _prefs?.setString('active_layout', fileName);
        _loadLayout();
        Navigator.pop(context);
      },
      trailing: isCustom
          ? IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 20,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text(
                      "Delete Layout",
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      "Remove this custom layout?",
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx); // Close dialog
                          await _deleteCustomLayout(fileName);
                          if (!mounted) return;
                          Navigator.pop(context); // Close bottom sheet
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );
              },
            )
          : isSelected
          ? const Icon(Icons.check_circle, color: Colors.cyanAccent, size: 18)
          : null,
    );
  }

  Widget _buildLockedOption(String title, String icon, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        leading: Text(
          icon,
          style: const TextStyle(fontSize: 24, color: Colors.white10),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white10,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(color: Colors.white10, fontSize: 11),
        ),
        trailing: const Icon(
          Icons.lock_outline,
          color: Colors.white10,
          size: 18,
        ),
      ),
    );
  }

  void _showColorDialog(Map<String, dynamic> k) {
    final TextEditingController hexController = TextEditingController(
      text: k["color"]?.toString().replaceAll('#', '') ?? "",
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text(
              "Edit Color",
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: hexController,
                  onChanged: (val) => setDialogState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Hex Code",
                    labelStyle: TextStyle(color: Colors.white38),
                    hintText: "e.g. FF5722",
                    hintStyle: TextStyle(color: Colors.white10),
                    prefixText: "#",
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Presets",
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildColorPreset(
                      null,
                      const Color(0xFF1A1A1A),
                      hexController,
                      isSelected: hexController.text.trim().isEmpty,
                      onSelect: () => setDialogState(() {}),
                    ),
                    _buildColorPreset(
                      "2A2A2A",
                      const Color(0xFF2A2A2A),
                      hexController,
                      isSelected:
                          hexController.text.trim().toUpperCase() == "2A2A2A",
                      onSelect: () => setDialogState(() {}),
                    ),
                    _buildColorPreset(
                      "311B1B",
                      const Color(0xFF311B1B),
                      hexController,
                      isSelected:
                          hexController.text.trim().toUpperCase() == "311B1B",
                      onSelect: () => setDialogState(() {}),
                    ),
                    _buildColorPreset(
                      "1B311B",
                      const Color(0xFF1B311B),
                      hexController,
                      isSelected:
                          hexController.text.trim().toUpperCase() == "1B311B",
                      onSelect: () => setDialogState(() {}),
                    ),
                    _buildColorPreset(
                      "1B2631",
                      const Color(0xFF1B2631),
                      hexController,
                      isSelected:
                          hexController.text.trim().toUpperCase() == "1B2631",
                      onSelect: () => setDialogState(() {}),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    String hex = hexController.text.trim().replaceAll('#', '');
                    k["color"] = hex.isEmpty ? null : hex;
                  });
                  _saveLayout();
                  Navigator.pop(context);
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColorPreset(
    String? hex,
    Color previewColor,
    TextEditingController controller, {
    bool isSelected = false,
    VoidCallback? onSelect,
  }) {
    return InkWell(
      onTap: () {
        controller.text = hex ?? "";
        onSelect?.call();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: previewColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.3),
                    spreadRadius: 2,
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
      ),
    );
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

class ListSelectionItem extends StatelessWidget {
  final String title;
  final String icon;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  const ListSelectionItem({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.cyanAccent.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.cyanAccent : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Text(icon, style: const TextStyle(fontSize: 24)),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            color: isSelected ? Colors.white38 : Colors.white24,
            fontSize: 11,
          ),
        ),
        trailing:
            trailing ??
            (isSelected
                ? const Icon(
                    Icons.check_circle,
                    color: Colors.cyanAccent,
                    size: 18,
                  )
                : null),
      ),
    );
  }
}

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

class MouseWidget extends StatefulWidget {
  final Map<String, dynamic> k;
  final bool isLocked;
  final Function(String) onSend;

  const MouseWidget({
    super.key,
    required this.k,
    required this.isLocked,
    required this.onSend,
  });

  @override
  State<MouseWidget> createState() => _MouseWidgetState();
}

class _MouseWidgetState extends State<MouseWidget> {
  Offset _knobOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double radius =
            math.min(constraints.maxWidth, constraints.maxHeight) / 2;

        return GestureDetector(
          onPanUpdate: widget.isLocked
              ? (details) {
                  setState(() {
                    final RenderBox box =
                        context.findRenderObject() as RenderBox;
                    final Offset localPos = box.globalToLocal(
                      details.globalPosition,
                    );
                    final Offset center = Offset(
                      constraints.maxWidth / 2,
                      constraints.maxHeight / 2,
                    );

                    Offset deltaFromCenter = localPos - center;
                    // Normalize and clamp to circle for visual knob
                    double dist = deltaFromCenter.distance;
                    if (dist > radius) {
                      deltaFromCenter = Offset.fromDirection(
                        deltaFromCenter.direction,
                        radius,
                      );
                    }
                    _knobOffset = Offset(
                      deltaFromCenter.dx / radius,
                      deltaFromCenter.dy / radius,
                    );
                  });

                  // Send actual touch delta for trackpad behavior
                  final double dx = details.delta.dx;
                  final double dy = details.delta.dy;
                  if (dx != 0 || dy != 0) {
                    widget.onSend("${widget.k["action"]}:$dx:$dy");
                  }
                }
              : null,
          onPanEnd: widget.isLocked
              ? (_) {
                  setState(() {
                    _knobOffset = Offset.zero;
                  });
                }
              : null,
          onPanCancel: widget.isLocked
              ? () {
                  setState(() {
                    _knobOffset = Offset.zero;
                  });
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isLocked
                    ? Colors.white10
                    : Colors.cyanAccent.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: 0.2,
                    child: Text(
                      widget.k["label"] ?? "MOUSE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: _knobOffset * (radius * 0.8),
                    child: Container(
                      width: radius * 0.6,
                      height: radius * 0.6,
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.mouse, color: Colors.black, size: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
