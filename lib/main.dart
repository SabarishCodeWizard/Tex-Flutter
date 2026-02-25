import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RobotControllerApp());
}

// --- 1. THEME & COLORS ---
class AppColors {
  static const bgMain = Color(0xFF1E1E2E);
  static const bgPanel = Color(0xFF27273A);
  static const border = Color(0xFF3F3F5F);
  static const textMain = Colors.white;
  static const textSec = Color(0xFFB0B0C0);
  static const accentBlue = Color(0xFF40C4FF);
  static const accentGreen = Color(0xFF00E676); 
  static const accentRed = Color(0xFFFF5252); 
  static const accentPurple = Color(0xFF9B59B6);
  static const accentYellow = Color(0xFFF39C12);
  static const btnBg = Color(0xFF32324A);
  static const lcdBg = Color(0xFF1A1A24); 
}

class RobotControllerApp extends StatelessWidget {
  const RobotControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Robot Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bgMain,
        cardColor: AppColors.bgPanel,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgPanel,
          elevation: 0,
          centerTitle: true,
        ),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentBlue,
          surface: AppColors.bgPanel,
        ),
      ),
      home: const ControllerScreen(),
    );
  }
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  // --- STATE VARIABLES ---
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.51");
  final TextEditingController _mmSpeedCtrl = TextEditingController(text: "50.0");
  final TextEditingController _degSpeedCtrl = TextEditingController(text: "50.0");

  String _selectedMmInc = "mm";
  String _selectedDegInc = "deg";
  final List<String> _mmOptions = ["mm", "50", "25", "15", "10", "5", "2", "1", "0.1", "0.01", "0.001"];
  final List<String> _degOptions = ["deg", "20", "15", "10", "5", "2", "1", "0.1", "0.01", "0.001", "0.0001"];

  WebSocketChannel? _channel;
  String _wsStatus = "DISCONNECTED";
  Color _wsStatusColor = AppColors.accentRed;

  // Robot State
  bool _servoOn = false;
  String _mode = "Unknown"; 
  String _errorMsg = "No error";
  String _lastErrorMsg = "No error";
  bool _isStarted = false;
  bool _isPaused = false;
  double _globalSpeed = 50.0;
  double _currentSpeedOp = 0.0;
  String _frame = "Base";
  String _motionType = "JOG"; 
  String _tpRunMode = "TP Mode"; 
  
  // File Tracking State
  String _currentTpName = "None"; 
  List<String> _tpFileList = []; // Stores the raw file strings from backend

  // --- LIVE DATA ---
  Map<String, double> _cartesian = {'x': 0.0, 'y': 0.0, 'z': 0.0, 'rx': 0.0, 'ry': 0.0, 'rz': 0.0};
  Map<String, double> _joints = {'j1': 0.0, 'j2': 0.0, 'j3': 0.0, 'j4': 0.0, 'j5': 0.0, 'j6': 0.0};
  List<Map<String, dynamic>> _tpList = []; // The actual target points inside a file

  String _currentView = "MAIN";

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _channel?.sink.close();
    super.dispose();
  }

  // --- WEBSOCKET LOGIC ---
  void _connect() {
    if (_wsStatus == "CONNECTED" || _wsStatus == "CONNECTING...") return;

    if (_channel != null) {
      _channel!.sink.close();
    }

    setState(() {
      _wsStatus = "CONNECTING...";
      _wsStatusColor = AppColors.accentYellow;
    });

    try {
      final wsUrl = Uri.parse("ws://${_ipController.text}:8080");
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        _handleMessage,
        onDone: () {
          if (_wsStatus == "WAITING..." || _wsStatus == "CONNECTING...") {
            _showConnectionRejectedPopup();
          }
          setState(() {
            _wsStatus = "DISCONNECTED";
            _wsStatusColor = AppColors.accentRed;
          });
        },
        onError: (error) {
          setState(() {
            _wsStatus = "ERROR";
            _wsStatusColor = AppColors.accentRed;
          });
        },
      );

      setState(() {
        _wsStatus = "WAITING...";
      });
    } catch (e) {
      setState(() {
        _wsStatus = "INVALID IP";
        _wsStatusColor = AppColors.accentRed;
      });
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _wsStatus = "DISCONNECTED";
      _wsStatusColor = AppColors.accentRed;
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'connection_rejected') {
        _showConnectionRejectedPopup();
        _disconnect();
      } else if (data['type'] == 'connection_accepted') {
        setState(() {
          _wsStatus = "CONNECTED";
          _wsStatusColor = AppColors.accentGreen;
        });
      } else if (data['type'] == 'status_update') {
        setState(() {
          _mode = data['mode'] ?? "Unknown";
          _servoOn = data['servo_on'] ?? false;
          _isStarted = data['started'] ?? false;
          _isPaused = data['paused'] ?? false;
          _tpRunMode = data['tp_run_mode'] ?? "TP Mode";
          _currentSpeedOp = (data['speed_op'] as num?)?.toDouble() ?? 0.0;
          
          _currentTpName = data['current_tp_name'] ?? "None";

          // Extract the TP File List (used for Opening/Deleting files)
          if (data['tp_file_list'] != null) {
            _tpFileList = List<String>.from(data['tp_file_list']);
          }

          // Error handling
          String newError = data['error_message'] ?? "No error";
          if (newError != "No error" && newError != _lastErrorMsg) {
            _showErrorPopup(newError);
          }
          _lastErrorMsg = newError;
          _errorMsg = newError;

          if (data['cartesian'] != null) {
            _cartesian['x'] = (data['cartesian']['x'] as num).toDouble();
            _cartesian['y'] = (data['cartesian']['y'] as num).toDouble();
            _cartesian['z'] = (data['cartesian']['z'] as num).toDouble();
            _cartesian['rx'] = (data['cartesian']['rx'] as num).toDouble();
            _cartesian['ry'] = (data['cartesian']['ry'] as num).toDouble();
            _cartesian['rz'] = (data['cartesian']['rz'] as num).toDouble();
          }

          if (data['joints'] != null) {
            _joints['j1'] = (data['joints']['j1'] as num).toDouble();
            _joints['j2'] = (data['joints']['j2'] as num).toDouble();
            _joints['j3'] = (data['joints']['j3'] as num).toDouble();
            _joints['j4'] = (data['joints']['j4'] as num).toDouble();
            _joints['j5'] = (data['joints']['j5'] as num).toDouble();
            _joints['j6'] = (data['joints']['j6'] as num).toDouble();
          }

          if (data['tp_list'] != null) {
            _tpList = List<Map<String, dynamic>>.from(data['tp_list']);
          }
        });
      }
    } catch (e) {
      debugPrint("Parse error: $e");
    }
  }

  void _sendCommand(String cmd, [dynamic value = ""]) {
    if (_wsStatus == "CONNECTED" && _channel != null) {
      final jsonMsg = jsonEncode({"command": cmd, "value": value.toString()});
      _channel!.sink.add(jsonMsg);
    }
  }

  void _sendModifyCommand(String name, String x, String y, String z) {
    if (_wsStatus == "CONNECTED" && _channel != null) {
      final jsonMsg = jsonEncode({
        "command": "MODIFY_TP",
        "data": {"name": name, "x": x, "y": y, "z": z}
      });
      _channel!.sink.add(jsonMsg);
    }
  }

  void _onPadInteract(String axis, bool isDown) {
    if (_motionType == 'JOG') {
      if (isDown) _sendCommand('BTN_PRESS', axis);
      else _sendCommand('BTN_RELEASE', axis);
    } else if (_motionType == 'MOVE') {
      if (isDown) _sendCommand('BTN_CLICK', axis);
    }
  }

  // --- VIEW SWITCHING LOGIC ---
  void _openSpeed() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _currentView = "SPEED");
  }

  void _openCartesian() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    setState(() => _currentView = "CARTESIAN");
  }

  void _openJoints() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _currentView = "JOINTS");
  }

  void _goBackToMain() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _currentView = "MAIN");
  }

  // =========================================================================
  // 1. TP FILE MANAGEMENT (NEW, OPEN, DELETE FILES)
  // =========================================================================

  void _showNewTpFileDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentBlue, width: 1)),
        title: const Text("Create TP File", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: "File Name (e.g., job_01)", labelStyle: TextStyle(color: Colors.grey), border: OutlineInputBorder(), filled: true, fillColor: AppColors.bgMain),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                _sendCommand('NEW_TP_FILE', nameCtrl.text); 
                Navigator.pop(ctx);
              }
            },
            child: const Text("CREATE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showTpFileListSheet(String actionTitle) {
    IconData actionIcon = actionTitle == "Open" ? Icons.folder_open : Icons.delete_forever;
    Color actionColor = actionTitle == "Open" ? AppColors.accentYellow : AppColors.accentRed;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 15),
            Text("$actionTitle TP File", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: actionColor)),
            const Divider(color: AppColors.border, height: 30),
            Expanded(
              child: _tpFileList.isEmpty 
                ? const Center(child: Text("No files available.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                : ListView.builder(
                    itemCount: _tpFileList.length,
                    itemBuilder: (ctx, i) {
                      final fileData = _tpFileList[i].split('|');
                      final fileName = fileData[0];
                      final fileDate = fileData.length > 1 ? fileData[1] : "";
                      
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file, color: AppColors.accentBlue),
                        title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text(fileDate, style: const TextStyle(fontFamily: 'monospace', color: Colors.grey, fontSize: 12)),
                        trailing: Icon(actionIcon, color: actionColor, size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (actionTitle == "Open") {
                            _sendCommand('OPEN_TP_FILE', fileName);
                          } else {
                            _showDeleteFileConfirmDialog(fileName);
                          }
                        },
                      );
                    }
                  ),
            ),
          ],
        ),
      )
    );
  }

  void _showDeleteFileConfirmDialog(String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentRed, width: 1)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.accentRed),
            SizedBox(width: 10),
            Text("Delete File?", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text("Are you sure you want to permanently delete the file '$fileName'?", style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () {
              _sendCommand('DELETE_TP_FILE', fileName);
              Navigator.pop(ctx);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  // =========================================================================
  // 2. TP POINT MANAGEMENT (INSERT, MODIFY, DELETE, RUN POINTS)
  // =========================================================================

  void _showTpModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentBlue, width: 1)),
        title: const Text("Select TP Mode", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text("TP Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: _tpRunMode == "TP Mode" ? const Icon(Icons.check, color: AppColors.accentGreen) : null,
              onTap: () { _sendCommand('SET_TP_RUN_MODE', 'Tp'); Navigator.pop(ctx); },
            ),
            ListTile(
              title: const Text("MOVJ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: _tpRunMode == "MOVJ" ? const Icon(Icons.check, color: AppColors.accentGreen) : null,
              onTap: () { _sendCommand('SET_TP_RUN_MODE', 'MOVJ'); Navigator.pop(ctx); },
            ),
            ListTile(
              title: const Text("MOVL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: _tpRunMode == "MOVL" ? const Icon(Icons.check, color: AppColors.accentGreen) : null,
              onTap: () { _sendCommand('SET_TP_RUN_MODE', 'MOVL'); Navigator.pop(ctx); },
            ),
          ],
        ),
      )
    );
  }

  void _showTpSelectionSheet(String actionTitle, Function(int index, Map<String, dynamic> tp) onSelect) {
    IconData getIcon() {
      if (actionTitle == "Modify") return Icons.edit;
      if (actionTitle == "Run") return Icons.play_arrow;
      return Icons.delete;
    }
    Color getColor() {
      if (actionTitle == "Modify") return AppColors.accentBlue;
      if (actionTitle == "Run") return AppColors.accentGreen;
      return AppColors.accentRed;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 15),
            Text("$actionTitle TP Point", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: getColor())),
            const Divider(color: AppColors.border, height: 30),
            Expanded(
              child: _tpList.isEmpty 
                ? const Center(child: Text("No TP points available.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                : ListView.builder(
                    itemCount: _tpList.length,
                    itemBuilder: (ctx, i) {
                      final tp = _tpList[i];
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: AppColors.btnBg, child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontSize: 12))),
                        title: Text(tp['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text(tp['value'] ?? "", style: const TextStyle(fontFamily: 'monospace', color: Colors.grey, fontSize: 12)),
                        trailing: Icon(getIcon(), color: getColor(), size: 20),
                        onTap: () {
                          Navigator.pop(ctx);
                          onSelect(i, tp);
                        },
                      );
                    }
                  ),
            ),
          ],
        ),
      )
    );
  }

  void _showRunConfirmDialog(int index, Map<String, dynamic> tp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentGreen, width: 1)),
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill, color: AppColors.accentGreen),
            SizedBox(width: 10),
            Text("Run Point?", style: TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${tp['name']}", style: const TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
            Text("Data: ${tp['value']}", style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen),
            onPressed: () {
              _sendCommand('SELECT_TP_INDEX', index); 
              _sendCommand('RUN_TP');
              Navigator.pop(ctx);
            },
            child: const Text("RUN", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  void _showInsertTpDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF00E5FF), width: 1)),
        title: const Text("Insert Target Point", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: "Point Name", labelStyle: TextStyle(color: Colors.grey), border: OutlineInputBorder(), filled: true, fillColor: AppColors.bgMain),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                _sendCommand('SET_TP_NAME', nameCtrl.text); 
                _sendCommand('INSERT_TP');                 
                Navigator.pop(ctx);
              }
            },
            child: const Text("INSERT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showDeletePointConfirmDialog(int index, Map<String, dynamic> tp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentRed, width: 1)),
        title: const Text("Delete Point", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold)),
        content: Text("Name: ${tp['name']}\n\nDelete this point?", style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () {
              setState(() { if (index >= 0 && index < _tpList.length) _tpList.removeAt(index); });
              _sendCommand('DELETE_TP_INDEX', index); 
              Navigator.pop(ctx);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  void _showModifyTpDialog(int index, Map<String, dynamic> tp) {
    final nameCtrl = TextEditingController(text: tp['name']);
    String rawVal = tp['value'] ?? "";
    String x = "0.0", y = "0.0", z = "0.0";
    
    final regex = RegExp(r"([xyz]):(-?\d+\.\d+)");
    final matches = regex.allMatches(rawVal);
    for (var m in matches) {
      if (m.group(1) == 'x') x = m.group(2)!;
      if (m.group(1) == 'y') y = m.group(2)!;
      if (m.group(1) == 'z') z = m.group(2)!;
    }

    final xCtrl = TextEditingController(text: x);
    final yCtrl = TextEditingController(text: y);
    final zCtrl = TextEditingController(text: z);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentBlue, width: 1)),
        title: const Text("Modify Point", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Point Name")),
              const SizedBox(height: 10),
              TextField(controller: xCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "X Value (mm)", filled: true, fillColor: AppColors.bgMain)),
              const SizedBox(height: 10),
              TextField(controller: yCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Y Value (mm)", filled: true, fillColor: AppColors.bgMain)),
              const SizedBox(height: 10),
              TextField(controller: zCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Z Value (mm)", filled: true, fillColor: AppColors.bgMain)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue),
            onPressed: () {
              _sendCommand('SELECT_TP_INDEX', index);
              _sendModifyCommand(nameCtrl.text, xCtrl.text, yCtrl.text, zCtrl.text);
              setState(() {
                if (index >= 0 && index < _tpList.length) {
                  var modifiedItem = _tpList.removeAt(index);
                  modifiedItem['name'] = nameCtrl.text;
                  modifiedItem['value'] = "x:${xCtrl.text} y:${yCtrl.text} z:${zCtrl.text}";
                  _tpList.add(modifiedItem); 
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text("CONFIRM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  // --- POPUPS ---
  void _showErrorPopup(String errorText) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentRed, width: 2)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.accentRed, size: 28),
            SizedBox(width: 10),
            Text("SYSTEM ERROR", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(errorText, style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () { _sendCommand('CLEAR_ERRORS'); Navigator.of(ctx).pop(); },
            child: const Text("CLEAR", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("DISMISS", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showConnectionRejectedPopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.accentYellow, width: 2)),
        title: const Row(
          children: [
            Icon(Icons.lock_person, color: AppColors.accentYellow, size: 28),
            SizedBox(width: 10),
            Text("ACCESS DENIED", style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text("Another client is already connected to the server.", style: TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("DISMISS", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // --- MAIN BUILD ---
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentView == "MAIN",
      onPopInvoked: (didPop) {
        if (!didPop) _goBackToMain();
      },
      child: Scaffold(
        appBar: _currentView == "MAIN"
            ? AppBar(
                title: const Text("Texsonics Controller", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 17)),
                actions: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: _wsStatusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: _wsStatusColor)),
                    alignment: Alignment.center,
                    child: Text(_wsStatus, style: TextStyle(color: _wsStatusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            : null,
        drawer: _currentView == "MAIN" ? _buildDrawer() : null,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildCurrentView(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case "SPEED": return _buildSpeedView();
      case "CARTESIAN": return _buildCartesianView();
      case "JOINTS": return _buildJointsView();
      case "MAIN": default: return _buildMainView();
    }
  }

  // --- 1. DRAWER (HAMBURGER MENU) ---
  Widget _buildDrawer() {
    bool isConnected = _wsStatus == "CONNECTED";
    return Drawer(
      backgroundColor: AppColors.bgMain,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 20, right: 20),
            color: AppColors.bgPanel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("CONNECTION", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(
                  controller: _ipController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0), border: OutlineInputBorder(), filled: true, fillColor: Color(0xFF0A0A12)),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _buildColorButton(
                    isConnected ? "DISCONNECT" : "CONNECT",
                    isConnected ? AppColors.accentRed : AppColors.accentGreen,
                    isConnected ? _disconnect : _connect,
                    padding: 0,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text("SYSTEM MODES", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildColorButton("SIM", AppColors.accentPurple, () => _sendCommand('SET_SIM'), isActive: _mode == 'Sim', padding: 0)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildColorButton("REAL", AppColors.accentRed, () => _sendCommand('SET_REAL'), isActive: _mode == 'Real', padding: 0)),
                  ],
                ),
                const SizedBox(height: 25),
                const Text("UTILITIES", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 10),
                _buildGenericButton("CLEAR ERRORS", () => _sendCommand('CLEAR_ERRORS')),
                const SizedBox(height: 10),
                _buildGenericButton("CLEAR MARKS", () => _sendCommand('CLEAR_MARKS')),
                const SizedBox(height: 10),
                _buildColorButton("EXIT SYSTEM", AppColors.accentRed, () => _sendCommand('EXIT'), padding: 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. MAIN PORTRAIT VIEW ---
  Widget _buildMainView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.bgPanel, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem("SERVO", _servoOn ? "ON" : "OFF", _servoOn ? AppColors.accentGreen : AppColors.accentRed),
                _buildStatusItem("MODE", _mode, _mode == "Real" ? AppColors.accentRed : AppColors.accentYellow),
                _buildStatusItem("OP SPEED", "${_currentSpeedOp.toStringAsFixed(1)}%", AppColors.accentBlue),
                GestureDetector(onTap: () { if (_errorMsg != "No error") _showErrorPopup(_errorMsg); }, child: _buildStatusItem("ERR", _errorMsg == "No error" ? "OK" : "ERR", _errorMsg == "No error" ? AppColors.accentGreen : AppColors.accentRed)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildColorButton("SERVO TOGGLE", AppColors.accentYellow, () => _sendCommand('TOGGLE_SERVO'), padding: 0)),
              const SizedBox(width: 10),
              Expanded(child: _buildColorButton("🏠 HOME", AppColors.accentPurple, () => _sendCommand('TRIGGER_HOME'), padding: 0)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildColorButton(_isStarted ? "STOP" : "START", _isStarted ? AppColors.accentRed : AppColors.accentGreen, () => _sendCommand('TOGGLE_START'), padding: 0)),
              const SizedBox(width: 10),
              Expanded(child: _buildColorButton(_isPaused ? "PAUSE" : "RUN", AppColors.accentYellow, () => _sendCommand('TOGGLE_PAUSE'), isActive: _isPaused, padding: 0)),
            ],
          ),

          // ==========================================
          // --- NEW: TP FILE MANAGEMENT SECTION ---
          // ==========================================
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TP FILE MANAGEMENT", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.lcdBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border)
                ),
                child: Text("ACTIVE: $_currentTpName", style: const TextStyle(color: AppColors.accentBlue, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            children: [
              Expanded(
                child: _buildColorButton(
                  "+ NEW",
                  AppColors.accentBlue, 
                  _showNewTpFileDialog,
                  padding: 0,
                  fontSize: 12
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildColorButton(
                  "📂 OPEN",
                  AppColors.accentYellow, 
                  () {
                    _sendCommand('REFRESH_TP_FILES');
                    Future.delayed(const Duration(milliseconds: 200), () => _showTpFileListSheet("Open"));
                  },
                  padding: 0,
                  fontSize: 12
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildColorButton(
                  "🗑 DELETE",
                  AppColors.accentRed, 
                  () {
                    _sendCommand('REFRESH_TP_FILES');
                    Future.delayed(const Duration(milliseconds: 200), () => _showTpFileListSheet("Delete"));
                  },
                  padding: 0,
                  fontSize: 12
                ),
              ),
            ],
          ),

          // ==========================================
          // --- EXISTING: TP POINT CONTROLS ---
          // ==========================================
          const SizedBox(height: 20),
          const Text("TP POINT OPERATIONS", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          
          // ROW 1: Mode & Run
          Row(
            children: [
              Expanded(
                child: _buildColorButton(
                  "⚙ $_tpRunMode",
                  AppColors.accentBlue, 
                  _showTpModeDialog,
                  padding: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildColorButton(
                  "▶ RUN TP",
                  AppColors.accentGreen, 
                  () => _showTpSelectionSheet("Run", _showRunConfirmDialog),
                  padding: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ROW 2: Insert, Modify, Delete (Points)
          Row(
            children: [
              Expanded(
                child: _buildColorButton(
                  "+ INSERT",
                  const Color(0xFF00E5FF), // Cyan
                  _showInsertTpDialog,
                  padding: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildColorButton(
                  "✎ MODIFY",
                  AppColors.accentBlue, 
                  () => _showTpSelectionSheet("Modify", _showModifyTpDialog),
                  padding: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildColorButton(
                  "- DELETE",
                  const Color(0xFFFF3D00), // Red-Orange
                  () => _showTpSelectionSheet("Delete", _showDeletePointConfirmDialog),
                  padding: 0,
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),
          const Divider(color: AppColors.border, height: 40, thickness: 1),

          const Center(child: Text("SELECT MOTION TYPE", style: TextStyle(color: AppColors.accentBlue, letterSpacing: 1.5, fontWeight: FontWeight.bold))),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _buildColorButton("JOG (Hold)", AppColors.accentGreen, () => setState(() => _motionType = "JOG"), isActive: _motionType == "JOG")),
              const SizedBox(width: 10),
              Expanded(child: _buildColorButton("MOVE (Click)", AppColors.accentBlue, () => setState(() => _motionType = "MOVE"), isActive: _motionType == "MOVE")),
            ],
          ),
          
          // --- NAVIGATION CARDS ---
          const SizedBox(height: 25),
          GestureDetector(onTap: _openSpeed, child: _buildNavCard("SPEED SETTINGS", Icons.speed, "Configure Speeds & Increments")),
          const SizedBox(height: 15),
          GestureDetector(onTap: _openCartesian, child: _buildNavCard("CARTESIAN PAD", Icons.screen_rotation, "Opens in Landscape")),
          const SizedBox(height: 15),
          GestureDetector(onTap: _openJoints, child: _buildNavCard("JOINTS PAD", Icons.precision_manufacturing, "Opens in Portrait")),
        ],
      ),
    );
  }

  // --- 2.5. SPEED & CONFIGURATION PORTRAIT VIEW ---
  Widget _buildSpeedView() {
    return Column(
      children: [
        AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBackToMain),
          title: const Text("SPEED & CONFIGURATION", style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgPanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Global Speed (%)
                  Row(
                    children: [
                      const Expanded(flex: 2, child: Text("Global (%)", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
                      Expanded(
                        flex: 4,
                        child: Slider(
                          value: _globalSpeed, min: 1, max: 100, activeColor: AppColors.accentBlue,
                          onChanged: (val) => setState(() => _globalSpeed = val),
                          onChangeEnd: (val) => _sendCommand('SET_GLOBAL_SPEED', val.toInt()),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text("${_globalSpeed.toInt()}%", style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: AppColors.border, thickness: 1),
                  const SizedBox(height: 10),

                  // Individual vertical config rows
                  _buildConfigDropdown("Lin Inc (mm)", _selectedMmInc, _mmOptions, (val) {
                    setState(() => _selectedMmInc = val);
                    if (val != "mm") _sendCommand('SET_MM_INC', val);
                  }),
                  
                  _buildConfigInput("Lin Speed (mm/s)", _mmSpeedCtrl, "SET_MM_SPEED"),
                  
                  _buildConfigDropdown("Ang Inc (deg)", _selectedDegInc, _degOptions, (val) {
                    setState(() => _selectedDegInc = val);
                    if (val != "deg") _sendCommand('SET_DEG_INC', val);
                  }),
                  
                  _buildConfigInput("Ang Speed (deg/s)", _degSpeedCtrl, "SET_DEG_SPEED"),
                  
                  _buildConfigDropdown("Ref Frame", _frame, ["Base", "Tool", "User"], (val) {
                    setState(() => _frame = val);
                    _sendCommand('SET_FRAME', val);
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigDropdown(String label, String value, List<String> items, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Expanded(
            flex: 5,
            child: Container(
              height: 40, padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: const Color(0xFF0A0A12), border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(6)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value, dropdownColor: AppColors.bgPanel, isDense: true, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                  items: items.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                  onChanged: (val) { if (val != null) onChanged(val); },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInput(String label, TextEditingController ctrl, String cmd) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: ctrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
                  filled: true, fillColor: Color(0xFF0A0A12)
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40, width: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.btnBg, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
              onPressed: () => _sendCommand(cmd, ctrl.text),
              child: const Icon(Icons.check, size: 20, color: AppColors.accentBlue)
            )
          )
        ],
      ),
    );
  }

  // --- 3. CARTESIAN LANDSCAPE VIEW ---
  Widget _buildCartesianView() {
    return Container(
      color: AppColors.bgMain,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopHud(),
            Expanded(
              child: Stack(
                children: [
                  Positioned(top: 10, left: 10, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24), onPressed: _goBackToMain)),
                  Positioned(
                    top: 15, right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4), border: Border.all(color: _motionType == "JOG" ? AppColors.accentGreen : AppColors.accentBlue)),
                      child: Text("$_motionType MODE", style: TextStyle(color: _motionType == "JOG" ? AppColors.accentGreen : AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildDPadCluster("Y+", "Y-", "X-", "X+", "Z+", "Z-", "XYZ MOVE"),
                        _buildDPadCluster("Rx+", "Rx-", "Ry+", "Ry-", "Rz+", "Rz-", "ROTATION"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHud() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(color: AppColors.bgPanel, border: Border(bottom: BorderSide(color: AppColors.border)), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("FRAME", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(_frame.toUpperCase(), style: const TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          Container(width: 1, height: 30, color: AppColors.border), 
          _buildCompactValueGroup(["X", "Y", "Z"], [_cartesian['x']!, _cartesian['y']!, _cartesian['z']!], "mm"),
          Container(width: 1, height: 30, color: AppColors.border), 
          _buildCompactValueGroup(["Rx", "Ry", "Rz"], [_cartesian['rx']!, _cartesian['ry']!, _cartesian['rz']!], "deg"),
        ],
      ),
    );
  }

  Widget _buildCompactValueGroup(List<String> labels, List<double> values, String unit) {
    return Row(
      children: List.generate(labels.length, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Text("${labels[index]}: ", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
              _buildLiveValueBox(values[index].toStringAsFixed(2), unit, fontSize: 13),
            ],
          ),
        );
      }),
    );
  }

  // --- 4. JOINTS PORTRAIT VIEW ---
  Widget _buildJointsView() {
    return Column(
      children: [
        AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBackToMain),
          title: Text("JOINTS - $_motionType", style: TextStyle(color: _motionType == "JOG" ? AppColors.accentGreen : AppColors.accentBlue)),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(children: [for (int i = 1; i <= 6; i++) _buildJointRow(i), const SizedBox(height: 30)]),
          ),
        ),
      ],
    );
  }

  Widget _buildJointRow(int jointNum) {
    double val = _joints['j$jointNum'] ?? 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.bgPanel, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildJogButton("J$jointNum-", width: 60, height: 50),
            Expanded(
              child: Column(
                children: [
                  Text("JOINT $jointNum", style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.lcdBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
                    child: Text("${val.toStringAsFixed(2)}°", style: const TextStyle(fontFamily: 'monospace', color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ],
              ),
            ),
            _buildJogButton("J$jointNum+", width: 60, height: 50),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _buildLiveValueBox(String value, String unit, {double fontSize = 14}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.lcdBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontFamily: 'monospace', color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: fontSize)),
          const SizedBox(width: 4),
          Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildNavCard(String title, IconData icon, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.bgPanel, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]),
      child: Row(
        children: [
          Icon(icon, size: 40, color: AppColors.accentBlue),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildDPadCluster(String up, String down, String left, String right, String zUp, String zDown, String title) {
    double btnSize = 55;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildJogButton(up, width: btnSize, height: btnSize),
                Row(mainAxisSize: MainAxisSize.min, children: [_buildJogButton(left, width: btnSize, height: btnSize), SizedBox(width: btnSize), _buildJogButton(right, width: btnSize, height: btnSize)]),
                _buildJogButton(down, width: btnSize, height: btnSize),
              ],
            ),
            const SizedBox(width: 20), 
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.bgPanel.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border.withOpacity(0.5))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [_buildJogButton(zUp, width: btnSize, height: 65), const SizedBox(height: 8), _buildJogButton(zDown, width: btnSize, height: 65)]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJogButton(String label, {double? width, double height = 50}) {
    Color getTextColor(String lbl) {
      if (lbl.contains('+')) return AppColors.accentGreen;
      if (lbl.contains('-')) return AppColors.accentRed;
      return Colors.black87;
    }
    return GestureDetector(
      onTapDown: (_) => _onPadInteract(label, true),
      onTapUp: (_) => _onPadInteract(label, false),
      onTapCancel: () => _onPadInteract(label, false),
      child: Container(
        width: width, height: height, margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border, width: 1.5), boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 4), blurRadius: 4)]),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: getTextColor(label))),
      ),
    );
  }

  Widget _buildStatusItem(String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.bgMain, borderRadius: BorderRadius.circular(4)),
          child: Text(val, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ),
      ],
    );
  }

  Widget _buildColorButton(String text, Color color, VoidCallback onPressed, {bool isActive = false, double padding = 18, double fontSize = 14}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color : (text == "STOP" || text == "EXIT SYSTEM" || text == "DISCONNECT" ? AppColors.accentRed : AppColors.btnBg),
        foregroundColor: isActive || text == "STOP" ? Colors.black : Colors.white,
        side: BorderSide(color: isActive ? Colors.white : color, width: isActive ? 2 : 1),
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: isActive ? 10 : 2,
      ),
      onPressed: onPressed,
      child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize), textAlign: TextAlign.center),
    );
  }

  Widget _buildGenericButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.btnBg, foregroundColor: Colors.white, side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}