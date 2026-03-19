import 'dart:async';
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

// --- APP STATES ---
enum AppState { disconnected, connecting, waitingForServer, connected }

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  // --- LOGIN & CONNECTION STATE ---
  AppState _appState = AppState.disconnected;
  String _loginStatusMsg = "";
  Color _loginStatusColor = Colors.transparent;
  bool _isKickedOrRejected = false;

  final TextEditingController _ipController = TextEditingController(
    text: "192.168.1.51",
  );
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  String _selectedRole = "Operator"; // Default role

  WebSocketChannel? _channel;
  String _activeRole = ""; // Stores the role approved by the server

  // --- ROBOT STATE VARIABLES ---
  final TextEditingController _mmSpeedCtrl = TextEditingController(
    text: "50.0",
  );
  final TextEditingController _degSpeedCtrl = TextEditingController(
    text: "50.0",
  );

  String _selectedMmInc = "mm";
  String _selectedDegInc = "deg";
  String _opMode = "MANUAL";
  final List<String> _mmOptions = [
    "mm",
    "50",
    "25",
    "15",
    "10",
    "5",
    "2",
    "1",
    "0.1",
    "0.01",
    "0.001",
  ];
  final List<String> _degOptions = [
    "deg",
    "20",
    "15",
    "10",
    "5",
    "2",
    "1",
    "0.1",
    "0.01",
    "0.001",
    "0.0001",
  ];

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
  bool _isRotationMode = false;

  // File Tracking State
  String _currentTpName = "None";
  List<String> _tpFileList = [];
  String _currentPrName = "None";
  List<String> _prFileList = [];

  // Trajectory & Highlights
  bool _isCalculatingTrajectory = false;
  int _highlightedInstruction = -1;
  String _currentInstructionString = "";

  // Live Data
  Map<String, double> _cartesian = {
    'x': 0.0,
    'y': 0.0,
    'z': 0.0,
    'rx': 0.0,
    'ry': 0.0,
    'rz': 0.0,
  };
  Map<String, double> _joints = {
    'j1': 0.0,
    'j2': 0.0,
    'j3': 0.0,
    'j4': 0.0,
    'j5': 0.0,
    'j6': 0.0,
  };
  List<Map<String, dynamic>> _tpList = [];
  List<Map<String, dynamic>> _prProgramData = []; // <-- ADD THIS LINE
  String _currentView = "MAIN";

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _channel?.sink.close();
    _ipController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  // =========================================================================
  // VIEW SWITCHING LOGIC
  // =========================================================================
  void _openSpeed() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _currentView = "SPEED");
  }

  void _openTpManagement() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _currentView = "TP_MANAGEMENT");
  }

  void _openPrgManagement() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() => _currentView = "PRG_MANAGEMENT");
  }

  void _openCartesian() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
  // WEBSOCKET LOGIC
  // =========================================================================

  void _initiateLogin() {
    if (_ipController.text.isEmpty ||
        _userController.text.isEmpty ||
        _passController.text.isEmpty) {
      setState(() {
        _loginStatusMsg = "Please fill in all fields.";
        _loginStatusColor = AppColors.accentRed;
      });
      return;
    }

    setState(() {
      _appState = AppState.connecting;
      _loginStatusMsg = "Connecting to Robot Server...";
      _loginStatusColor = AppColors.accentYellow;
    });

    try {
      final wsUrl = Uri.parse("ws://${_ipController.text}:8080");
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        _handleMessage,
        onDone: () => _handleDisconnect("Connection closed by server."),
        onError: (error) => _handleDisconnect("Failed to connect to server."),
      );

      // Instantly send the REMOTE_AUTH command required by your C++ backend
      final authMsg = jsonEncode({
        "command": "REMOTE_AUTH",
        "username": _userController.text.trim(),
        "password": _passController.text.trim(),
        "role": _selectedRole,
      });
      _channel!.sink.add(authMsg);
    } catch (e) {
      _handleDisconnect("Invalid IP address format.");
    }
  }

  void _handleDisconnect(String reason) {
    _channel?.sink.close();
    setState(() {
      _appState = AppState.disconnected;

      // Prevent the generic socket 'onDone' event from overwriting our specific error messages!
      if (!_isKickedOrRejected || reason != "Connection closed by server.") {
        _loginStatusMsg = reason;
      }

      _loginStatusColor = AppColors.accentRed;
      _currentView = "MAIN"; // Reset view on disconnect

      // Reset the flag after the disconnect is fully processed
      if (reason == "Connection closed by server.") {
        _isKickedOrRejected = false;
      }
    });
  }

  void _userLogout() {
    _handleDisconnect("Disconnected successfully.");
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final String type = data['type'] ?? "";

      // 1. PRE-AUTH RESPONSES
      if (type == 'auth_rejected' ||
          type == 'connection_rejected' ||
          type == 'force_disconnect') {
        _isKickedOrRejected = true; // Tell Flutter NOT to overwrite this message
        String msg = data['message'] ?? "Connection denied.";

        // --- NEW: Advanced User-in-Use parsing ---
        if (type == 'connection_rejected' && data.containsKey('active_user')) {
          String actUser = data['active_user'];
          String actRole = data['active_role'];
          msg = "Access Denied: The server is currently in use by another client ($actRole: $actUser).";
        }
        // Translate the generic C++ backend messages into the requested professional format
        else if (msg.contains("Server is busy")) {
          msg = "Another client is already connected to the server.";
        } else if (msg.contains("Access Denied")) {
          msg = msg.replaceAll(
            "Access Denied: The machine is in ",
            "Connection rejected: The server is currently operating in ",
          );
          msg = msg.replaceAll(
            " mode, but you tried to connect as ",
            " mode. You cannot connect as ",
          );
        } else if (msg.contains("Admin login is strictly prohibited")) {
          msg = "Access restricted: Remote Admin operations are prohibited.";
        } else if (type == 'force_disconnect') {
          msg = "Session Terminated: You have been disconnected by the server admin.";
        }

        _handleDisconnect(msg);
      } else if (type == 'auth_success') {
        setState(() {
          _appState = AppState.waitingForServer;
          _loginStatusMsg = "Waiting for Physical Operator to Accept...";
          _loginStatusColor = AppColors.accentBlue;
        });
      } else if (type == 'connection_accepted') {
        setState(() {
          _appState = AppState.connected;
          _activeRole =
              data['role'] ?? _selectedRole; // Grab the confirmed role
          _loginStatusMsg = "";
        });
      }
      // 2. STANDARD STATUS UPDATES
      else if (type == 'status_update') {
        setState(() {
          _mode = data['mode'] ?? "Unknown";
          _servoOn = data['servo_on'] ?? false;
          _isStarted = data['started'] ?? false;
          _isPaused = data['paused'] ?? false;
          _tpRunMode = data['tp_run_mode'] ?? "TP Mode";
          _currentSpeedOp = (data['speed_op'] as num?)?.toDouble() ?? 0.0;

          _currentTpName = data['current_tp_name'] ?? "None";
          _currentPrName = data['current_pr_name'] ?? "None";
          _isCalculatingTrajectory = data['is_calculating_trajectory'] ?? false;
          _highlightedInstruction = data['highlighted_instruction'] ?? -1;

          if (data['staging_data'] != null) {
            _currentInstructionString =
                data['staging_data']['instruction'] ?? "";
          }

          if (data['tp_file_list'] != null) {
            _tpFileList = List<String>.from(data['tp_file_list']);
          }
          if (data['pr_file_list'] != null) {
            _prFileList = List<String>.from(data['pr_file_list']);
          }

          // Error handling
          String newError = data['error_message'] ?? "No error";
          if (newError != "No error" && newError != _lastErrorMsg) {
            _showErrorPopup("SYSTEM ERROR", newError);
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
          // <-- ADD THIS BLOCK BELOW -->
          if (data['pr_program_data'] != null) {
            _prProgramData = List<Map<String, dynamic>>.from(
              data['pr_program_data'],
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Parse error: $e");
    }
  }

  void _sendCommand(String cmd, [dynamic value = ""]) {
    if (_appState == AppState.connected && _channel != null) {
      final jsonMsg = jsonEncode({"command": cmd, "value": value.toString()});
      _channel!.sink.add(jsonMsg);
    }
  }

  void _sendModifyCommand(String name, String x, String y, String z) {
    if (_appState == AppState.connected && _channel != null) {
      final jsonMsg = jsonEncode({
        "command": "MODIFY_TP",
        "data": {"name": name, "x": x, "y": y, "z": z},
      });
      _channel!.sink.add(jsonMsg);
    }
  }

  void _onPadInteract(String axis, bool isDown) {
    if (_motionType == 'JOG') {
      if (isDown)
        _sendCommand('BTN_PRESS', axis);
      else
        _sendCommand('BTN_RELEASE', axis);
    } else if (_motionType == 'MOVE') {
      if (isDown) _sendCommand('BTN_CLICK', axis);
    }
  }

  void _showDisconnectConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.accentRed),
            SizedBox(width: 10),
            Text(
              "Disconnect?",
              style: TextStyle(
                color: AppColors.accentRed,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          "Are you sure you want to exit connection?",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _userLogout();
            },
            child: const Text(
              "CONFIRM",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- POPUPS ---
  void _showErrorPopup(String title, String contentText) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 2),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.accentRed,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.accentRed,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          contentText,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          if (title == "SYSTEM ERROR")
            TextButton(
              onPressed: () {
                _sendCommand('CLEAR_ERRORS');
                Navigator.of(ctx).pop();
              },
              child: const Text(
                "CLEAR",
                style: TextStyle(
                  color: AppColors.accentBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("DISMISS", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: AppColors.accentRed),
            SizedBox(width: 10),
            Text(
              "Confirm Exit?",
              style: TextStyle(
                color: AppColors.accentRed,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          "Are you sure you want to stop and exit the current program?",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () {
              _sendCommand('EXIT');
              Navigator.pop(ctx);
            },
            child: const Text(
              "EXIT",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BUILD: MAIN ROUTER
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    if (_appState != AppState.connected) {
      return Scaffold(body: SafeArea(child: _buildLoginScreen()));
    }

    return PopScope(
      canPop: _currentView == "MAIN",
      onPopInvoked: (didPop) {
        if (!didPop) {
          _goBackToMain();
        }
      },
      child: Scaffold(
        appBar: _currentView == "MAIN"
            ? AppBar(
                title: Text(
                  "Texsonics - $_activeRole",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    fontSize: 17,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout, color: AppColors.accentRed),
                    onPressed: _showDisconnectConfirmDialog,
                    tooltip: "Disconnect",
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
      case "SPEED":
        return _buildSpeedView();
      case "TP_MANAGEMENT":
        return _buildTpManagementView();
      // ADD THIS NEW CASE:
      case "PRG_MANAGEMENT":
        return _buildPrgManagementView();
      case "CARTESIAN":
        return _buildCartesianView();
      case "JOINTS":
        return _buildJointsView();
      case "MAIN":
      default:
        return _buildMainView();
    }
  }

  // =========================================================================
  // VIEW 0: LOGIN SCREEN
  // =========================================================================
  Widget _buildLoginScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: AppColors.bgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.precision_manufacturing,
                size: 60,
                color: AppColors.accentBlue,
              ),
              const SizedBox(height: 10),
              const Text(
                "TEXSONICS",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.accentBlue,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                "REMOTE AUTHENTICATION",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSec,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 30),

              _buildLoginTextField(
                "Server IP",
                Icons.wifi,
                _ipController,
                false,
              ),
              const SizedBox(height: 15),

              _buildLoginTextField(
                "Username",
                Icons.person,
                _userController,
                false,
              ),
              const SizedBox(height: 15),

              _buildLoginTextField(
                "Password",
                Icons.lock,
                _passController,
                true,
              ),
              const SizedBox(height: 25),

              const Text(
                "SELECT ROLE",
                style: TextStyle(
                  color: AppColors.textSec,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _appState == AppState.disconnected
                          ? () => setState(() => _selectedRole = "Operator")
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedRole == "Operator"
                              ? AppColors.accentBlue
                              : AppColors.lcdBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _selectedRole == "Operator"
                                ? AppColors.accentBlue
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Operator",
                          style: TextStyle(
                            color: _selectedRole == "Operator"
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _appState == AppState.disconnected
                          ? () => setState(() => _selectedRole = "Programmer")
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedRole == "Programmer"
                              ? AppColors.accentBlue
                              : AppColors.lcdBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _selectedRole == "Programmer"
                                ? AppColors.accentBlue
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Programmer",
                          style: TextStyle(
                            color: _selectedRole == "Programmer"
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- PROFESSIONAL ERROR/STATUS MESSAGE BOX ---
              if (_loginStatusMsg.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _loginStatusColor.withOpacity(0.1),
                    border: Border.all(color: _loginStatusColor, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _appState == AppState.disconnected
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline,
                        color: _loginStatusColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _loginStatusMsg,
                          style: TextStyle(
                            color: _loginStatusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_appState == AppState.disconnected)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _initiateLogin,
                  child: const Text(
                    "CONNECT & LOGIN",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ),

              if (_appState == AppState.connecting ||
                  _appState == AppState.waitingForServer)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => _handleDisconnect("Connection cancelled."),
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTextField(
    String label,
    IconData icon,
    TextEditingController controller,
    bool obscure,
  ) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: _appState == AppState.disconnected,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSec),
        prefixIcon: Icon(icon, color: AppColors.textSec),
        filled: true,
        fillColor: AppColors.lcdBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.accentBlue),
        ),
      ),
    );
  }

  // --- DRAWER ---
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.bgMain,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(
              top: 50,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            color: AppColors.bgPanel,
            child: Column(
              children: [
                const Icon(
                  Icons.account_circle,
                  size: 60,
                  color: AppColors.accentBlue,
                ),
                const SizedBox(height: 10),
                Text(
                  _activeRole.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  "IP: ${_ipController.text}",
                  style: const TextStyle(
                    color: AppColors.textSec,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  "SYSTEM MODES",
                  style: TextStyle(
                    color: AppColors.accentBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildColorButton(
                        "SIM",
                        AppColors.accentPurple,
                        () => _sendCommand('SET_SIM'),
                        isActive: _mode == 'Sim',
                        padding: 0,
                        icon: Icons.biotech_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildColorButton(
                        "REAL",
                        AppColors.accentRed,
                        () => _sendCommand('SET_REAL'),
                        isActive: _mode == 'Real',
                        padding: 0,
                        icon: Icons.precision_manufacturing,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildColorButton(
                        "AUTO",
                        AppColors.accentBlue,
                        () {
                          setState(() => _opMode = "AUTO");
                          _sendCommand('SET_AUTO');
                        },
                        isActive:
                            _opMode == "AUTO", // Adds the visual highlight
                        padding: 0,
                        icon: Icons.autorenew,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildColorButton(
                        "MANUAL",
                        AppColors.accentYellow,
                        () {
                          setState(() => _opMode = "MANUAL");
                          _sendCommand('SET_MANUAL');
                        },
                        isActive:
                            _opMode == "MANUAL", // Adds the visual highlight
                        padding: 0,
                        icon: Icons.pan_tool,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                const Text(
                  "UTILITIES",
                  style: TextStyle(
                    color: AppColors.accentBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                _buildGenericButton(
                  "CLEAR ERRORS",
                  () => _sendCommand('CLEAR_ERRORS'),
                ),
                const SizedBox(height: 10),
                _buildGenericButton(
                  "CLEAR MARKS",
                  () => _sendCommand('CLEAR_MARKS'),
                ),
                const SizedBox(height: 10),
                _buildColorButton(
                  "EXIT PRG",
                  AppColors.accentRed,
                  _showExitConfirmDialog,
                  padding: 0,
                  icon: Icons.exit_to_app,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- DASHBOARD (MAIN VIEW) ---
  Widget _buildMainView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. TOP HUD (ALWAYS VISIBLE)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem(
                  "SERVO",
                  _servoOn ? "ON" : "OFF",
                  _servoOn ? AppColors.accentGreen : AppColors.accentRed,
                ),
                _buildStatusItem(
                  "MODE",
                  _mode,
                  _mode == "Real"
                      ? AppColors.accentRed
                      : AppColors.accentYellow,
                ),
                _buildStatusItem(
                  "OP SPEED",
                  "${_currentSpeedOp.toStringAsFixed(1)}%",
                  AppColors.accentBlue,
                ),
                GestureDetector(
                  onTap: () {
                    if (_errorMsg != "No error")
                      _showErrorPopup("SYSTEM ERROR", _errorMsg);
                  },
                  child: _buildStatusItem(
                    "ERR",
                    _errorMsg == "No error" ? "OK" : "ERR",
                    _errorMsg == "No error"
                        ? AppColors.accentGreen
                        : AppColors.accentRed,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. PRIMARY CONTROLS (ALWAYS VISIBLE TO BOTH ROLES)
          Row(
            children: [
              Expanded(
                child: _buildColorButton(
                  "SERVO",
                  AppColors.accentYellow,
                  () => _sendCommand('TOGGLE_SERVO'),
                  padding: 0,
                  icon: Icons.power_settings_new,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildColorButton(
                  "HOME",
                  AppColors.accentPurple,
                  () => _sendCommand('TRIGGER_HOME'),
                  padding: 0,
                  icon: Icons.home,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildColorButton(
                  _isStarted ? "STOP" : "START",
                  _isStarted ? AppColors.accentRed : AppColors.accentGreen,
                  () => _sendCommand('TOGGLE_START'),
                  padding: 0,
                  icon: _isStarted ? Icons.stop_circle : Icons.play_circle_fill,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildColorButton(
                  _isPaused ? "PAUSE" : "RUN",
                  AppColors.accentYellow,
                  () => _sendCommand('TOGGLE_PAUSE'),
                  isActive: _isPaused,
                  padding: 0,
                  icon: _isPaused ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),
          const Divider(color: AppColors.border, thickness: 1),
          const SizedBox(height: 15),

          // --- SHARED MOTION TYPE SELECTION (NOW VISIBLE TO BOTH ROLES) ---
          const Center(
            child: Text(
              "SELECT MOTION TYPE",
              style: TextStyle(
                color: AppColors.accentBlue,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _buildColorButton(
                  "JOG (Hold)",
                  AppColors.accentGreen,
                  () => setState(() => _motionType = "JOG"),
                  isActive: _motionType == "JOG",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildColorButton(
                  "MOVE (Click)",
                  AppColors.accentBlue,
                  () => setState(() => _motionType = "MOVE"),
                  isActive: _motionType == "MOVE",
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Divider(color: AppColors.border, thickness: 1),
          const SizedBox(height: 20),

          // 3. ROLE-BASED RENDERING (NAVIGATION CARDS IN CUSTOM ORDER)
          if (_activeRole == "Programmer") ...[
            // --- PROGRAMMER VIEW ---
            GestureDetector(
              onTap: _openSpeed,
              child: _buildNavCard(
                "SPEED SETTINGS",
                Icons.speed,
                "Configure Speeds & Increments",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openTpManagement,
              child: _buildNavCard(
                "TP MANAGEMENT",
                Icons.folder_special,
                "Manage Files & Points",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openPrgManagement,
              child: _buildNavCard(
                "PRG MANAGEMENT",
                Icons.play_circle_fill,
                "Manage, Calculate & Run Programs",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openJoints,
              child: _buildNavCard(
                "JOINTS PAD",
                Icons.precision_manufacturing,
                "Opens in Portrait",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openCartesian,
              child: _buildNavCard(
                "CARTESIAN PAD",
                Icons.screen_rotation,
                "Opens in Landscape",
              ),
            ),
          ] else ...[
            // --- OPERATOR VIEW ---
            const Center(
              child: Text(
                "OPERATOR DASHBOARD",
                style: TextStyle(
                  color: AppColors.accentPurple,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 15),

            // Operator Navigation Cards (NO TP MANAGEMENT)
            GestureDetector(
              onTap: _openSpeed,
              child: _buildNavCard(
                "SPEED SETTINGS",
                Icons.speed,
                "Configure Speeds & Increments",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openPrgManagement,
              child: _buildNavCard(
                "PRG MANAGEMENT",
                Icons.play_circle_fill,
                "Manage, Calculate & Run Programs",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openJoints,
              child: _buildNavCard(
                "JOINTS PAD",
                Icons.precision_manufacturing,
                "Opens in Portrait",
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: _openCartesian,
              child: _buildNavCard(
                "CARTESIAN PAD",
                Icons.screen_rotation,
                "Opens in Landscape",
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPrFileListSheet(String actionTitle) {
    IconData actionIcon = actionTitle == "Open"
        ? Icons.folder_open
        : Icons.delete_forever;
    Color actionColor = actionTitle == "Open"
        ? AppColors.accentYellow
        : AppColors.accentRed;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "$actionTitle PRG File",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: actionColor,
              ),
            ),
            const Divider(color: AppColors.border, height: 30),
            Expanded(
              child: _prFileList.isEmpty
                  ? const Center(
                      child: Text(
                        "No files available.",
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _prFileList.length,
                      itemBuilder: (ctx, i) {
                        final fileData = _prFileList[i].split('|');
                        final fileName = fileData[0];
                        final fileDate = fileData.length > 1 ? fileData[1] : "";

                        return ListTile(
                          leading: const Icon(
                            Icons.insert_drive_file,
                            color: AppColors.accentPurple,
                          ),
                          title: Text(
                            fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            fileDate,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            actionIcon,
                            color: actionColor,
                            size: 20,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (actionTitle == "Open") {
                              _sendCommand('OPEN_PR_FILE', fileName);
                            } else {
                              _showDeletePrFileConfirmDialog(fileName);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // REMAINDER OF UI BUILDERS (Speed, Cartesian, Joints, TP Mgmt)
  // =========================================================================

  Widget _buildSpeedView() {
    return Column(
      children: [
        AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToMain,
          ),
          title: const Text(
            "SPEED & CONFIGURATION",
            style: TextStyle(
              color: AppColors.accentBlue,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.bgPanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "GLOBAL SYSTEM SPEED",
                    style: TextStyle(
                      color: AppColors.accentBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        flex: 2,
                        child: Text(
                          "Limit (%)",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Slider(
                          value: _globalSpeed,
                          min: 1,
                          max: 100,
                          activeColor: AppColors.accentBlue,
                          onChanged: (val) =>
                              setState(() => _globalSpeed = val),
                          onChangeEnd: (val) =>
                              _sendCommand('SET_GLOBAL_SPEED', val.toInt()),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          "${_globalSpeed.toInt()}%",
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border, thickness: 1),
                  const SizedBox(height: 20),
                  _buildConfigDropdown(
                    "Lin Inc (mm)",
                    _selectedMmInc,
                    _mmOptions,
                    (val) {
                      setState(() => _selectedMmInc = val);
                      if (val != "mm") _sendCommand('SET_MM_INC', val);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildConfigInput(
                    "Lin Speed (mm/s)",
                    _mmSpeedCtrl,
                    "SET_MM_SPEED",
                  ),
                  const SizedBox(height: 20),
                  const Divider(
                    color: AppColors.border,
                    thickness: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
                  const SizedBox(height: 20),
                  _buildConfigDropdown(
                    "Ang Inc (deg)",
                    _selectedDegInc,
                    _degOptions,
                    (val) {
                      setState(() => _selectedDegInc = val);
                      if (val != "deg") _sendCommand('SET_DEG_INC', val);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildConfigInput(
                    "Ang Speed (deg/s)",
                    _degSpeedCtrl,
                    "SET_DEG_SPEED",
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border, thickness: 1),
                  const SizedBox(height: 20),
                  _buildConfigDropdown(
                    "Ref Frame",
                    _frame,
                    ["Base", "Tool", "User"],
                    (val) {
                      setState(() => _frame = val);
                      _sendCommand('SET_FRAME', val);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTpManagementView() {
    return Column(
      children: [
        AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToMain,
          ),
          title: const Text(
            "TP FILE MANAGEMENT",
            style: TextStyle(
              color: AppColors.accentBlue,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "ACTIVE FILE",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lcdBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _currentTpName,
                        style: const TextStyle(
                          color: AppColors.accentBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildColorButton(
                        "NEW",
                        AppColors.accentBlue,
                        _showNewTpFileDialog,
                        padding: 0,
                        fontSize: 12,
                        icon: Icons.add,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildColorButton(
                        "OPEN",
                        AppColors.accentYellow,
                        () {
                          _sendCommand('REFRESH_TP_FILES');
                          Future.delayed(
                            const Duration(milliseconds: 200),
                            () => _showTpFileListSheet("Open"),
                          );
                        },
                        padding: 0,
                        fontSize: 12,
                        icon: Icons.folder_open,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildColorButton(
                        "DELETE",
                        AppColors.accentRed,
                        () {
                          _sendCommand('REFRESH_TP_FILES');
                          Future.delayed(
                            const Duration(milliseconds: 200),
                            () => _showTpFileListSheet("Delete"),
                          );
                        },
                        padding: 0,
                        fontSize: 12,
                        icon: Icons.delete,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Divider(color: AppColors.border, thickness: 1),
                const SizedBox(height: 20),
                const Text(
                  "TP POINT OPERATIONS",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildColorButton(
                        _tpRunMode,
                        AppColors.accentBlue,
                        _showTpModeDialog,
                        padding: 0,
                        icon: Icons.settings,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildColorButton(
                        "RUN TP",
                        AppColors.accentGreen,
                        () =>
                            _showTpSelectionSheet("Run", _showRunConfirmDialog),
                        padding: 0,
                        icon: Icons.play_arrow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildColorButton(
                        "INSERT",
                        const Color(0xFF00E5FF),
                        _showInsertTpDialog,
                        padding: 0,
                        fontSize: 12,
                        icon: Icons.add_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildColorButton(
                        "MODIFY",
                        AppColors.accentBlue,
                        () => _showTpSelectionSheet(
                          "Modify",
                          _showModifyTpDialog,
                        ),
                        padding: 0,
                        fontSize: 12,
                        icon: Icons.edit,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildColorButton(
                        "DELETE",
                        const Color(0xFFFF3D00),
                        () => _showTpSelectionSheet(
                          "Delete",
                          _showDeletePointConfirmDialog,
                        ),
                        padding: 0,
                        fontSize: 12,
                        icon: Icons.remove_circle_outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

 // =========================================================================
  // CARTESIAN VIEW (RESPONSIVE DYNAMIC D-PAD & VERTICAL TOGGLE)
  // =========================================================================
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
                  // --- LEFT: BACK BUTTON & MODE BADGE ---
                  Positioned(
                    top: 15,
                    left: 15,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                          onPressed: _goBackToMain,
                        ),
                        const SizedBox(height: 15),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _motionType == "JOG" ? AppColors.accentGreen : AppColors.accentBlue,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            "$_motionType MODE",
                            style: TextStyle(
                              color: _motionType == "JOG" ? AppColors.accentGreen : AppColors.accentBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- CENTER: RESPONSIVE DYNAMIC D-PAD ---
                  Center(
                    child: _buildSingleDPad(),
                  ),

                  // --- RIGHT: VERTICAL CARTESIAN / ROTATION TOGGLE ---
                  Positioned(
                    right: 15,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.bgPanel,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _isRotationMode = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: !_isRotationMode ? AppColors.accentBlue : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: RotatedBox(
                                  quarterTurns: 3, // Reads bottom to top
                                  child: Text(
                                    "CARTESIAN",
                                    style: TextStyle(
                                      color: !_isRotationMode ? Colors.black : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _isRotationMode = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _isRotationMode ? AppColors.accentBlue : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Text(
                                    "ROTATION",
                                    style: TextStyle(
                                      color: _isRotationMode ? Colors.black : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  // =========================================================================
  // VIEW: PRG MANAGEMENT (UPDATED WITH ROLE RESTRICTIONS)
  // =========================================================================
  Widget _buildPrgManagementView() {
    return Column(
      children: [
        AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToMain,
          ),
          title: const Text(
            "PROGRAM MANAGEMENT",
            style: TextStyle(
              color: AppColors.accentPurple,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgPanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- Active File Display ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "ACTIVE FILE",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.lcdBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          _currentPrName,
                          style: const TextStyle(
                            color: AppColors.accentPurple,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- PRG FILE MANAGEMENT (ROLE RESTRICTED) ---
                  Row(
                    children: [
                      // NEW Button (Programmer Only)
                      if (_activeRole == "Programmer") ...[
                        Expanded(
                          child: _buildColorButton(
                            "NEW",
                            AppColors.accentBlue,
                            _showNewPrFileDialog,
                            padding: 0,
                            fontSize: 12,
                            icon: Icons.add,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      // OPEN Button (Both Roles)
                      Expanded(
                        child: _buildColorButton(
                          "OPEN",
                          AppColors.accentYellow,
                          () {
                            _sendCommand('REFRESH_PR_FILES');
                            Future.delayed(
                              const Duration(milliseconds: 200),
                              () => _showPrFileListSheet("Open"),
                            );
                          },
                          padding: 0,
                          fontSize: 12,
                          icon: Icons.folder_open,
                        ),
                      ),

                      // DELETE FILE Button (Programmer Only)
                      if (_activeRole == "Programmer") ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildColorButton(
                            "DELETE",
                            AppColors.accentRed,
                            () {
                              _sendCommand('REFRESH_PR_FILES');
                              Future.delayed(
                                const Duration(milliseconds: 200),
                                () => _showPrFileListSheet("Delete"),
                              );
                            },
                            padding: 0,
                            fontSize: 12,
                            icon: Icons.delete,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Divider(color: AppColors.border, thickness: 1),
                  const SizedBox(height: 20),

                  // --- PRG EXECUTION (BOTH ROLES) ---
                  _buildColorButton(
                    _isCalculatingTrajectory
                        ? "CANCEL CALCULATION"
                        : "CALCULATE TRAJECTORY",
                    _isCalculatingTrajectory
                        ? AppColors.accentRed
                        : AppColors.accentBlue,
                    () {
                      if (_isCalculatingTrajectory) {
                        _sendCommand('CANCEL_CALCULATION');
                      } else {
                        _sendCommand('CALCULATE_TRAJECTORY');
                      }
                    },
                    isActive: _isCalculatingTrajectory,
                    icon: _isCalculatingTrajectory ? Icons.cancel : Icons.route,
                  ),

                  if (_isCalculatingTrajectory) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lcdBg,
                        border: Border.all(
                          color: AppColors.accentYellow,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: AppColors.accentYellow,
                              strokeWidth: 2.5,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "GENERATING TRAJECTORY DATA...",
                            style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),

                  // Run Program Button
                  _buildColorButton(
                    "RUN PROGRAM",
                    AppColors.accentGreen,
                    () =>
                        _showPrgSelectionSheet("Run", _showPrgRunConfirmDialog),
                    icon: Icons.play_arrow,
                  ),

                  // --- ROW DELETION (PROGRAMMER ONLY) ---
                  if (_activeRole == "Programmer") ...[
                    const SizedBox(height: 15),
                    _buildColorButton(
                      "DELETE INSTRUCTION",
                      const Color(0xFFFF3D00), // Distinct Red-Orange
                      () => _showPrgSelectionSheet(
                        "Delete",
                        _showDeletePrgRowConfirmDialog,
                      ),
                      icon: Icons.remove_circle_outline,
                    ),
                  ],

                  const SizedBox(height: 25),
                  const Divider(color: AppColors.border, thickness: 1),
                  const SizedBox(height: 15),

                  // --- CURRENT INSTRUCTION LIVE MONITOR ---
                  const Text(
                    "CURRENT INSTRUCTION",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (ctx) =>
                            LiveExecutionSheet(this, isPrgMode: true),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.lcdBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.accentPurple),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.btnBg,
                            radius: 14,
                            child: Text(
                              _highlightedInstruction >= 0
                                  ? "$_highlightedInstruction"
                                  : "-",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              _currentInstructionString.isNotEmpty
                                  ? _currentInstructionString
                                  : "Standing By...",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopHud() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "FRAME",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _frame.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.accentBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          _buildCompactValueGroup(
            ["X", "Y", "Z"],
            [_cartesian['x']!, _cartesian['y']!, _cartesian['z']!],
            "mm",
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          _buildCompactValueGroup(
            ["Rx", "Ry", "Rz"],
            [_cartesian['rx']!, _cartesian['ry']!, _cartesian['rz']!],
            "deg",
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // JOINTS VIEW (DYNAMIC ALIGNMENT WITH LISTVIEW)
  // =========================================================================
  Widget _buildJointsView() {
    return Column(
      children: [
        AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToMain,
          ),
          title: Text(
            "JOINTS - $_motionType",
            style: TextStyle(
              color: _motionType == "JOG" ? AppColors.accentGreen : AppColors.accentBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        // Used ListView.builder to ensure it handles smaller screen heights without overflow
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            itemCount: 6,
            itemBuilder: (context, index) => _buildJointRow(index + 1),
          ),
        ),
      ],
    );
  }

  // --- UPDATED JOINT ROW (Flexible constraints for all screen widths) ---
  Widget _buildJointRow(int jointNum) {
    double val = _joints['j$jointNum'] ?? 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Flexible allows the button to expand/contract safely
            Flexible(
              flex: 2,
              child: _buildJogButton("J$jointNum-", width: double.infinity, height: 60), 
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Text(
                      "JOINT $jointNum",
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.lcdBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        "${val.toStringAsFixed(2)}°",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: AppColors.accentBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16, // Scaled down slightly to fit smaller phones perfectly
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              flex: 2,
              child: _buildJogButton("J$jointNum+", width: double.infinity, height: 60),
            ),
          ],
        ),
      ),
    );
  }

  // --- COMPONENTS ---
  Widget _buildConfigDropdown(
    String label,
    String value,
    List<String> items,
    Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A12),
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  dropdownColor: AppColors.bgPanel,
                  isDense: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  items: items
                      .map(
                        (val) => DropdownMenuItem(value: val, child: Text(val)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) onChanged(val);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInput(
    String label,
    TextEditingController ctrl,
    String cmd,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: ctrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  filled: true,
                  fillColor: Color(0xFF0A0A12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            width: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.btnBg,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () => _sendCommand(cmd, ctrl.text),
              child: const Icon(
                Icons.check,
                size: 20,
                color: AppColors.accentBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactValueGroup(
    List<String> labels,
    List<double> values,
    String unit,
  ) {
    return Row(
      children: List.generate(labels.length, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Text(
                "${labels[index]}: ",
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              _buildLiveValueBox(
                values[index].toStringAsFixed(2),
                unit,
                fontSize: 13,
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLiveValueBox(String value, String unit, {double fontSize = 14}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.lcdBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              color: AppColors.accentBlue,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
          const SizedBox(width: 4),
          Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildNavCard(String title, IconData icon, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: AppColors.accentBlue),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

  // --- REPLACES _buildDPadCluster ---
  Widget _buildSingleDPad() {
    String up = _isRotationMode ? "Ry+" : "Y+";
    String down = _isRotationMode ? "Ry-" : "Y-";
    String left = _isRotationMode ? "Rx-" : "X-";
    String right = _isRotationMode ? "Rx+" : "X+";
    String zUp = _isRotationMode ? "Rz+" : "Z+";
    String zDown = _isRotationMode ? "Rz-" : "Z-";

    // Dynamic Sizing based on screen height to prevent overlap on any phone
    double screenHeight = MediaQuery.of(context).size.height;
    double btnSize = (screenHeight * 0.20).clamp(55.0, 85.0); // Adjusts beautifully to space
    double spacing = 12.0; // Increased spacing for cleaner industrial look

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Cross layout for X and Y with HOME in center
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildJogButton(up, width: btnSize, height: btnSize),
            SizedBox(height: spacing),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildJogButton(left, width: btnSize, height: btnSize),
                SizedBox(width: spacing),
                _buildJogButton("HOME", width: btnSize, height: btnSize, isCircle: true),
                SizedBox(width: spacing),
                _buildJogButton(right, width: btnSize, height: btnSize),
              ],
            ),
            SizedBox(height: spacing),
            _buildJogButton(down, width: btnSize, height: btnSize),
          ],
        ),
        SizedBox(width: btnSize * 0.8), // Dynamic spacing between XY and Z
        // Vertical layout for Z
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildJogButton(zUp, width: btnSize, height: btnSize),
            SizedBox(height: spacing * 2.5), // Distinctly separates Up/Down
            _buildJogButton(zDown, width: btnSize, height: btnSize),
          ],
        ),
      ],
    );
  }

 // --- UPDATED JOG BUTTON FACTORY ---
  Widget _buildJogButton(String label, {double width = 65, double height = 65, bool isCircle = false}) {
    Color btnColor;
    
    // Exact Professional Color Mapping
    if (label == 'HOME') {
      btnColor = AppColors.accentBlue; // Center Home is Blue
    } else if (label.startsWith('X') || label.startsWith('Rx')) {
      btnColor = AppColors.accentRed;
    } else if (label.startsWith('Y') || label.startsWith('Ry')) {
      btnColor = AppColors.accentGreen;
    } else if (label.startsWith('Z') || label.startsWith('Rz')) {
      btnColor = AppColors.accentBlue;
    } else if (label.startsWith('J')) {
      // Joints: Negative is Red, Positive is Green
      btnColor = label.contains('+') ? AppColors.accentGreen : AppColors.accentRed;
    } else {
      btnColor = Colors.grey;
    }

    return Tactile3DButton(
      label: label,
      baseColor: btnColor,
      width: width,
      height: height,
      isCircle: isCircle,
      onTapDown: () {
        if (label == 'HOME') {
          _sendCommand('TRIGGER_HOME');
        } else {
          _onPadInteract(label, true);
        }
      },
      onTapUp: () {
        if (label != 'HOME') _onPadInteract(label, false);
      },
    );
  }

  Widget _buildStatusItem(String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.bgMain,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            val,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorButton(
    String text,
    Color color,
    VoidCallback onPressed, {
    bool isActive = false,
    double padding = 18,
    double fontSize = 14,
    IconData? icon,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive
            ? color
            : (text == "STOP" || text == "EXIT SYSTEM" || text == "DISCONNECT"
                  ? AppColors.accentRed
                  : AppColors.btnBg),
        foregroundColor: isActive || text == "STOP"
            ? Colors.black
            : Colors.white,
        side: BorderSide(
          color: isActive ? Colors.white : color,
          width: isActive ? 2 : 1,
        ),
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: isActive ? 10 : 2,
      ),
      onPressed: onPressed,
      child: icon == null
          ? Text(
              text,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
              textAlign: TextAlign.center,
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: fontSize + 4),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildGenericButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.btnBg,
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  // --- REUSED DIALOGS ---
  void _showNewTpFileDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentBlue, width: 1),
        ),
        title: const Text(
          "Create TP File",
          style: TextStyle(
            color: AppColors.accentBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "File Name (e.g., job_01)",
            labelStyle: TextStyle(color: Colors.grey),
            border: OutlineInputBorder(),
            filled: true,
            fillColor: AppColors.bgMain,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBlue,
            ),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                _sendCommand('NEW_TP_FILE', nameCtrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text(
              "CREATE",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTpFileListSheet(String actionTitle) {
    IconData actionIcon = actionTitle == "Open"
        ? Icons.folder_open
        : Icons.delete_forever;
    Color actionColor = actionTitle == "Open"
        ? AppColors.accentYellow
        : AppColors.accentRed;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "$actionTitle TP File",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: actionColor,
              ),
            ),
            const Divider(color: AppColors.border, height: 30),
            Expanded(
              child: _tpFileList.isEmpty
                  ? const Center(
                      child: Text(
                        "No files available.",
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _tpFileList.length,
                      itemBuilder: (ctx, i) {
                        final fileData = _tpFileList[i].split('|');
                        final fileName = fileData[0];
                        final fileDate = fileData.length > 1 ? fileData[1] : "";
                        return ListTile(
                          leading: const Icon(
                            Icons.insert_drive_file,
                            color: AppColors.accentBlue,
                          ),
                          title: Text(
                            fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            fileDate,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            actionIcon,
                            color: actionColor,
                            size: 20,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (actionTitle == "Open")
                              _sendCommand('OPEN_TP_FILE', fileName);
                            else
                              _showDeleteFileConfirmDialog(fileName);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteFileConfirmDialog(String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.accentRed),
            SizedBox(width: 10),
            Text(
              "Delete File?",
              style: TextStyle(
                color: AppColors.accentRed,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to permanently delete the file '$fileName'?",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () {
              _sendCommand('DELETE_TP_FILE', fileName);
              Navigator.pop(ctx);
            },
            child: const Text(
              "DELETE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTpModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentBlue, width: 1),
        ),
        title: const Text(
          "Select TP Mode",
          style: TextStyle(
            color: AppColors.accentBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                "TP Mode",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: _tpRunMode == "TP Mode"
                  ? const Icon(Icons.check, color: AppColors.accentGreen)
                  : null,
              onTap: () {
                _sendCommand('SET_TP_RUN_MODE', 'Tp');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text(
                "MOVJ",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: _tpRunMode == "MOVJ"
                  ? const Icon(Icons.check, color: AppColors.accentGreen)
                  : null,
              onTap: () {
                _sendCommand('SET_TP_RUN_MODE', 'MOVJ');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text(
                "MOVL",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: _tpRunMode == "MOVL"
                  ? const Icon(Icons.check, color: AppColors.accentGreen)
                  : null,
              onTap: () {
                _sendCommand('SET_TP_RUN_MODE', 'MOVL');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTpSelectionSheet(
    String actionTitle,
    Function(int index, Map<String, dynamic> tp) onSelect,
  ) {
    IconData getIcon() => actionTitle == "Modify"
        ? Icons.edit
        : (actionTitle == "Run" ? Icons.play_arrow : Icons.delete);
    Color getColor() => actionTitle == "Modify"
        ? AppColors.accentBlue
        : (actionTitle == "Run" ? AppColors.accentGreen : AppColors.accentRed);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "$actionTitle TP Point",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: getColor(),
              ),
            ),
            const Divider(color: AppColors.border, height: 30),
            Expanded(
              child: _tpList.isEmpty
                  ? const Center(
                      child: Text(
                        "No TP points available.",
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _tpList.length,
                      itemBuilder: (ctx, i) {
                        final tp = _tpList[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.btnBg,
                            child: Text(
                              "${i + 1}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            tp['name'] ?? "Unknown",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            tp['value'] ?? "",
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            getIcon(),
                            color: getColor(),
                            size: 20,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            onSelect(i, tp);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PRG SPECIFIC: SELECTION SHEET & RUN CONFIRMATION
  // =========================================================================
  void _showPrgSelectionSheet(
    String actionTitle,
    Function(int index, Map<String, dynamic> prgItem) onSelect,
  ) {
    // Dynamically set colors and icons based on whether we are Running or Deleting
    IconData getIcon() =>
        actionTitle == "Run" ? Icons.play_arrow : Icons.delete;
    Color getColor() =>
        actionTitle == "Run" ? AppColors.accentGreen : AppColors.accentRed;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "$actionTitle PRG Instruction",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: getColor(), // <-- Uses dynamic color (Green or Red)
              ),
            ),
            const Divider(color: AppColors.border, height: 30),
            Expanded(
              child: _prProgramData.isEmpty
                  ? const Center(
                      child: Text(
                        "No program instructions available.",
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _prProgramData.length,
                      itemBuilder: (ctx, i) {
                        final prgItem = _prProgramData[i];

                        // Parse standard PRG variables safely
                        String name =
                            prgItem['name'] ?? prgItem['inst'] ?? "CMD";
                        String val = prgItem['value'] ?? prgItem['data'] ?? "";

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.btnBg,
                            child: Text(
                              "${i + 1}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            val,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            getIcon(), // <-- Uses dynamic icon (Play Arrow or Trash Bin)
                            color: getColor(),
                            size: 20,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            onSelect(i, prgItem);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrgRunConfirmDialog(int index, Map<String, dynamic> prgItem) {
    String name = prgItem['name'] ?? prgItem['inst'] ?? "CMD";
    String val = prgItem['value'] ?? prgItem['data'] ?? "";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentGreen, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill, color: AppColors.accentGreen),
            SizedBox(width: 10),
            Text(
              "Run Program Step?",
              style: TextStyle(
                color: AppColors.accentGreen,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Step ${index + 1}: $name",
              style: const TextStyle(
                color: AppColors.accentBlue,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Data: $val",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () {
              // 1. Select the specific PRG Row
              _sendCommand('SELECT_PR_ROW', index);
              // 2. Trigger the run command
              _sendCommand('RUN_PROGRAM');
              Navigator.pop(ctx);
            },
            child: const Text(
              "RUN",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRunConfirmDialog(int index, Map<String, dynamic> tp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentGreen, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill, color: AppColors.accentGreen),
            SizedBox(width: 10),
            Text(
              "Run Point?",
              style: TextStyle(
                color: AppColors.accentGreen,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Name: ${tp['name']}",
              style: const TextStyle(
                color: AppColors.accentBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "Data: ${tp['value']}",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
            ),
            onPressed: () {
              _sendCommand('SELECT_TP_INDEX', index);
              _sendCommand('RUN_TP');
              Navigator.pop(ctx);
            },
            child: const Text(
              "RUN",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInsertTpDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        title: const Text(
          "Insert Target Point",
          style: TextStyle(
            color: Color(0xFF00E5FF),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Point Name",
            labelStyle: TextStyle(color: Colors.grey),
            border: OutlineInputBorder(),
            filled: true,
            fillColor: AppColors.bgMain,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
            ),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                _sendCommand('SET_TP_NAME', nameCtrl.text);
                _sendCommand('INSERT_TP');
                Navigator.pop(ctx);
              }
            },
            child: const Text(
              "INSERT",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletePointConfirmDialog(int index, Map<String, dynamic> tp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 1),
        ),
        title: const Text(
          "Delete Point",
          style: TextStyle(
            color: AppColors.accentRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Name: ${tp['name']}\n\nDelete this point?",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () {
              setState(() {
                if (index >= 0 && index < _tpList.length)
                  _tpList.removeAt(index);
              });
              _sendCommand('DELETE_TP_INDEX', index);
              Navigator.pop(ctx);
            },
            child: const Text(
              "DELETE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentBlue, width: 1),
        ),
        title: const Text(
          "Modify Point",
          style: TextStyle(
            color: AppColors.accentBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Point Name"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: xCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "X Value (mm)",
                  filled: true,
                  fillColor: AppColors.bgMain,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: yCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "Y Value (mm)",
                  filled: true,
                  fillColor: AppColors.bgMain,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: zCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "Z Value (mm)",
                  filled: true,
                  fillColor: AppColors.bgMain,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBlue,
            ),
            onPressed: () {
              _sendCommand('SELECT_TP_INDEX', index);
              _sendModifyCommand(
                nameCtrl.text,
                xCtrl.text,
                yCtrl.text,
                zCtrl.text,
              );
              setState(() {
                if (index >= 0 && index < _tpList.length) {
                  var modifiedItem = _tpList.removeAt(index);
                  modifiedItem['name'] = nameCtrl.text;
                  modifiedItem['value'] =
                      "x:${xCtrl.text} y:${yCtrl.text} z:${zCtrl.text}";
                  _tpList.add(modifiedItem);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text(
              "CONFIRM",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // PRG: FILE CREATION AND DELETION DIALOGS
  // =========================================================================
  void _showNewPrFileDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentBlue, width: 1),
        ),
        title: const Text(
          "Create PRG File",
          style: TextStyle(
            color: AppColors.accentBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Program Name (e.g., weld_path_1)",
            labelStyle: TextStyle(color: Colors.grey),
            border: OutlineInputBorder(),
            filled: true,
            fillColor: AppColors.bgMain,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentBlue,
            ),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                _sendCommand(
                  'NEW_PR_FILE',
                  nameCtrl.text,
                ); // <--- Triggers C++ requestNewPr
                Navigator.pop(ctx);
              }
            },
            child: const Text(
              "CREATE",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletePrFileConfirmDialog(String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.accentRed),
            SizedBox(width: 10),
            Text(
              "Delete PRG File?",
              style: TextStyle(
                color: AppColors.accentRed,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to permanently delete the program '$fileName'?",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () {
              _sendCommand(
                'DELETE_PR_FILE',
                fileName,
              ); // <--- Triggers C++ requestDeletePrFile
              Navigator.pop(ctx);
            },
            child: const Text(
              "DELETE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletePrgRowConfirmDialog(int index, Map<String, dynamic> prgItem) {
    String name = prgItem['name'] ?? prgItem['inst'] ?? "CMD";
    String val = prgItem['value'] ?? prgItem['data'] ?? "";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentRed, width: 1.5),
        ),
        title: const Text(
          "Delete Instruction",
          style: TextStyle(
            color: AppColors.accentRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Step ${index + 1}: $name\nData: $val\n\nDelete this instruction?",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () {
              // 1. Select row, 2. Delete it (Matches C++ backend signals)
              _sendCommand('SELECT_PR_ROW', index);
              _sendCommand('DELETE_PR_INSTRUCTION');

              // Optimistically update the UI to prevent ghost rows
              setState(() {
                if (index >= 0 && index < _prProgramData.length) {
                  _prProgramData.removeAt(index);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text(
              "DELETE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// NEW: LIVE EXECUTION BOTTOM SHEET WIDGET (INDUSTRIAL STYLING)
// =========================================================================
class LiveExecutionSheet extends StatefulWidget {
  final _ControllerScreenState parentState;
  final bool isPrgMode;

  const LiveExecutionSheet(
    this.parentState, {
    super.key,
    this.isPrgMode = false,
  });

  @override
  State<LiveExecutionSheet> createState() => _LiveExecutionSheetState();
}

class _LiveExecutionSheetState extends State<LiveExecutionSheet> {
  Timer? _timer;
  final ScrollController _scrollController = ScrollController();
  int _lastHighlighted = -1;

  @override
  void initState() {
    super.initState();
    // Auto-refresh the popup every 200ms to fetch live index & list updates
    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (mounted) {
        setState(() {});
        _scrollToHighlight();
      }
    });
  }

  void _scrollToHighlight() {
    final p = widget.parentState;
    int current = p._highlightedInstruction;

    // Select the correct list to check length
    final currentList = widget.isPrgMode ? p._prProgramData : p._tpList;

    if (current >= 0 && current != _lastHighlighted && currentList.isNotEmpty) {
      _lastHighlighted = current;

      double rowHeight = 60.0;
      double targetOffset = current * rowHeight;

      if (_scrollController.hasClients) {
        double maxScroll = _scrollController.position.maxScrollExtent;
        if (targetOffset > maxScroll) targetOffset = maxScroll;
        if (targetOffset < 0) targetOffset = 0;

        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  static const TextStyle _headerStyle = TextStyle(
    color: Colors.grey,
    fontSize: 10,
    fontWeight: FontWeight.bold,
    letterSpacing: 1,
  );

  // --- NEW: PROFESSIONAL ROW DETAILS POPUP ---
  void _showRowDetailsDialog(
    BuildContext context,
    int index,
    String inst,
    String name,
    String value,
    String speed,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgPanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.accentPurple, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.data_object, color: AppColors.accentPurple),
            SizedBox(width: 10),
            Text(
              "INSTRUCTION DETAILS",
              style: TextStyle(
                color: AppColors.accentPurple,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow("STEP NO", "${index + 1}"),
              const SizedBox(height: 8),
              _buildDetailRow("INSTRUCTION", inst),
              const SizedBox(height: 8),
              _buildDetailRow("NAME", name),
              const SizedBox(height: 8),
              _buildDetailRow("VALUE / DATA", value),
              const SizedBox(height: 8),
              _buildDetailRow("SPEED", speed),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "CLOSE",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // Helper for the details popup layout
  Widget _buildDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lcdBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parentState;

    // Smart List Selection
    final listData = widget.isPrgMode ? p._prProgramData : p._tpList;
    final activeFileName = widget.isPrgMode
        ? p._currentPrName
        : p._currentTpName;

    return Container(
      height: MediaQuery.of(context).size.height * 0.70,
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 15),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.monitor, color: AppColors.accentPurple),
                const SizedBox(width: 10),
                const Text(
                  "AUTO EXECUTION MONITOR",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentPurple,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lcdBg,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    activeFileName,
                    style: const TextStyle(
                      color: AppColors.accentBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1, thickness: 1),

          // --- UPDATED: SEPARATED HEADERS ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: const [
                SizedBox(width: 40, child: Text("S.NO", style: _headerStyle)),
                Expanded(flex: 2, child: Text("INST", style: _headerStyle)),
                Expanded(flex: 3, child: Text("NAME", style: _headerStyle)),
                Expanded(flex: 4, child: Text("VALUE", style: _headerStyle)),
                SizedBox(
                  width: 50,
                  child: Text(
                    "SPEED",
                    textAlign: TextAlign.right,
                    style: _headerStyle,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1, thickness: 1),

          Expanded(
            child: listData.isEmpty
                ? const Center(
                    child: Text(
                      "No program data available.\nLoad a TP or PRG file.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: listData.length,
                    itemBuilder: (context, index) {
                      final item = listData[index];
                      bool isHighlighted = (index == p._highlightedInstruction);

                      // --- UPDATED: PARSE INST AND NAME SEPARATELY ---
                      String inst =
                          item['inst'] ??
                          item['type'] ??
                          item['instruction'] ??
                          "CMD";
                      String name = item['name'] ?? "-";
                      String value = item['value'] ?? item['data'] ?? "-";
                      String speed = item['speed']?.toString() ?? "-";

                      return InkWell(
                        onTap: () => _showRowDetailsDialog(
                          context,
                          index,
                          inst,
                          name,
                          value,
                          speed,
                        ),
                        child: Container(
                          height: 60.0,
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? AppColors.accentPurple.withOpacity(0.15)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isHighlighted
                                    ? AppColors.accentPurple
                                    : Colors.transparent,
                                width: 4,
                              ),
                              bottom: const BorderSide(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  "${index + 1}",
                                  style: TextStyle(
                                    color: isHighlighted
                                        ? Colors.white
                                        : Colors.grey[600],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              // INST COLUMN
                              Expanded(
                                flex: 2,
                                child: Text(
                                  inst,
                                  style: TextStyle(
                                    color: isHighlighted
                                        ? AppColors.accentPurple
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // NAME COLUMN
                              Expanded(
                                flex: 3,
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: isHighlighted
                                        ? Colors.white
                                        : AppColors.textSec,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // VALUE COLUMN
                              Expanded(
                                flex: 4,
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    color: isHighlighted
                                        ? Colors.white
                                        : AppColors.textSec,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // SPEED COLUMN
                              SizedBox(
                                width: 50,
                                child: Text(
                                  speed,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: isHighlighted
                                        ? AppColors.accentYellow
                                        : Colors.grey[600],
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Container(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 25,
            ),
            decoration: const BoxDecoration(
              color: AppColors.lcdBg,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.accentGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p._currentInstructionString.isNotEmpty
                        ? p._currentInstructionString
                        : "System Standing By...",
                    style: const TextStyle(
                      color: AppColors.accentGreen,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// =========================================================================
// NEW: TACTILE 3D BUTTON COMPONENT
// =========================================================================
class Tactile3DButton extends StatefulWidget {
  final String label;
  final double width;
  final double height;
  final Color baseColor;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final bool isCircle;

  const Tactile3DButton({
    super.key,
    required this.label,
    required this.baseColor,
    required this.onTapDown,
    required this.onTapUp,
    this.width = 65,
    this.height = 65,
    this.isCircle = false,
  });

  @override
  State<Tactile3DButton> createState() => _Tactile3DButtonState();
}

class _Tactile3DButtonState extends State<Tactile3DButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // Generate a darker shade for the 3D edge
    final darkerColor = Color.lerp(widget.baseColor, Colors.black, 0.4)!;
    // Highlight color for the font based on the label length
    final double fontSize = widget.label.length > 3 ? 14 : 24;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        widget.onTapDown();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTapUp();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        widget.onTapUp();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50), // Snappy physical push
        width: widget.width,
        height: widget.height,
        // The container moves down via padding when pressed, simulating a push
        margin: EdgeInsets.only(
          top: _isPressed ? 6 : 0, 
          bottom: _isPressed ? 0 : 6,
          left: 4, right: 4,
        ),
        decoration: BoxDecoration(
          color: widget.baseColor,
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.isCircle ? null : BorderRadius.circular(10),
          boxShadow: _isPressed
              ? [] // Flat when pressed
              : [
                  // 3D Bottom Edge
                  BoxShadow(
                    color: darkerColor,
                    offset: const Offset(0, 6),
                  ),
                  // Drop Shadow
                  const BoxShadow(
                    color: Colors.black45,
                    offset: Offset(0, 8),
                    blurRadius: 4,
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: Colors.white, // All labels bold white per request
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
            letterSpacing: widget.label == "HOME" ? 1 : 0,
          ),
        ),
      ),
    );
  }
}