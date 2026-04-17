import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF5F4F0),
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AttendanceApp());
}

// ─── Theme Colors ─────────────────────────────────────────────────────────────
const kBgColor = Color(0xFFF5F4F0);
const kWhite = Color(0xFFFFFFFF);
const kBorder = Color(0xFFE8E6E0);
const kRed = Color(0xFFD04A2A);
const kGreen = Color(0xFF2A7D4F);
const kText = Color(0xFF1A1A1A);
const kSubText = Color(0xFF888888);
const kMuted = Color(0xFF999999);
const kLight = Color(0xFFBBBBBB);

// ─── Root App ─────────────────────────────────────────────────────────────────
class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: const Color(0xFFE8E6E0),
        colorScheme: ColorScheme.fromSeed(seedColor: kRed),
        useMaterial3: true,
      ),
      home: const AttendanceHome(),
    );
  }
}

// ─── Log Entry Model ──────────────────────────────────────────────────────────
class LogEntry {
  final String type;
  final String time;
  final String location;
  LogEntry({required this.type, required this.time, required this.location});
}

// ─── Location Helper ──────────────────────────────────────────────────────────
Future<String> fetchRealLocation() async {
  try {
    // 1. Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'Location services disabled';

    // 2. Check / request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied';
    }

    // 3. Get actual GPS position
    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // 4. Reverse-geocode to a readable address
    final List<Placemark> placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      // Build a clean address string from available fields
      final parts = <String>[
        if ((p.name ?? '').isNotEmpty && p.name != p.thoroughfare) p.name!,
        if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
        if ((p.locality ?? '').isNotEmpty) p.locality!,
        if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
        if ((p.postalCode ?? '').isNotEmpty) p.postalCode!,
        if ((p.country ?? '').isNotEmpty) p.country!,
      ];
      return parts.join(', ');
    }

    // Fallback: show raw coordinates
    return '${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)}';
  } catch (e) {
    return 'Unable to fetch location';
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────
class AttendanceHome extends StatefulWidget {
  const AttendanceHome({super.key});

  @override
  State<AttendanceHome> createState() => _AttendanceHomeState();
}

class _AttendanceHomeState extends State<AttendanceHome> {
  late Timer _clockTimer;
  String _liveClock = '';
  String _topClock = '';

  String _mode = 'in';
  String _lastCheckIn = '--:--';
  String _lastCheckOut = '--:--';

  // Location state
  bool _showLocation = false;
  String _locationText = 'Fetching location…';
  bool _locationLoading = false;

  final List<LogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _updateClocks();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClocks(),
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  void _updateClocks() {
    final now = DateTime.now();
    setState(() {
      _topClock = DateFormat('hh:mm').format(now);
      _liveClock = DateFormat('hh:mm:ss a').format(now);
    });
  }

  String _nowTime() => DateFormat('hh:mm a').format(DateTime.now());

  // ── Fetch GPS location then record check-in ────────────────────────────────
  Future<void> _doCheckIn() async {
    final t = _nowTime();

    // Show location box immediately with loading state
    setState(() {
      _lastCheckIn = t;
      _mode = 'out';
      _showLocation = true;
      _locationLoading = true;
      _locationText = 'Fetching location…';
    });

    // Fetch real GPS location in background
    final loc = await fetchRealLocation();

    if (mounted) {
      setState(() {
        _locationLoading = false;
        _locationText = loc;
      });
      _log.add(LogEntry(type: 'Check In', time: t, location: loc));
      _showToast('Checked in at $t');
    }
  }

  void _doCheckOut() {
    final t = _nowTime();
    setState(() {
      _lastCheckOut = t;
      _mode = 'in';
      _showLocation = false;
      _locationText = 'Fetching location…';
      _log.add(LogEntry(type: 'Check Out', time: t, location: ''));
    });
    _showToast('Checked out at $t');
  }

  void _handleAction() {
    if (_mode == 'in') {
      _doCheckIn();
    } else {
      _doCheckOut();
    }
  }

  // ── Toast ──────────────────────────────────────────────────────────────────
  OverlayEntry? _toastEntry;

  void _showToast(String msg) {
    _toastEntry?.remove();
    _toastEntry = OverlayEntry(builder: (_) => _ToastWidget(message: msg));
    Overlay.of(context).insert(_toastEntry!);
    Future.delayed(const Duration(milliseconds: 2600), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  Future<void> _openQRScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(mode: _mode),
        fullscreenDialog: true,
      ),
    );
    if (result != null) {
      _handleAction();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayNum = DateFormat('d').format(now);
    final monthYear = DateFormat('MMMM yyyy').format(now);
    final accentColor = _mode == 'in' ? kRed : kGreen;

    return Scaffold(
      backgroundColor: const Color(0xFFE8E6E0),
      body: SafeArea(
        child: Center(
          child: _PhoneFrame(
            child: Column(
              children: [
                _StatusBar(topClock: _topClock),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const Text(
                          'Welcome,',
                          style: TextStyle(
                            fontSize: 13,
                            color: kSubText,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Employee EMP-2047',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          "Today's status",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _StatusCard(
                          checkIn: _lastCheckIn,
                          checkOut: _lastCheckOut,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$dayNum ',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: kRed,
                                    ),
                                  ),
                                  TextSpan(
                                    text: monthYear,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: kText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _liveClock,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: kSubText,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),

                        // ── Location box (real GPS address) ────────────────
                        AnimatedSize(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                          child: _showLocation
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kWhite,
                                      border: Border.all(color: kBorder),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Pin icon
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 1,
                                          ),
                                          child: Icon(
                                            Icons.location_on_rounded,
                                            size: 14,
                                            color: kRed,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: _locationLoading
                                              ? Row(
                                                  children: const [
                                                    SizedBox(
                                                      width: 11,
                                                      height: 11,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 1.5,
                                                            color: kMuted,
                                                          ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Fetching location…',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: kMuted,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Text.rich(
                                                  TextSpan(
                                                    children: [
                                                      const TextSpan(
                                                        text: 'Location: ',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 12,
                                                          color: kText,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: _locationText,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: kMuted,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 20),
                        _QRScanCard(
                          mode: _mode,
                          accentColor: accentColor,
                          onTap: _openQRScanner,
                        ),

                        // ── Activity Log ───────────────────────────────────
                        if (_log.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          const Text(
                            'Activity Log',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: kText,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._log.reversed.map(
                            (e) => _LogEntryWidget(entry: e),
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── QR Scanner Screen ────────────────────────────────────────────────────────
class QRScannerScreen extends StatefulWidget {
  final String mode;
  const QRScannerScreen({super.key, required this.mode});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MobileScannerController _controller;
  StreamSubscription<Object?>? _subscription;
  bool _scanned = false;
  bool _torchOn = false;

  late AnimationController _lineAnim;
  late Animation<double> _linePos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ autoStart: false — we control start manually
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      autoStart: false,
    );

    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _linePos = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _lineAnim, curve: Curves.easeInOut));

    // ✅ Start camera only after widget tree is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _controller.start();
      _subscription = _controller.barcodes.listen(_onBarcode);
    });
  }

  void _onBarcode(BarcodeCapture capture) {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _scanned = true;
    unawaited(_controller.stop());
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) Navigator.of(context).pop(raw);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // ✅ Cancel old subscription before creating new one
        _subscription?.cancel();
        _subscription = null;
        unawaited(_controller.start());
        _subscription = _controller.barcodes.listen(_onBarcode);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _subscription?.cancel();
        _subscription = null;
        unawaited(_controller.stop());
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lineAnim.dispose();
    _subscription?.cancel();
    _subscription = null;
    _controller.dispose(); // ✅ synchronous dispose
    super.dispose(); // ✅ always last
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.mode == 'in';
    final accentColor = isCheckIn ? kRed : kGreen;
    final label = isCheckIn ? 'Scan to Check In' : 'Scan to Check Out';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onBarcode),
          _ScanOverlay(accentColor: accentColor, linePos: _linePos),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleTorch,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _torchOn
                                ? Colors.white.withOpacity(0.3)
                                : Colors.white.withOpacity(0.15),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _torchOn
                                ? Icons.flashlight_on
                                : Icons.flashlight_off_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Align the QR code within the frame',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
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

// ─── Scan Overlay ─────────────────────────────────────────────────────────────
class _ScanOverlay extends StatelessWidget {
  final Color accentColor;
  final Animation<double> linePos;

  const _ScanOverlay({required this.accentColor, required this.linePos});

  @override
  Widget build(BuildContext context) {
    const boxSize = 240.0;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final left = (screenW - boxSize) / 2;
    final top = (screenH - boxSize) / 2 - 30;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: const ColoredBox(color: Color(0xCC000000)),
        ),
        Positioned(
          top: top + boxSize,
          left: 0,
          right: 0,
          bottom: 0,
          child: const ColoredBox(color: Color(0xCC000000)),
        ),
        Positioned(
          top: top,
          left: 0,
          width: left,
          height: boxSize,
          child: const ColoredBox(color: Color(0xCC000000)),
        ),
        Positioned(
          top: top,
          left: left + boxSize,
          right: 0,
          height: boxSize,
          child: const ColoredBox(color: Color(0xCC000000)),
        ),
        Positioned(
          left: left,
          top: top,
          width: boxSize,
          height: boxSize,
          child: _CornerBrackets(color: accentColor),
        ),
        AnimatedBuilder(
          animation: linePos,
          builder: (_, __) {
            final dy = top + linePos.value * boxSize;
            return Positioned(
              left: left + 8,
              top: dy,
              width: boxSize - 16,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      accentColor,
                      Colors.transparent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Corner Brackets ──────────────────────────────────────────────────────────
class _CornerBrackets extends StatelessWidget {
  final Color color;
  const _CornerBrackets({required this.color});

  @override
  Widget build(BuildContext context) {
    const r = 4.0;
    const w = 32.0;
    const t = 3.0;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: _Bracket(
            color: color,
            r: r,
            w: w,
            t: t,
            corner: _Corner.topLeft,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _Bracket(
            color: color,
            r: r,
            w: w,
            t: t,
            corner: _Corner.topRight,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          child: _Bracket(
            color: color,
            r: r,
            w: w,
            t: t,
            corner: _Corner.bottomLeft,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: _Bracket(
            color: color,
            r: r,
            w: w,
            t: t,
            corner: _Corner.bottomRight,
          ),
        ),
      ],
    );
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _Bracket extends StatelessWidget {
  final Color color;
  final double r, w, t;
  final _Corner corner;

  const _Bracket({
    required this.color,
    required this.r,
    required this.w,
    required this.t,
    required this.corner,
  });

  @override
  Widget build(BuildContext context) {
    BorderRadius borderRadius;
    Border border;

    switch (corner) {
      case _Corner.topLeft:
        borderRadius = BorderRadius.only(topLeft: Radius.circular(r));
        border = Border(
          top: BorderSide(color: color, width: t),
          left: BorderSide(color: color, width: t),
        );
        break;
      case _Corner.topRight:
        borderRadius = BorderRadius.only(topRight: Radius.circular(r));
        border = Border(
          top: BorderSide(color: color, width: t),
          right: BorderSide(color: color, width: t),
        );
        break;
      case _Corner.bottomLeft:
        borderRadius = BorderRadius.only(bottomLeft: Radius.circular(r));
        border = Border(
          bottom: BorderSide(color: color, width: t),
          left: BorderSide(color: color, width: t),
        );
        break;
      case _Corner.bottomRight:
        borderRadius = BorderRadius.only(bottomRight: Radius.circular(r));
        border = Border(
          bottom: BorderSide(color: color, width: t),
          right: BorderSide(color: color, width: t),
        );
        break;
    }

    return SizedBox(
      width: w,
      height: w,
      child: DecoratedBox(
        decoration: BoxDecoration(border: border, borderRadius: borderRadius),
      ),
    );
  }
}

// ─── Phone Frame ───���──────────────────────────────────────────────────────────
class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 780),
      decoration: BoxDecoration(
        color: kBgColor,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

// ─── Status Bar ───────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final String topClock;
  const _StatusBar({required this.topClock});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBgColor,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            topClock,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF555555),
            ),
          ),
          const Text(
            '●●●●  WiFi  100%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF555555),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Card ──────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final String checkIn;
  final String checkOut;
  const _StatusCard({required this.checkIn, required this.checkOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _StatusItem(label: 'CHECK IN', value: checkIn, isCheckIn: true),
            Container(
              width: 1,
              color: kBorder,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            _StatusItem(label: 'CHECK OUT', value: checkOut, isCheckIn: false),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isCheckIn;
  const _StatusItem({
    required this.label,
    required this.value,
    required this.isCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final isSet = value != '--:--';
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: kMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: -0.5,
              color: (isCheckIn && isSet) ? kRed : kText,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── QR Scan Card ─────────────────────────────────────────────────────────────
class _QRScanCard extends StatelessWidget {
  final String mode;
  final Color accentColor;
  final VoidCallback onTap;

  const _QRScanCard({
    required this.mode,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCheckIn = mode == 'in';
    final label = isCheckIn ? 'Scan to check in' : 'Scan to check out';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withOpacity(0.35), width: 1.5),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: accentColor, width: 2.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: accentColor,
                      size: 38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: kSubText,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Point your camera at the office QR code',
              style: TextStyle(fontSize: 11, color: kLight),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to open camera scanner',
              style: TextStyle(
                fontSize: 11,
                color: accentColor.withOpacity(0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Log Entry Widget ─────────────────────────────────────────────────────────
class _LogEntryWidget extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryWidget({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isIn = entry.type == 'Check In';
    final color = isIn ? kRed : kGreen;
    final icon = isIn ? Icons.login_rounded : Icons.logout_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.type,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kText,
                  ),
                ),
                const Text(
                  'via QR Scan',
                  style: TextStyle(fontSize: 11, color: kMuted),
                ),
                // ✅ Show GPS address in log too (only for check-in)
                if (entry.location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 11,
                        color: kMuted,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          entry.location,
                          style: const TextStyle(fontSize: 10, color: kMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.time,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: kSubText,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Toast Widget ─────────────────────────────────────────────────────────────
class _ToastWidget extends StatefulWidget {
  final String message;
  const _ToastWidget({required this.message});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 48,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
