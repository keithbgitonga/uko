import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

const String kApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/v1',
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        reportClientError('driver', details.exceptionAsString(), details.stack);
      };
      try {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        FirebaseMessaging.onMessage.listen((message) {
          debugPrint('FCM foreground: ${message.notification?.title}');
        });
      } catch (e) {
        debugPrint('Firebase init skipped: $e');
      }
      runApp(const UkoDriverApp());
    },
    (error, stack) => reportClientError('driver', error.toString(), stack),
  );
}

Future<void> reportClientError(String app, String message, StackTrace? stack, {String? token}) async {
  try {
    await http
        .post(
          Uri.parse('$kApiBase/diagnostics/client-errors'),
          headers: {
            'content-type': 'application/json',
            if (token != null) 'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'app': app,
            'message': message,
            'stack': stack?.toString() ?? '',
            'version': '0.1.0',
            'platform': Platform.operatingSystem,
          }),
        )
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // Crash reporting must never crash the app.
  }
}

class UkoDriverApp extends StatelessWidget {
  const UkoDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uko? Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C8C86), brightness: Brightness.light, surface: Colors.white),
        scaffoldBackgroundColor: const Color(0xFFF4F8F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Color(0xFF08222B),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          toolbarHeight: 52,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE7E6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0C8C86), width: 1.6)),
          prefixIconColor: const Color(0xFF0C8C86),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE4ECEA), thickness: 1, space: 24),
      ),
      home: const SignInPage(),
    );
  }
}

class UkoTopBar extends StatelessWidget implements PreferredSizeWidget {
  const UkoTopBar({super.key, this.actions});
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: const Color(0xFF08222B),
        toolbarHeight: 52,
        actions: actions,
      );
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);
  final int statusCode;
  final String code;
  final String message;
  @override
  String toString() => message;
}

class AuthSession {
  AuthSession({required this.accessToken, required this.user});
  final String accessToken;
  final Map<String, dynamic> user;
  String get phone => (user['phone'] ?? '') as String;
}

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? accessToken;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (accessToken != null) 'authorization': 'Bearer $accessToken',
  };

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    Map<String, dynamic> json;
    try {
      json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      json = <String, dynamic>{'message': text};
    }
    if (response.statusCode >= 400) {
      final raw = json['message'];
      final message = raw is List ? raw.join(', ') : (raw ?? 'Request failed').toString();
      throw ApiException(response.statusCode, (json['code'] ?? 'HTTP_${response.statusCode}').toString(), message);
    }
    return json;
  }

  Future<String?> requestOtp(String phone) async {
    final json = await _post('/auth/otp/request', {'phone': phone});
    return json['dev_code'] as String?;
  }

  Future<AuthSession> verifyOtp(String phone, String code) async {
    final json = await _post('/auth/otp/verify', {'phone': phone, 'code': code});
    final tokens = (json['tokens'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    final session = AuthSession(
      accessToken: (tokens['accessToken'] ?? '') as String,
      user: (json['user'] ?? <String, dynamic>{}) as Map<String, dynamic>,
    );
    accessToken = session.accessToken;
    return session;
  }

  Future<void> registerDevice(String token) async {
    await _post('/notifications/devices', {'token': token, 'platform': 'android'});
  }

  Future<RouteResult> getRoute({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final json = await _get('/routes?pickupLat=$pickupLat&pickupLng=$pickupLng&dropoffLat=$dropoffLat&dropoffLng=$dropoffLng');
    return RouteResult.fromJson((json['route'] as Map).cast<String, dynamic>());
  }

  Future<void> updateLocation(double lat, double lng) async {
    await _post('/driver/location', {'lat': lat, 'lng': lng});
  }

  Future<DriverStatus> status() async => DriverStatus.fromJson(await _get('/driver/status'));
  Future<DriverEarnings> earnings() async => DriverEarnings.fromJson(await _get('/driver/earnings'));
  Future<DriverShift> shift() async => DriverShift.fromJson(await _get('/driver/shift'));

  Future<List<DriverDocument>> documents() async {
    final json = await _get('/driver/documents');
    return ((json['documents'] as List?) ?? []).map((e) => DriverDocument.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DriverDocument> uploadDocument(String type) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/driver/documents'));
    request.headers['authorization'] = 'Bearer $accessToken';
    request.fields['type'] = type;
    request.fields['documentNumber'] = '${type.toUpperCase()}-DEMO';
    final file = File('${Directory.systemTemp.path}/uko-demo-$type.txt');
    await file.writeAsString('Uko? demo $type document for pilot verification.');
    request.files.add(await http.MultipartFile.fromPath('file', file.path, filename: 'demo-$type.txt'));
    final response = await http.Response.fromStream(await request.send());
    final body = response.body;
    final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, (json['code'] ?? 'DOCUMENT_UPLOAD') as String, (json['message'] ?? 'Upload failed') as String);
    }
    return DriverDocument.fromJson(json['document'] as Map<String, dynamic>);
  }

  Future<DriverDocument> uploadDocumentFile(String type, String path, String fileName) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/driver/documents'));
    request.headers['authorization'] = 'Bearer $accessToken';
    request.fields['type'] = type;
    request.fields['documentNumber'] = '${type.toUpperCase()}-PHOTO';
    request.files.add(await http.MultipartFile.fromPath('file', path, filename: fileName));
    final response = await http.Response.fromStream(await request.send());
    final body = response.body;
    final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, (json['code'] ?? 'DOCUMENT_UPLOAD') as String, (json['message'] ?? 'Upload failed') as String);
    }
    return DriverDocument.fromJson(json['document'] as Map<String, dynamic>);
  }

  Future<List<DriverNotification>> notifications() async {
    final json = await _get('/notifications');
    return ((json['notifications'] as List?) ?? [])
        .map((e) => DriverNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  Future<DriverStatus> setOnline(bool online) async =>
      DriverStatus.fromJson(await _post('/driver/online', {'online': online}));
  Future<List<DriverOffer>> offers() async {
    final json = await _get('/driver/offers');
    return ((json['offers'] ?? []) as List)
        .map((e) => DriverOffer.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
  Future<DriverTrip?> currentTrip() async {
    final json = await _get('/driver/trips/current');
    final trip = json['trip'];
    return trip == null ? null : DriverTrip.fromJson((trip as Map).cast<String, dynamic>());
  }
  Future<DriverTrip> acceptOffer(String id) async {
    final json = await _post('/driver/offers/$id/accept', const {});
    return DriverTrip.fromJson((json['trip'] as Map).cast<String, dynamic>());
  }
  Future<DriverStatus> rejectOffer(String id) async =>
      DriverStatus.fromJson(await _post('/driver/offers/$id/reject', const {}));
  Future<DriverTrip> cancelTrip(String id, {String? reason}) async {
    final json = await _post('/driver/trips/$id/cancel', {
      if (reason != null) 'reason': reason,
    });
    return DriverTrip.fromJson((json['trip'] as Map).cast<String, dynamic>());
  }

  Future<DriverTrip> tripAction(String id, String action, {String? pickupCode}) async {
    final json = await _post('/driver/trips/$id/$action', {
      if (pickupCode != null) 'pickupCode': pickupCode,
    });
    return DriverTrip.fromJson((json['trip'] as Map).cast<String, dynamic>());
  }
}

class DriverOffer {
  DriverOffer({required this.id, required this.riderName, required this.pickupAddress,
    required this.dropoffAddress, required this.fare, required this.distanceKm,
    required this.durationMin, required this.etaMin});
  final String id;
  final String riderName;
  final String pickupAddress;
  final String dropoffAddress;
  final int fare;
  final double distanceKm;
  final int durationMin;
  final int etaMin;

  factory DriverOffer.fromJson(Map<String, dynamic> j) {
    final pickup = (j['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dropoff = (j['dropoff'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DriverOffer(
      id: j['id'] as String,
      riderName: (j['riderName'] ?? '') as String,
      pickupAddress: (pickup['address'] ?? '') as String,
      dropoffAddress: (dropoff['address'] ?? '') as String,
      fare: (j['fare'] as num).toInt(),
      distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
      durationMin: (j['durationMin'] as num?)?.toInt() ?? 0,
      etaMin: (j['etaMin'] as num?)?.toInt() ?? 0,
    );
  }
}

class DriverTrip {
  DriverTrip({required this.id, required this.riderName, required this.pickupAddress,
    required this.dropoffAddress, required this.fare, required this.pickupCode, required this.state,
    this.pickupLat, this.pickupLng, this.dropoffLat, this.dropoffLng});
  final String id;
  final String riderName;
  final String pickupAddress;
  final String dropoffAddress;
  final int fare;
  final String pickupCode;
  final String state;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;

  factory DriverTrip.fromJson(Map<String, dynamic> j) {
    final pickup = (j['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dropoff = (j['dropoff'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DriverTrip(
      id: j['id'] as String,
      riderName: (j['riderName'] ?? '') as String,
      pickupAddress: (pickup['address'] ?? '') as String,
      dropoffAddress: (dropoff['address'] ?? '') as String,
      fare: (j['fare'] as num).toInt(),
      pickupCode: (j['pickupCode'] ?? '') as String,
      state: (j['state'] ?? '') as String,
      pickupLat: (pickup['lat'] as num?)?.toDouble(),
      pickupLng: (pickup['lng'] as num?)?.toDouble(),
      dropoffLat: (dropoff['lat'] as num?)?.toDouble(),
      dropoffLng: (dropoff['lng'] as num?)?.toDouble(),
    );
  }
}

class RouteStep {
  const RouteStep({required this.instruction, required this.distanceM});
  final String instruction;
  final int distanceM;

  factory RouteStep.fromJson(Map<String, dynamic> j) => RouteStep(
        instruction: (j['instruction'] ?? '') as String,
        distanceM: (j['distanceM'] as num?)?.toInt() ?? 0,
      );
}

class RouteResult {
  const RouteResult({required this.points, required this.distanceKm, required this.durationMin, required this.source, this.steps = const []});
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  final String source;
  final List<RouteStep> steps;

  factory RouteResult.fromJson(Map<String, dynamic> j) => RouteResult(
        points: ((j['points'] as List?) ?? [])
            .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
        distanceKm: ((j['distanceKm'] as num?) ?? 0).toDouble(),
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 0,
        source: (j['source'] ?? '') as String,
        steps: ((j['steps'] as List?) ?? [])
            .map((e) => RouteStep.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class DriverStatus {
  DriverStatus({required this.online, this.activeTrip, required this.offers});
  final bool online;
  final DriverTrip? activeTrip;
  final List<DriverOffer> offers;

  factory DriverStatus.fromJson(Map<String, dynamic> j) => DriverStatus(
    online: j['online'] == true,
    activeTrip: j['activeTrip'] == null ? null : DriverTrip.fromJson((j['activeTrip'] as Map).cast<String, dynamic>()),
    offers: ((j['offers'] ?? []) as List)
        .map((e) => DriverOffer.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

class PriceSummary {
  PriceSummary({required this.trips, required this.gross, required this.commission, required this.net});
  final int trips;
  final int gross;
  final int commission;
  final int net;

  factory PriceSummary.fromJson(Map<String, dynamic> j) => PriceSummary(
    trips: (j['trips'] as num?)?.toInt() ?? 0,
    gross: (j['gross'] as num?)?.toInt() ?? 0,
    commission: (j['commission'] as num?)?.toInt() ?? 0,
    net: (j['net'] as num?)?.toInt() ?? 0,
  );
}

class DriverEarnings {
  DriverEarnings({required this.currency, required this.commissionPercent, required this.today, required this.lifetime});
  final String currency;
  final int commissionPercent;
  final PriceSummary today;
  final PriceSummary lifetime;

  factory DriverEarnings.fromJson(Map<String, dynamic> j) => DriverEarnings(
    currency: (j['currency'] ?? 'KES') as String,
    commissionPercent: (j['commissionPercent'] as num?)?.toInt() ?? 20,
    today: PriceSummary.fromJson((j['today'] as Map?)?.cast<String, dynamic>() ?? const {}),
    lifetime: PriceSummary.fromJson((j['lifetime'] as Map?)?.cast<String, dynamic>() ?? const {}),
  );
}

class DriverDocument {
  DriverDocument({required this.id, required this.type, required this.status, this.fileName, this.createdAt});
  final String id;
  final String type;
  final String status;
  final String? fileName;
  final DateTime? createdAt;

  factory DriverDocument.fromJson(Map<String, dynamic> j) => DriverDocument(
    id: (j['id'] ?? '') as String,
    type: (j['type'] ?? '') as String,
    status: (j['status'] ?? '') as String,
    fileName: j['fileName'] as String?,
    createdAt: j['createdAt'] == null ? null : DateTime.tryParse(j['createdAt'] as String)?.toLocal(),
  );
}

class DriverNotification {
  DriverNotification({required this.id, required this.title, required this.body, this.createdAt});
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  factory DriverNotification.fromJson(Map<String, dynamic> j) => DriverNotification(
    id: (j['id'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    body: (j['body'] ?? '') as String,
    createdAt: j['createdAt'] == null ? null : DateTime.tryParse(j['createdAt'] as String)?.toLocal(),
  );
}

class DriverShift {
  DriverShift({required this.online, this.onShiftSince, required this.onlineMinutesToday,
    required this.tripsToday, required this.netToday});
  final bool online;
  final String? onShiftSince;
  final int onlineMinutesToday;
  final int tripsToday;
  final int netToday;

  factory DriverShift.fromJson(Map<String, dynamic> j) => DriverShift(
    online: j['online'] == true,
    onShiftSince: j['onShiftSince'] as String?,
    onlineMinutesToday: (j['onlineMinutesToday'] as num?)?.toInt() ?? 0,
    tripsToday: (j['tripsToday'] as num?)?.toInt() ?? 0,
    netToday: (j['netToday'] as num?)?.toInt() ?? 0,
  );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _api = ApiClient(baseUrl: kApiBase);
  final _phone = TextEditingController(text: '+254700000001');
  final _otp = TextEditingController();
  bool _otpStep = false;
  bool _busy = false;
  String? _error;
  String? _devCode;
  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter phone in international format, e.g. +254700000001');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final code = await _api.requestOtp(phone);
      setState(() { _busy = false; _otpStep = true; _devCode = code; if (code != null) _otp.text = code; });
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _verify() async {
    setState(() { _busy = true; _error = null; });
    try {
      final session = await _api.verifyOtp(_phone.text.trim(), _otp.text.trim());
      if (!mounted) return;
      unawaited(registerPushForApi(_api));
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => DriverHomePage(api: _api, session: session),
      ));
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(color: const Color(0xFF0C8C86), borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.two_wheeler, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 18),
                Text(_otpStep ? 'Enter your code' : 'Driver sign in',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_otpStep ? 'Code sent to ${_phone.text.trim()}' : 'Sign in to go online and receive Boda ride offers.',
                    style: const TextStyle(color: Color(0xFF5C7077))),
                const SizedBox(height: 22),
                if (!_otpStep) ...[
                  TextField(
                    key: const Key('phone_field'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone number'),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFF2F7F6), borderRadius: BorderRadius.circular(10)),
                    child: const Text('Pilot test login: +254700000001 · OTP 123456', style: TextStyle(fontSize: 12, color: Color(0xFF3D5A60))),
                  ),
                ] else ...[
                  if (_devCode != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFDF3E2), borderRadius: BorderRadius.circular(10)),
                      child: Text('Development code: $_devCode', style: const TextStyle(fontSize: 12)),
                    ),
                  TextField(
                    key: const Key('otp_field'),
                    controller: _otp,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: Key(_otpStep ? 'verify_otp' : 'send_otp'),
                    onPressed: _busy ? null : (_otpStep ? _verify : _sendOtp),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_otpStep ? 'Verify and continue' : 'Send code'),
                  ),
                ),
                if (_otpStep)
                  TextButton(onPressed: () => setState(() { _otpStep = false; _error = null; }), child: const Text('Use a different number')),
                const SizedBox(height: 14),
                Text('API: $kApiBase', style: const TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key, required this.api, required this.session});
  final ApiClient api;
  final AuthSession session;
  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  DriverStatus? _status;
  DriverEarnings? _earnings;
  DriverShift? _shift;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  Timer? _locationTimer;
  StreamSubscription<RemoteMessage>? _notificationTapSub;
  bool _locationBusy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_status?.online == true && _status?.activeTrip == null) _refresh(quiet: true);
    });
    _startLocationSharing();
    FirebaseMessaging.instance.getInitialMessage().then(_openFromNotification);
    _notificationTapSub = FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification);
  }

  Future<void> _openFromNotification(RemoteMessage? message) async {
    if (message == null) return;
    await _refresh();
    if (!mounted) return;
    final trip = _status?.activeTrip;
    if (trip != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripPage(api: widget.api, trip: trip),
      ));
      _refresh();
    }
  }

  Future<void> _startLocationSharing() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    } catch (_) {
      return;
    }
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _shareLocation());
    _shareLocation();
  }

  Future<void> _shareLocation() async {
    if (_locationBusy) return;
    _locationBusy = true;
    try {
      final position = await Geolocator.getCurrentPosition();
      await widget.api.updateLocation(position.latitude, position.longitude);
    } catch (_) {
      // best-effort; retry on the next tick
    } finally {
      _locationBusy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationTimer?.cancel();
    _notificationTapSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    try {
      final results = await Future.wait([widget.api.status(), widget.api.earnings(), widget.api.shift()]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as DriverStatus;
        _earnings = results[1] as DriverEarnings;
        _shift = results[2] as DriverShift;
        if (!quiet) _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Connection problem. Retrying…');
    }
  }

  Future<void> _toggleOnline(bool online) async {
    setState(() => _busy = true);
    try {
      final status = await widget.api.setOnline(online);
      if (!mounted) return;
      setState(() { _status = status; _busy = false; });
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _accept(DriverOffer offer) async {
    setState(() => _busy = true);
    try {
      final trip = await widget.api.acceptOffer(offer.id);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TripPage(api: widget.api, trip: trip),
      ));
      _refresh();
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _decline(DriverOffer offer) async {
    setState(() => _busy = true);
    try {
      final status = await widget.api.rejectOffer(offer.id);
      if (!mounted) return;
      setState(() { _status = status; _busy = false; });
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _resumeTrip() async {
    final trip = _status?.activeTrip;
    if (trip == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripPage(api: widget.api, trip: trip),
    ));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final offer = status?.offers.isNotEmpty == true ? status!.offers.first : null;
    final trip = status?.activeTrip;
    final online = status?.online == true;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const UkoMap(hero: true),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: online ? const Color(0xFF08222B) : Colors.white, borderRadius: BorderRadius.circular(24)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? const Color(0xFF4ADE80) : const Color(0xFF8A9DA2), shape: BoxShape.circle)),
                          const SizedBox(width: 7),
                          Text(online ? 'Online' : 'Offline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: online ? Colors.white : const Color(0xFF2A4048))),
                        ]),
                      ),
                      const Spacer(),
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(24)),
                        child: IconButton(
                          tooltip: 'Notifications',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.notifications_none, size: 19, color: Color(0xFF08222B)),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverNotificationsPage(api: widget.api))),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(24)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 15, color: Color(0xFF0C8C86)),
                          const SizedBox(width: 6),
                          Text('KES ${_earnings?.today.net ?? 0} today', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2A4048))),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Account',
                        onSelected: (value) async {
                          if (value == 'signout') {
                            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SignInPage()));
                          } else if (value == 'documents') {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverDocumentsPage(api: widget.api)));
                          } else if (value == 'report') {
                            await reportClientError('driver', 'Pilot diagnostic sent from driver app', StackTrace.current, token: widget.api.accessToken);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostic sent to the Uko? team')));
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'documents', child: Text('Documents')),
                          PopupMenuItem(value: 'report', child: Text('Report a problem')),
                          PopupMenuItem(value: 'signout', child: Text('Sign out')),
                        ],
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF0C8C86),
                          child: Text(widget.session.phone.length >= 4 ? widget.session.phone.substring(widget.session.phone.length - 4) : 'UK',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        boxShadow: [BoxShadow(color: Color(0x2208222B), blurRadius: 24, offset: Offset(0, -6))],
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFDCE7E6), borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Hi ${widget.session.phone}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  Text(status?.online == true ? 'You are online' : 'You are offline',
                                      key: const Key('driver_status'),
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                                ]),
                              ),
                              Switch(
                                key: const Key('online_switch'),
                                value: online,
                                onChanged: _busy ? null : _toggleOnline,
                                activeColor: const Color(0xFF0C8C86),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            Text(_error!, style: const TextStyle(color: Color(0xFFB3261E), fontSize: 11)),
                          ],
                          const SizedBox(height: 10),
                          if (status == null)
                            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                          else if (trip != null)
                            _ActiveTripCard(trip: trip, onResume: _resumeTrip)
                          else if (offer != null)
                            _OfferCard(offer: offer, busy: _busy, onAccept: () => _accept(offer), onDecline: () => _decline(offer))
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                              decoration: BoxDecoration(color: const Color(0xFFF6FAF9), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE4EEEC))),
                              child: Column(children: [
                                Icon(online ? Icons.radar : Icons.wifi_tethering_off, size: 34, color: const Color(0xFF8A9DA2)),
                                const SizedBox(height: 8),
                                Text(online ? 'Waiting for ride offers…' : 'Go online to start receiving offers',
                                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 3),
                                Text(online ? 'Nearby Boda requests will appear here.' : 'You can go offline at any time.',
                                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ]),
                            ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [
                              const Icon(Icons.timer_outlined, size: 18, color: Color(0xFF0C8C86)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _shift == null
                                      ? 'Loading shift…'
                                      : _shift!.online
                                          ? 'On shift · ${_fmtDuration(_shift!.onlineMinutesToday)} online today'
                                          : 'Off shift · ${_fmtDuration(_shift!.onlineMinutesToday)} online today',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                              Text('${_shift?.tripsToday ?? 0} trips', style: const TextStyle(fontSize: 11, color: Color(0xFF5C7077))),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFF6FAF9), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE4EEEC))),
                            child: Row(children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.account_balance_wallet_outlined, size: 19, color: Color(0xFF0C8C86)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Text("Today's earnings", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_earnings?.today.trips ?? 0} trips · net KES ${_earnings?.today.net ?? 0} · commission ${_earnings?.commissionPercent ?? 20}%',
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  ),
                                ]),
                              ),
                              Text('KES ${_earnings?.today.net ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0C8C86), fontSize: 14)),
                            ]),
                          ),
                          const SizedBox(height: 4),
                          Center(child: Text('Boda pilot · weekly manual payouts', style: TextStyle(fontSize: 10, color: Colors.grey.shade500))),
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
    );
  }
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({required this.offer, required this.busy, required this.onAccept, required this.onDecline});
  final DriverOffer offer;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  static const _window = 45;
  int _remaining = _window;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _reset(widget.offer.id);
  }

  @override
  void didUpdateWidget(covariant _OfferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.id != widget.offer.id) _reset(widget.offer.id);
  }

  void _reset(String id) {
    _remaining = _window;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF0C8C86), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 44, height: 44,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: _remaining / _window,
                strokeWidth: 4,
                backgroundColor: const Color(0xFFE4EEEC),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0C8C86)),
              ),
              Text('$_remaining', key: const Key('offer_countdown'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('New Boda offer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text('KES ${widget.offer.fare}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF0C8C86))),
        ]),
        const SizedBox(height: 10),
        Text(widget.offer.riderName, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _StopRow(icon: Icons.trip_origin, label: widget.offer.pickupAddress, note: '${widget.offer.etaMin} min away'),
        const SizedBox(height: 6),
        _StopRow(icon: Icons.place_outlined, label: widget.offer.dropoffAddress, note: '${widget.offer.distanceKm.toStringAsFixed(1)} km · ${widget.offer.durationMin} min'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('decline_offer'),
              onPressed: widget.busy ? null : widget.onDecline,
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const Key('accept_offer'),
              onPressed: widget.busy ? null : widget.onAccept,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Accept'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.icon, required this.label, required this.note});
  final IconData icon;
  final String label;
  final String note;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 18, color: const Color(0xFF0C8C86)),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(note, style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
    ])),
  ]);
}

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({required this.trip, required this.onResume});
  final DriverTrip trip;
  final VoidCallback onResume;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFDCE7E6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Active trip', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text('${trip.riderName} · ${trip.state}'),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: onResume, child: const Text('Continue trip'))),
      ]),
    );
  }
}

class TripPage extends StatefulWidget {
  const TripPage({super.key, required this.api, required this.trip});
  final ApiClient api;
  final DriverTrip trip;
  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  late DriverTrip _trip = widget.trip;
  RouteResult? _route;
  int? _etaMin;
  Timer? _etaTimer;
  Timer? _statusTimer;
  bool _busy = false;
  bool _cancelNotified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoute();
    _updateEta();
    _etaTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updateEta());
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) => _watchRideCancellation());
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _watchRideCancellation() async {
    if (_cancelNotified) return;
    try {
      final status = await widget.api.status();
      if (!mounted) return;
      final active = status.activeTrip;
      if (active == null || active.id != _trip.id || active.state == 'CANCELLED') {
        _cancelNotified = true;
        _statusTimer?.cancel();
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Ride cancelled'),
            content: const Text('The rider cancelled this ride. Dispatch can also cancel rides. You will not be charged.'),
            actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Back to home'))],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  Future<void> _updateEta() async {
    final lat = _trip.state == 'IN_PROGRESS' ? _trip.dropoffLat : _trip.pickupLat;
    final lng = _trip.state == 'IN_PROGRESS' ? _trip.dropoffLng : _trip.pickupLng;
    if (lat == null || lng == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      final route = await widget.api.getRoute(
        pickupLat: pos.latitude, pickupLng: pos.longitude,
        dropoffLat: lat, dropoffLng: lng,
      );
      if (mounted) setState(() => _etaMin = route.durationMin);
    } catch (_) {}
  }

  Future<void> _loadRoute() async {
    final trip = _trip;
    if (trip.pickupLat == null || trip.dropoffLat == null) return;
    try {
      final route = await widget.api.getRoute(
        pickupLat: trip.pickupLat!, pickupLng: trip.pickupLng!,
        dropoffLat: trip.dropoffLat!, dropoffLng: trip.dropoffLng!,
      );
      if (mounted) setState(() => _route = route);
    } catch (_) {}
  }

  Future<String?> _askPickupCode() async {
    final controller = TextEditingController();
    String? validation;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Verify rider pickup code'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ask the rider for the 4-digit pickup code shown on their app.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pickup_code_input'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(labelText: 'Pickup code', counterText: '', errorText: validation),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _cancelRideByDriver();
              },
              child: const Text('Cancel ride', style: TextStyle(color: Color(0xFFB3261E))),
            ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Back')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (!RegExp(r'^\d{4}$').hasMatch(value)) {
                  setDialogState(() => validation = 'Enter the 4-digit code');
                  return;
                }
                Navigator.of(ctx).pop(value);
              },
              child: const Text('Verify & start'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    return code;
  }

  Future<void> _cancelRideByDriver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text('The rider will be notified and the request will appear as cancelled for dispatch. Use this if you cannot verify the pickup code or the rider is unavailable.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep ride')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.cancelTrip(_trip.id, reason: 'Driver could not verify pickup code / rider unavailable');
      if (!mounted) return;
      _statusTimer?.cancel();
      _cancelNotified = true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ride cancelled'),
          content: const Text('The ride was cancelled and dispatch has been notified.'),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Back to home'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _advance(String action) async {
    String? pickupCode;
    if (action == 'start') {
      pickupCode = await _askPickupCode();
      if (pickupCode == null) return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final trip = await widget.api.tripAction(_trip.id, action, pickupCode: pickupCode);
      if (!mounted) return;
      setState(() { _trip = trip; _busy = false; });
      if (trip.state == 'IN_PROGRESS') {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DriverNavigationPage(api: widget.api, trip: trip),
        ));
        return;
      }
      if (trip.state == 'COMPLETED') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Trip completed'),
            content: Text('KES ${trip.fare} fare recorded for ${trip.riderName}.'),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done'))],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = e.message; });
      if (e.code == 'PICKUP_CODE_INVALID') {
        final cancel = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Incorrect pickup code'),
            content: const Text('The trip was not started. Ask the rider to read the code again, or cancel this ride.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Try again')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Cancel ride'),
              ),
            ],
          ),
        );
        if (cancel == true) await _cancelRideByDriver();
      }
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _navigate() async {
    if (_trip.state == 'IN_PROGRESS') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DriverNavigationPage(api: widget.api, trip: _trip),
      ));
      return;
    }
    final lat = _trip.pickupLat;
    final lng = _trip.pickupLng;
    if (lat == null || lng == null) return;
    final uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      final fallback = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving&dir_action=navigate');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = switch (_trip.state) {
      'ACCEPTED' => ('arrived', "I've arrived"),
      'ARRIVED' => ('start', 'Enter pickup code & start'),
      'IN_PROGRESS' => ('complete', 'Complete trip'),
      _ => (null, 'Completed'),
    };
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: Stack(children: [
                      Positioned.fill(child: UkoMap(
                        pickup: _trip.pickupAddress,
                        dropoff: _trip.dropoffAddress,
                        pickupPoint: _trip.pickupLat == null ? null : LatLng(_trip.pickupLat!, _trip.pickupLng!),
                        dropoffPoint: _trip.dropoffLat == null ? null : LatLng(_trip.dropoffLat!, _trip.dropoffLng!),
                        routePoints: _route?.points,
                      )),
                      Positioned(top: 8, right: 8, child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: IconButton(
                          key: const Key('driver_expand_map'),
                          tooltip: 'Open map',
                          icon: const Icon(Icons.fullscreen, size: 20),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RouteMapPage(
                              pickupAddress: _trip.pickupAddress,
                              dropoffAddress: _trip.dropoffAddress,
                              pickupPoint: _trip.pickupLat == null ? const LatLng(-1.2841, 36.8233) : LatLng(_trip.pickupLat!, _trip.pickupLng!),
                              dropoffPoint: _trip.dropoffLat == null ? const LatLng(-1.2657, 36.8075) : LatLng(_trip.dropoffLat!, _trip.dropoffLng!),
                              route: _route,
                            ),
                          )),
                        ),
                      )),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_trip.riderName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Ride state: ${_trip.state}', key: const Key('trip_state'), style: const TextStyle(color: Color(0xFF5C7077))),
                if (_etaMin != null)
                  Text(
                    _trip.state == 'IN_PROGRESS' ? '~$_etaMin min to drop-off' : '~$_etaMin min to pickup',
                    key: const Key('driver_trip_eta'),
                    style: const TextStyle(color: Color(0xFF0C8C86), fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 10),
                _TripTimeline(state: _trip.state),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFDCE7E6))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Rider verification', style: TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                    const SizedBox(height: 4),
                    const Text('Ask the rider for their 4-digit pickup code before starting the trip.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF41565D))),
                    const Divider(height: 26),
                    _StopRow(icon: Icons.trip_origin, label: _trip.pickupAddress, note: 'Pickup'),
                    const SizedBox(height: 10),
                    _StopRow(icon: Icons.place_outlined, label: _trip.dropoffAddress, note: 'Drop-off'),
                    const Divider(height: 26),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Fare', style: TextStyle(color: Color(0xFF5C7077))),
                      Text('KES ${_trip.fare}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    ]),
                  ]),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB3261E), fontSize: 12)),
                ],
                const SizedBox(height: 20),
                if (_trip.pickupLat != null || _trip.dropoffLat != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('navigate_button'),
                      onPressed: _navigate,
                      icon: const Icon(Icons.navigation_outlined),
                      label: Text(_trip.state == 'IN_PROGRESS' ? 'Navigate to drop-off' : 'Navigate to pickup'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('trip_action'),
                    onPressed: _busy || action.$1 == null ? null : () => _advance(action.$1!),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(action.$2),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverNavigationPage extends StatefulWidget {
  const DriverNavigationPage({super.key, required this.api, required this.trip});
  final ApiClient api;
  final DriverTrip trip;

  @override
  State<DriverNavigationPage> createState() => _DriverNavigationPageState();
}

class _DriverNavigationPageState extends State<DriverNavigationPage> {
  final MapController _map = MapController();
  RouteResult? _route;
  LatLng? _position;
  Timer? _timer;
  bool _busy = false;
  bool _fitted = false;

  LatLng get _destination => LatLng(widget.trip.dropoffLat ?? -1.0333, widget.trip.dropoffLng ?? 37.0693);

  @override
  void initState() {
    super.initState();
    _refreshNavigation();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refreshNavigation());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshNavigation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final route = await widget.api.getRoute(
        pickupLat: pos.latitude,
        pickupLng: pos.longitude,
        dropoffLat: _destination.latitude,
        dropoffLng: _destination.longitude,
      );
      if (!mounted) return;
      setState(() {
        _position = LatLng(pos.latitude, pos.longitude);
        _route = route;
      });
      if (!_fitted) {
        _fitted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
      }
    } catch (_) {
      // Keep the last known route; retry on the next tick.
    }
  }

  void _fitRoute() {
    final route = _route;
    if (route == null || route.points.isEmpty) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([...route.points, if (_position != null) _position!]),
      padding: const EdgeInsets.only(top: 120, bottom: 300, left: 40, right: 40),
      maxZoom: 16,
    ));
  }

  Future<void> _openGoogleMaps() async {
    final dest = _destination;
    final origin = _position;
    final nav = Uri.parse('google.navigation:q=${dest.latitude},${dest.longitude}&mode=d');
    var launched = false;
    try {
      launched = await launchUrl(nav, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (launched) return;
    final web = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '${origin == null ? '' : '&origin=${origin.latitude},${origin.longitude}'}'
      '&destination=${dest.latitude},${dest.longitude}&travelmode=driving&dir_action=navigate',
    );
    if (!await launchUrl(web, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google Maps could not be opened')));
    }
  }

  Future<void> _completeTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete trip?'),
        content: Text('Finish the trip for ${widget.trip.riderName} at ${widget.trip.dropoffAddress}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep navigating')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Complete trip')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final trip = await widget.api.tripAction(widget.trip.id, 'complete');
      if (!mounted) return;
      _timer?.cancel();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trip completed'),
          content: Text('KES ${trip.fare} recorded. Net after 20% commission: KES ${(trip.fare * 0.8).round()}.'),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not complete trip: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final nextStep = route?.steps.isNotEmpty == true ? route!.steps.first.instruction : 'Follow the route to the drop-off';
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _destination,
            initialZoom: 14,
            initialCameraFit: _position == null ? null : CameraFit.bounds(
              bounds: LatLngBounds.fromPoints([_position!, _destination]),
              padding: const EdgeInsets.only(top: 120, bottom: 300, left: 40, right: 40),
              maxZoom: 16,
            ),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ke.uko.driver', maxZoom: 19),
            if (route != null)
              PolylineLayer(polylines: [Polyline(points: route.points, strokeWidth: 6, color: const Color(0xFF0C8C86))]),
            MarkerLayer(markers: [
              Marker(point: _destination, width: 48, height: 48, child: const Icon(Icons.location_on, color: Color(0xFFB3261E), size: 38)),
              if (_position != null)
                Marker(point: _position!, width: 54, height: 54, child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF08222B), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                  child: const Icon(Icons.two_wheeler, color: Colors.white, size: 28),
                )),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Material(color: Colors.white, shape: const CircleBorder(), child: IconButton(
              key: const Key('nav_exit'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            )),
            const SizedBox(width: 10),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Text(route == null ? 'Starting navigation…' : '${route.distanceKm} km · ${route.durationMin} min',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            )),
          ]),
        )),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.turn_right, color: Color(0xFF0C8C86), size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(nextStep, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 12),
            Text('To ${widget.trip.dropoffAddress}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('nav_google_maps'),
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Navigate with Google Maps'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('nav_complete_trip'),
                onPressed: _busy ? null : _completeTrip,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Complete trip'),
              ),
            ),
          ]),
        )),
      ]),
    );
  }
}

class _TripTimeline extends StatelessWidget {
  const _TripTimeline({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    const steps = ['ACCEPTED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED'];
    const labels = ['Accepted', 'Arrived', 'On trip', 'Done'];
    final current = steps.indexOf(state);
    return Row(children: [
      for (var i = 0; i < steps.length; i++) ...[
        Expanded(
          child: Column(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: i <= current ? const Color(0xFF0C8C86) : const Color(0xFFE4EEEC),
                shape: BoxShape.circle,
              ),
              child: i < current
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : i == current
                      ? const Icon(Icons.circle, size: 7, color: Colors.white)
                      : null,
            ),
            const SizedBox(height: 4),
            Text(labels[i], style: TextStyle(fontSize: 9, fontWeight: i == current ? FontWeight.w700 : FontWeight.w400, color: i <= current ? const Color(0xFF2A4048) : const Color(0xFF8A9DA2))),
          ]),
        ),
        if (i < steps.length - 1)
          Container(width: 18, height: 2, color: i < current ? const Color(0xFF0C8C86) : const Color(0xFFE4EEEC)),
      ],
    ]);
  }
}

class DriverMap extends StatelessWidget {
  const DriverMap({super.key, this.hero = false, this.pickup, this.dropoff});
  final bool hero;
  final String? pickup;
  final String? dropoff;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      CustomPaint(painter: _DriverMapPainter(hero: hero)),
      if (!hero && pickup != null && dropoff != null)
        Positioned(
          left: 12, right: 12, bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(11), boxShadow: const [BoxShadow(color: Color(0x1808222B), blurRadius: 8)]),
            child: Row(children: [
              const Icon(Icons.trip_origin, size: 14, color: Color(0xFF0C8C86)),
              const SizedBox(width: 5),
              Expanded(child: Text(pickup!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
              const Icon(Icons.arrow_forward, size: 12, color: Color(0xFF8A9DA2)),
              const SizedBox(width: 5),
              const Icon(Icons.place, size: 14, color: Color(0xFFB3261E)),
              const SizedBox(width: 3),
              Expanded(child: Text(dropoff!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
    ]);
  }
}

class _DriverMapPainter extends CustomPainter {
  _DriverMapPainter({required this.hero});
  final bool hero;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEAF2EE));
    final block = Paint()..color = const Color(0xFFF7FBF9);
    final edge = Paint()..color = const Color(0xFFDDE9E4)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (var i = 0; i < 6; i++) {
      for (var j = 0; j < 5; j++) {
        if ((i + j) % 4 == 0) continue;
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(24.0 + i * (size.width / 6), 24.0 + j * (size.height / 5), size.width / 6 - 18, size.height / 5 - 18),
          const Radius.circular(9),
        );
        canvas.drawRRect(r, block);
        canvas.drawRRect(r, edge);
      }
    }
    final road = Paint()..color = Colors.white..strokeWidth = 6..strokeCap = StrokeCap.round;
    final roadEdge = Paint()..color = const Color(0xFFD6E3DE)..strokeWidth = 10..strokeCap = StrokeCap.round;
    for (var i = 1; i < 4; i++) {
      final y = size.height * (0.2 + i * 0.2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadEdge);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    for (var i = 1; i < 4; i++) {
      final x = size.width * (i * 0.24);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadEdge);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
    final route = Paint()..color = const Color(0xFF0C8C86)..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.8)
      ..cubicTo(size.width * 0.35, size.height * 0.62, size.width * 0.5, size.height * 0.6, size.width * 0.62, size.height * 0.46)
      ..cubicTo(size.width * 0.74, size.height * 0.32, size.width * 0.8, size.height * 0.3, size.width * 0.86, size.height * 0.2);
    canvas.drawPath(path, route);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.8), 8, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.8), 5, Paint()..color = const Color(0xFF0C8C86));
    _pin(canvas, Offset(size.width * 0.86, size.height * 0.2), const Color(0xFFB3261E));
    if (hero) {
      final text = TextPainter(
        text: const TextSpan(text: 'Thika · driver', style: TextStyle(fontSize: 10, color: Color(0xFF7A918A), fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(20, size.height - 24));
    }
  }

  void _pin(Canvas canvas, Offset c, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy + 11)
      ..cubicTo(c.dx - 11, c.dy - 4, c.dx - 8, c.dy - 15, c.dx, c.dy - 15)
      ..cubicTo(c.dx + 8, c.dy - 15, c.dx + 11, c.dy - 4, c.dx, c.dy + 11)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(Offset(c.dx, c.dy - 6), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DriverMapPainter oldDelegate) => oldDelegate.hero != hero;
}


String _fmtDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}


class DriverNotificationsPage extends StatefulWidget {
  const DriverNotificationsPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<DriverNotificationsPage> createState() => _DriverNotificationsPageState();
}

class _DriverNotificationsPageState extends State<DriverNotificationsPage> {
  List<DriverNotification> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.api.notifications();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _when(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UkoTopBar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load notifications: $_error'))])
                : _items.isEmpty
                    ? ListView(children: const [
                        Padding(padding: EdgeInsets.all(40), child: Column(children: [
                          Icon(Icons.notifications_none, size: 44, color: Color(0xFF8A9DA2)),
                          SizedBox(height: 12),
                          Text('No notifications yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Trip updates and earnings will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF5C7077))),
                        ])),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE4EEEC))),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.notifications_active_outlined, size: 20, color: Color(0xFF0C8C86)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                  Text(_when(item.createdAt), style: const TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
                                ]),
                                const SizedBox(height: 3),
                                Text(item.body, style: const TextStyle(fontSize: 12.5, color: Color(0xFF41565D), height: 1.35)),
                              ])),
                            ]),
                          );
                        },
                      ),
      ),
    );
  }
}

class DriverDocumentsPage extends StatefulWidget {
  const DriverDocumentsPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<DriverDocumentsPage> createState() => _DriverDocumentsPageState();
}

class _DriverDocumentsPageState extends State<DriverDocumentsPage> {
  List<DriverDocument> _items = [];
  bool _loading = true;
  String? _error;
  String? _uploading;
  String _docType = 'licence';

  Future<void> _pick(ImageSource source) async {
    setState(() { _uploading = source == ImageSource.camera ? 'camera' : 'gallery'; });
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      if (picked == null) {
        if (mounted) setState(() { _uploading = null; });
        return;
      }
      await widget.api.uploadDocumentFile(_docType, picked.path, picked.name);
      await _load();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _uploading = null; });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.api.documents();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _upload(String type) async {
    setState(() { _uploading = type; });
    try {
      await widget.api.uploadDocument(type);
      await _load();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _uploading = null; });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED': return const Color(0xFF0C8C86);
      case 'REJECTED': return const Color(0xFFB3261E);
      default: return const Color(0xFFB26A00);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UkoTopBar(actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text('Driver verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('Upload your licence and insurance. Ops reviews them before you can go online during the pilot.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF5C7077))),
                      const SizedBox(height: 16),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                        const SizedBox(height: 10),
                      ],
                      if (_items.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                          child: const Text('No documents uploaded yet. Add your licence and insurance to start the vetting flow.'),
                        )
                      else
                        for (final doc in _items)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                            child: Row(children: [
                              const Icon(Icons.description_outlined, color: Color(0xFF0C8C86)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(doc.type.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(doc.fileName ?? 'Uploaded document', style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: _statusColor(doc.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(doc.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _statusColor(doc.status))),
                              ),
                            ]),
                          ),
                      const SizedBox(height: 16),
                      const Text('Add document', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'licence', label: Text('Licence'), icon: Icon(Icons.badge_outlined, size: 16)),
                          ButtonSegment(value: 'insurance', label: Text('Insurance'), icon: Icon(Icons.shield_outlined, size: 16)),
                          ButtonSegment(value: 'vehicle_photo', label: Text('Vehicle'), icon: Icon(Icons.two_wheeler_outlined, size: 16)),
                        ],
                        selected: {_docType},
                        onSelectionChanged: (selection) => setState(() => _docType = selection.first),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: FilledButton.icon(
                          onPressed: _uploading == null ? () => _pick(ImageSource.camera) : null,
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(_uploading == 'camera' ? 'Uploading…' : 'Take photo'),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(
                          onPressed: _uploading == null ? () => _pick(ImageSource.gallery) : null,
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: Text(_uploading == 'gallery' ? 'Uploading…' : 'Gallery'),
                        )),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, children: [
                        TextButton(onPressed: _uploading == null ? () => _upload('licence') : null, child: const Text('Demo licence')),
                        TextButton(onPressed: _uploading == null ? () => _upload('insurance') : null, child: const Text('Demo insurance')),
                      ]),
                      const SizedBox(height: 6),
                      const Text('Camera/gallery photos are uploaded as-is for ops review. Demo buttons are for bench testing only.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}


bool _pushStarted = false;
Future<void> registerPushForApi(ApiClient api) async {
  if (_pushStarted) return;
  _pushStarted = true;
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token == null) return;
    await api.registerDevice(token);
    FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
      api.registerDevice(refreshed);
    });
  } catch (e) {
    debugPrint('Push registration skipped: $e');
  }
}


const bool kRealMapsEnabled = bool.fromEnvironment('UKO_REAL_MAPS', defaultValue: true);
const _ukoPickup = LatLng(-1.0333, 37.0693);
const _ukoDropoff = LatLng(-1.0408, 37.0910);

/// Real Google map when built with `--dart-define=UKO_REAL_MAPS=true` and a
/// Maps API key configured; otherwise falls back to the offline stylised map.
class UkoMap extends StatefulWidget {
  const UkoMap({super.key, this.hero = false, this.pickup, this.dropoff, this.pickupPoint, this.dropoffPoint, this.routePoints});
  final bool hero;
  final String? pickup;
  final String? dropoff;
  final LatLng? pickupPoint;
  final LatLng? dropoffPoint;
  final List<LatLng>? routePoints;

  @override
  State<UkoMap> createState() => _UkoMapState();
}

class _UkoMapState extends State<UkoMap> {
  bool? _online;
  Timer? _netTimer;

  @override
  void initState() {
    super.initState();
    _checkOnline();
    _netTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkOnline());
  }

  @override
  void dispose() {
    _netTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkOnline() async {
    var online = false;
    try {
      final result = await InternetAddress.lookup('tile.openstreetmap.org').timeout(const Duration(seconds: 3));
      online = result.isNotEmpty;
    } catch (_) {
      online = false;
    }
    if (mounted) setState(() => _online = online);
  }

  Widget _fallback() => DriverMap(hero: widget.hero, pickup: widget.pickup, dropoff: widget.dropoff);

  @override
  Widget build(BuildContext context) {
    final offline = _online == false;
    if (!kRealMapsEnabled || offline) {
      return Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: _fallback()),
        if (offline)
          Positioned(
            top: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off, size: 14, color: Color(0xFFB3261E)),
                SizedBox(width: 6),
                Text('Offline map', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB3261E))),
              ]),
            ),
          ),
      ]);
    }
    final start = widget.pickupPoint ?? _ukoPickup;
    final end = widget.dropoffPoint ?? _ukoDropoff;
    final routePoints = widget.routePoints;
    return Stack(fit: StackFit.expand, children: [
      FlutterMap(
        key: ValueKey('${start.latitude},${start.longitude}-${end.latitude},${end.longitude}-${routePoints?.length ?? 0}'),
        options: MapOptions(
          initialCenter: LatLng((start.latitude + end.latitude) / 2, (start.longitude + end.longitude) / 2),
          initialZoom: 12.5,
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([...?routePoints, start, end]),
            padding: const EdgeInsets.all(28),
            maxZoom: 14.5,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'ke.uko.driver',
            maxZoom: 19,
          ),
          if (routePoints != null)
            PolylineLayer(polylines: [
              Polyline(points: routePoints, strokeWidth: 4, color: const Color(0xFF0C8C86)),
            ]),
          if (!widget.hero || routePoints != null || widget.pickupPoint != null || widget.dropoffPoint != null)
            MarkerLayer(markers: [
              Marker(point: start, width: 44, height: 44, child: const Icon(Icons.trip_origin, color: Color(0xFF0C8C86), size: 30)),
              Marker(point: end, width: 44, height: 44, child: const Icon(Icons.location_on, color: Color(0xFFB3261E), size: 34)),
            ]),
          RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
      if (!widget.hero && widget.pickupPoint != null && widget.dropoffPoint != null && routePoints == null)
        Positioned(
          top: 10, left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Calculating route…', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      if (!widget.hero && widget.pickup != null && widget.dropoff != null)
        Positioned(
          left: 12, right: 12, bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(20)),
            child: Text('${widget.pickup} → ${widget.dropoff}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
    ]);
  }
}


class RouteMapPage extends StatefulWidget {
  const RouteMapPage({super.key, required this.pickupAddress, required this.dropoffAddress, required this.pickupPoint, required this.dropoffPoint, this.route});
  final String pickupAddress;
  final String dropoffAddress;
  final LatLng pickupPoint;
  final LatLng dropoffPoint;
  final RouteResult? route;
  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  final MapController _map = MapController();
  static const _zoom = 13.5;

  @override
  Widget build(BuildContext context) {
    final start = widget.pickupPoint, end = widget.dropoffPoint;
    final center = LatLng((start.latitude + end.latitude) / 2, (start.longitude + end.longitude) / 2);
    final route = widget.route;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _zoom,
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(route?.points ?? [start, end]),
              padding: const EdgeInsets.only(top: 170, bottom: 340, left: 30, right: 30),
              maxZoom: 15,
            ),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ke.uko.driver', maxZoom: 19),
            PolylineLayer(polylines: [Polyline(points: route?.points ?? const [], strokeWidth: 5, color: const Color(0xFF0C8C86))]),
            MarkerLayer(markers: [
              Marker(point: start, width: 46, height: 46, child: const Icon(Icons.trip_origin, color: Color(0xFF0C8C86), size: 32)),
              Marker(point: end, width: 46, height: 46, child: const Icon(Icons.location_on, color: Color(0xFFB3261E), size: 36)),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Material(color: Colors.white, shape: const CircleBorder(), child: IconButton(
              key: const Key('driver_map_back'), icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop())),
            const SizedBox(width: 10),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Text(route == null ? 'Calculating route…' : '${route.distanceKm} km · about ${route.durationMin} min',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), overflow: TextOverflow.ellipsis),
            )),
          ]),
        )),
        Positioned(top: 90, left: 12, right: 90, child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.97), borderRadius: BorderRadius.circular(16)),
          child: Text('${widget.pickupAddress} → ${widget.dropoffAddress}', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
        )),
        Positioned(right: 12, bottom: 340, child: Column(children: [
          Material(color: Colors.white, shape: const CircleBorder(), child: IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => _map.move(_map.camera.center, _map.camera.zoom + 1))),
          const SizedBox(height: 8),
          Material(color: Colors.white, shape: const CircleBorder(), child: IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: () => _map.move(_map.camera.center, _map.camera.zoom - 1))),
        ])),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          constraints: const BoxConstraints(maxHeight: 330),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.alt_route, size: 18, color: Color(0xFF0C8C86)),
              const SizedBox(width: 8),
              const Text('Directions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              Text(route == null ? '' : '${route.steps.length} steps', style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
            ]),
            const SizedBox(height: 8),
            Flexible(child: route == null || route.steps.isEmpty
                ? const Text('Directions unavailable for this trip.', style: TextStyle(color: Color(0xFF5C7077)))
                : ListView.builder(shrinkWrap: true, itemCount: route.steps.length, itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      const Icon(Icons.turn_right, size: 16, color: Color(0xFF0C8C86)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(route.steps[i].instruction, style: const TextStyle(fontSize: 13))),
                      Text(route.steps[i].distanceM >= 1000 ? '${(route.steps[i].distanceM / 1000).toStringAsFixed(1)} km' : '${route.steps[i].distanceM} m',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                    ]),
                  ))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              key: const Key('driver_open_google_maps'),
              onPressed: () async {
                final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${end.latitude},${end.longitude}&travelmode=driving');
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Open in Google Maps'),
            )),
          ]),
        )),
      ]),
    );
  }
}
