import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, InternetAddress;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Local API base. On the Lenovo test bench the workstation API is exposed
/// through `adb reverse tcp:3000 tcp:3000`.
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
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        reportClientError('rider', details.exceptionAsString(), details.stack);
      };
      runApp(const UkoApp());
      unawaited(_initFirebase());
    },
    (error, stack) => reportClientError('rider', error.toString(), stack),
  );
}

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground: ${message.notification?.title}');
    });
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
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

class UkoApp extends StatelessWidget {
  const UkoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0C8C86);
    return MaterialApp(
      title: 'Uko? Rider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light, surface: Colors.white),
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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF08222B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
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

const MethodChannel _calendarChannel = MethodChannel('ke.uko.rider/calendar');

class CalendarSuggestion {
  CalendarSuggestion({required this.title, required this.start, required this.location});
  final String title;
  final DateTime start;
  final String location;

  factory CalendarSuggestion.fromMap(Map<dynamic, dynamic> m) => CalendarSuggestion(
    title: (m['title'] ?? '') as String,
    start: DateTime.fromMillisecondsSinceEpoch((m['startMillis'] as num).toInt()),
    location: (m['location'] ?? '') as String,
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

class UkoNotification {
  UkoNotification({required this.id, required this.title, required this.body, required this.status, this.createdAt});
  final String id;
  final String title;
  final String body;
  final String status;
  final DateTime? createdAt;

  factory UkoNotification.fromJson(Map<String, dynamic> j) => UkoNotification(
    id: (j['id'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    body: (j['body'] ?? '') as String,
    status: (j['status'] ?? '') as String,
    createdAt: j['createdAt'] == null ? null : DateTime.tryParse(j['createdAt'] as String)?.toLocal(),
  );
}

class OtpRequestResult {
  OtpRequestResult({required this.sent, required this.expiresInSeconds, this.devCode});
  final bool sent;
  final int expiresInSeconds;
  final String? devCode;
}

class PlaceSuggestion {
  const PlaceSuggestion({required this.id, required this.name, required this.address, required this.lat, required this.lng});
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) => PlaceSuggestion(
        id: (json['id'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        address: (json['address'] ?? '') as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}

class RouteStep {
  const RouteStep({required this.instruction, required this.distanceM, required this.type, required this.modifier, required this.name});
  final String instruction;
  final int distanceM;
  final String type;
  final String modifier;
  final String name;

  factory RouteStep.fromJson(Map<String, dynamic> j) => RouteStep(
        instruction: (j['instruction'] ?? '') as String,
        distanceM: (j['distanceM'] as num?)?.toInt() ?? 0,
        type: (j['type'] ?? '') as String,
        modifier: (j['modifier'] ?? '') as String,
        name: (j['name'] ?? '') as String,
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

class DriverLocation {
  const DriverLocation({required this.lat, required this.lng, required this.updatedAt});
  final double lat;
  final double lng;
  final String updatedAt;

  factory DriverLocation.fromJson(Map<String, dynamic> j) => DriverLocation(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        updatedAt: (j['updatedAt'] ?? '') as String,
      );
}

class SavedPlace {
  const SavedPlace({required this.label, required this.address, required this.lat, required this.lng});
  final String label;
  final String address;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'label': label, 'address': address, 'lat': lat, 'lng': lng};
  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
        label: (j['label'] ?? '') as String,
        address: (j['address'] ?? '') as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}

class SavedPlacesStore {
  static const _key = 'uko_saved_places_v1';
  static const defaults = <SavedPlace>[
    SavedPlace(label: 'Home', address: 'Makongeni, Thika', lat: -1.0330, lng: 37.0550),
    SavedPlace(label: 'Work', address: 'Thika Town', lat: -1.0333, lng: 37.0693),
    SavedPlace(label: 'Airport', address: 'JKIA Terminal 1A', lat: -1.3169, lng: 36.9289),
    SavedPlace(label: 'Mall', address: 'Ananas Mall, Thika', lat: -1.0408, lng: 37.0910),
  ];

  static Future<List<SavedPlace>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return List.of(defaults);
    try {
      final list = (jsonDecode(raw) as List).map((e) => SavedPlace.fromJson((e as Map).cast<String, dynamic>())).toList();
      return list.isEmpty ? List.of(defaults) : list;
    } catch (_) {
      return List.of(defaults);
    }
  }

  static Future<void> add(SavedPlace place) async {
    final places = await load();
    final without = places.where((p) => !(p.label.toLowerCase() == place.label.toLowerCase())).toList();
    without.insert(0, place);
    await _write(without.take(12).toList());
  }

  static Future<void> remove(String label) async {
    final places = await load();
    await _write(places.where((p) => p.label.toLowerCase() != label.toLowerCase()).toList());
  }

  static Future<void> update(SavedPlace place, String newLabel) async {
    final places = await load();
    final updated = places
        .map((p) => p.label.toLowerCase() == place.label.toLowerCase()
            ? SavedPlace(label: newLabel, address: place.address, lat: place.lat, lng: place.lng)
            : p)
        .toList();
    await _write(updated);
  }

  static Future<void> _write(List<SavedPlace> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(places.map((p) => p.toJson()).toList()));
  }
}

class AuthSession {
  AuthSession({required this.accessToken, required this.refreshToken, required this.user});
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> user;

  String get phone => (user['phone'] ?? '') as String;
  String get userId => (user['id'] ?? '') as String;
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
    final uri = Uri.parse('$baseUrl$path');
    final response = await _client
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
    final response = await _client
        .patch(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final response = await _client
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path, [String? token]) async {
    final uri = Uri.parse('$baseUrl$path');
    final bearer = token ?? accessToken;
    final response = await _client.get(uri, headers: {
      if (bearer != null) 'authorization': 'Bearer $bearer',
    }).timeout(const Duration(seconds: 15));
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

  Future<void> registerDevice(String token) async {
    await _post('/notifications/devices', {'token': token, 'platform': 'android'});
  }

  Future<OtpRequestResult> requestOtp(String phone) async {
    final json = await _post('/auth/otp/request', {'phone': phone});
    return OtpRequestResult(
      sent: json['sent'] == true,
      expiresInSeconds: (json['expiresInSeconds'] ?? 300) as int,
      devCode: json['dev_code'] as String?,
    );
  }

  Future<AuthSession> verifyOtp(String phone, String code) async {
    final json = await _post('/auth/otp/verify', {'phone': phone, 'code': code});
    final tokens = (json['tokens'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    return AuthSession(
      accessToken: (tokens['accessToken'] ?? '') as String,
      refreshToken: (tokens['refreshToken'] ?? '') as String,
      user: (json['user'] ?? <String, dynamic>{}) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> me(String accessToken) async {
    this.accessToken = accessToken;
    final json = await _get('/me');
    return (json['user'] ?? <String, dynamic>{}) as Map<String, dynamic>;
  }

  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final json = await _get('/places/search?q=${Uri.encodeQueryComponent(query)}');
    return ((json['places'] as List?) ?? [])
        .map((e) => PlaceSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlaceSuggestion?> reverseGeocode(double lat, double lng) async {
    final json = await _get('/places/reverse?lat=$lat&lng=$lng');
    final place = json['place'];
    if (place is! Map) return null;
    return PlaceSuggestion.fromJson(place.cast<String, dynamic>());
  }

  Future<Quote> quote({
    required String pickupAddress,
    required String dropoffAddress,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final json = await _post('/quotes', {
      'pickup': {'lat': pickupLat, 'lng': pickupLng, 'address': pickupAddress},
      'dropoff': {'lat': dropoffLat, 'lng': dropoffLng, 'address': dropoffAddress},
    });
    return Quote.fromJson((json['quote'] as Map).cast<String, dynamic>());
  }

  Future<Ride> createRide(String quoteId, String paymentMethod) async {
    final json = await _post('/rides', {'quoteId': quoteId, 'paymentMethod': paymentMethod});
    return Ride.fromJson((json['ride'] as Map).cast<String, dynamic>());
  }

  Future<Ride> getRide(String id) async {
    final json = await _get('/rides/$id');
    return Ride.fromJson((json['ride'] as Map).cast<String, dynamic>());
  }

  Future<DriverLocation?> getDriverLocation(String rideId) async {
    final json = await _get('/rides/$rideId/driver-location');
    final raw = json['location'];
    if (raw is! Map) return null;
    return DriverLocation.fromJson(raw.cast<String, dynamic>());
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

  Future<Ride> cancelRide(String id, {String? reason, String? note}) async {
    final json = await _post('/rides/$id/cancel', {
      if (reason != null) 'reason': reason,
      if (note != null) 'note': note,
    });
    return Ride.fromJson((json['ride'] as Map).cast<String, dynamic>());
  }

  Future<ScheduledRide> scheduleRide({
    required String pickupAddress,
    required String dropoffAddress,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required DateTime scheduledAt,
    String paymentMethod = 'mpesa',
  }) async {
    final json = await _post('/scheduled-rides', {
      'pickup': {'lat': pickupLat, 'lng': pickupLng, 'address': pickupAddress},
      'dropoff': {'lat': dropoffLat, 'lng': dropoffLng, 'address': dropoffAddress},
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      'paymentMethod': paymentMethod,
    });
    return ScheduledRide.fromJson((json['scheduledRide'] as Map).cast<String, dynamic>());
  }

  Future<List<Ride>> rides() async {
    final json = await _get('/rides');
    return ((json['rides'] ?? []) as List)
        .map((e) => Ride.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> cancelScheduledRide(String id) async {
    await _post('/scheduled-rides/$id/cancel', const <String, dynamic>{});
  }

  Future<void> rateRide(String rideId, int rating) async {
    await _post('/ratings', {'rideId': rideId, 'rating': rating});
  }

  Future<List<UkoNotification>> notifications() async {
    final json = await _get('/notifications');
    return ((json['notifications'] as List?) ?? [])
        .map((e) => UkoNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ScheduledRide>> scheduledRides() async {
    final json = await _get('/scheduled-rides');
    return ((json['scheduledRides'] ?? []) as List)
        .map((e) => ScheduledRide.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<ScheduleSeries> repeatRide(String rideId, List<int> weekdays, DateTime endDate) async {
    final json = await _post('/scheduled-rides/$rideId/repeat', {
      'weekdays': weekdays,
      'endDate': endDate.toUtc().toIso8601String(),
    });
    return ScheduleSeries.fromJson((json['series'] as Map).cast<String, dynamic>());
  }

  Future<List<ScheduleSeries>> scheduleSeries() async {
    final json = await _get('/schedule-series');
    return ((json['series'] ?? []) as List)
        .map((e) => ScheduleSeries.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<ScheduleSeries> updateSeries(String id, String status) async {
    final json = await _patch('/schedule-series/$id', {'status': status});
    return ScheduleSeries.fromJson((json['series'] as Map).cast<String, dynamic>());
  }

  Future<Payment?> ridePayment(String rideId) async {
    final json = await _get('/payments/ride/$rideId');
    final payment = json['payment'];
    return payment == null ? null : Payment.fromJson((payment as Map).cast<String, dynamic>());
  }

  Future<Payment> requestMpesa(String rideId) async {
    final json = await _post('/payments/mpesa/stk', {'rideId': rideId});
    return Payment.fromJson((json['payment'] as Map).cast<String, dynamic>());
  }

  Future<Payment> confirmCash(String rideId) async {
    final json = await _post('/payments/cash/confirm', {'rideId': rideId});
    return Payment.fromJson((json['payment'] as Map).cast<String, dynamic>());
  }

  Future<Payment> getPayment(String id) async {
    final json = await _get('/payments/$id');
    return Payment.fromJson((json['payment'] as Map).cast<String, dynamic>());
  }

  Future<List<EmergencyContact>> safetyContacts() async {
    final json = await _get('/safety/contacts');
    return ((json['contacts'] ?? []) as List)
        .map((e) => EmergencyContact.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<EmergencyContact> addSafetyContact({required String name, required String phone, String? relationship}) async {
    final json = await _post('/safety/contacts', {
      'name': name,
      'phone': phone,
      if (relationship != null && relationship.isNotEmpty) 'relationship': relationship,
    });
    return EmergencyContact.fromJson((json['contact'] as Map).cast<String, dynamic>());
  }

  Future<void> removeSafetyContact(String id) async {
    await _delete('/safety/contacts/$id');
  }

  Future<SafetyIncident> triggerSos({String? rideId, String? note}) async {
    final json = await _post('/safety/sos', {
      if (rideId != null) 'rideId': rideId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return SafetyIncident.fromJson((json['incident'] as Map).cast<String, dynamic>());
  }

  Future<SafetyIncident> getIncident(String id) async {
    final json = await _get('/safety/incidents/$id');
    return SafetyIncident.fromJson((json['incident'] as Map).cast<String, dynamic>());
  }

  Future<SafetyIncident> cancelIncident(String id) async {
    final json = await _post('/safety/incidents/$id/cancel', const <String, dynamic>{});
    return SafetyIncident.fromJson((json['incident'] as Map).cast<String, dynamic>());
  }
}

class Quote {
  Quote({required this.id, required this.fare, required this.currency, required this.distanceKm,
    required this.durationMin, required this.breakdown, required this.pickupAddress, required this.dropoffAddress});
  final String id;
  final int fare;
  final String currency;
  final double distanceKm;
  final int durationMin;
  final Map<String, dynamic> breakdown;
  final String pickupAddress;
  final String dropoffAddress;

  factory Quote.fromJson(Map<String, dynamic> j) {
    final pickup = (j['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dropoff = (j['dropoff'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Quote(
      id: j['id'] as String,
      fare: (j['fare'] as num).toInt(),
      currency: (j['currency'] ?? 'KES') as String,
      distanceKm: (j['distanceKm'] as num).toDouble(),
      durationMin: (j['durationMin'] as num).toInt(),
      breakdown: (j['breakdown'] as Map?)?.cast<String, dynamic>() ?? const {},
      pickupAddress: (pickup['address'] ?? '') as String,
      dropoffAddress: (dropoff['address'] ?? '') as String,
    );
  }
}

class RideDriver {
  RideDriver({required this.name, required this.vehicle, required this.plate, required this.rating, required this.etaMin});
  final String name;
  final String vehicle;
  final String plate;
  final double rating;
  final int etaMin;

  factory RideDriver.fromJson(Map<String, dynamic> j) => RideDriver(
    name: (j['name'] ?? '') as String,
    vehicle: (j['vehicle'] ?? '') as String,
    plate: (j['plate'] ?? '') as String,
    rating: (j['rating'] as num?)?.toDouble() ?? 0,
    etaMin: (j['etaMin'] as num?)?.toInt() ?? 0,
  );
}

class Ride {
  Ride({required this.id, required this.state, required this.fare, required this.currency,
    required this.paymentMethod, required this.pickupAddress, required this.dropoffAddress,
    required this.createdAt, this.pickupCode, this.driver,
    this.pickupLat, this.pickupLng, this.dropoffLat, this.dropoffLng, this.cancellationLabel});
  final String id;
  final String state;
  final int fare;
  final String currency;
  final String paymentMethod;
  final String pickupAddress;
  final String dropoffAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final DateTime createdAt;
  final String? pickupCode;
  final RideDriver? driver;
  final String? cancellationLabel;

  factory Ride.fromJson(Map<String, dynamic> j) {
    final pickup = (j['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dropoff = (j['dropoff'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Ride(
      id: j['id'] as String,
      state: (j['state'] ?? '') as String,
      fare: (j['fare'] as num).toInt(),
      currency: (j['currency'] ?? 'KES') as String,
      paymentMethod: (j['paymentMethod'] ?? 'mpesa') as String,
      pickupAddress: (pickup['address'] ?? '') as String,
      dropoffAddress: (dropoff['address'] ?? '') as String,
      pickupLat: (pickup['lat'] as num?)?.toDouble(),
      pickupLng: (pickup['lng'] as num?)?.toDouble(),
      dropoffLat: (dropoff['lat'] as num?)?.toDouble(),
      dropoffLng: (dropoff['lng'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
      pickupCode: j['pickupCode'] as String?,
      cancellationLabel: (j['cancellation'] as Map?)?['label'] as String?,
      driver: j['driver'] == null ? null : RideDriver.fromJson((j['driver'] as Map).cast<String, dynamic>()),
    );
  }
}

class EmergencyContact {
  EmergencyContact({required this.id, required this.name, required this.phone, this.relationship});
  final String id;
  final String name;
  final String phone;
  final String? relationship;

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    phone: (j['phone'] ?? '') as String,
    relationship: j['relationship'] as String?,
  );
}

class SafetyIncident {
  SafetyIncident({required this.id, required this.state, this.rideId, this.note,
    required this.contactsNotified, required this.createdAt});
  final String id;
  final String state;
  final String? rideId;
  final String? note;
  final int contactsNotified;
  final DateTime createdAt;

  factory SafetyIncident.fromJson(Map<String, dynamic> j) => SafetyIncident(
    id: j['id'] as String,
    state: (j['state'] ?? '') as String,
    rideId: j['rideId'] as String?,
    note: j['note'] as String?,
    contactsNotified: ((j['contacts'] ?? []) as List).length,
    createdAt: DateTime.parse((j['createdAt'] ?? DateTime.now().toIso8601String()) as String).toLocal(),
  );
}

class Payment {
  Payment({required this.id, required this.rideId, required this.amount, required this.method,
    required this.status, this.receipt, this.customerMessage});
  final String id;
  final String rideId;
  final int amount;
  final String method;
  final String status;
  final String? receipt;
  final String? customerMessage;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: j['id'] as String,
    rideId: (j['rideId'] ?? '') as String,
    amount: (j['amount'] as num?)?.toInt() ?? 0,
    method: (j['method'] ?? 'mpesa') as String,
    status: (j['status'] ?? '') as String,
    receipt: j['receipt'] as String?,
    customerMessage: j['customerMessage'] as String?,
  );
}

class ScheduledRide {
  ScheduledRide({required this.id, required this.scheduledAt, required this.pickupAddress,
    required this.dropoffAddress, required this.fare, required this.status, this.seriesId});
  final String id;
  final DateTime scheduledAt;
  final String pickupAddress;
  final String dropoffAddress;
  final int fare;
  final String status;
  final String? seriesId;

  factory ScheduledRide.fromJson(Map<String, dynamic> j) {
    final pickup = (j['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dropoff = (j['dropoff'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ScheduledRide(
      id: j['id'] as String,
      scheduledAt: DateTime.parse(j['scheduledAt'] as String).toLocal(),
      pickupAddress: (pickup['address'] ?? '') as String,
      dropoffAddress: (dropoff['address'] ?? '') as String,
      fare: (j['fare'] as num).toInt(),
      status: (j['status'] ?? '') as String,
      seriesId: j['seriesId'] as String?,
    );
  }
}

class ScheduleSeries {
  ScheduleSeries({required this.id, required this.weekdays, required this.timeOfDay,
    required this.startDate, required this.endDate, required this.fare, required this.status,
    required this.occurrenceCount});
  final String id;
  final List<int> weekdays;
  final String timeOfDay;
  final String startDate;
  final String endDate;
  final int fare;
  final String status;
  final int occurrenceCount;

  factory ScheduleSeries.fromJson(Map<String, dynamic> j) => ScheduleSeries(
    id: j['id'] as String,
    weekdays: ((j['weekdays'] ?? []) as List).map((e) => (e as num).toInt()).toList(),
    timeOfDay: (j['timeOfDay'] ?? '') as String,
    startDate: (j['startDate'] ?? '') as String,
    endDate: (j['endDate'] ?? '') as String,
    fare: (j['fare'] as num).toInt(),
    status: (j['status'] ?? '') as String,
    occurrenceCount: ((j['occurrences'] ?? []) as List).length,
  );
}

enum AuthStep { phone, otp, home }

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  StreamSubscription<RemoteMessage>? _notificationTapSub;
  final _api = ApiClient(baseUrl: kApiBase);
  final _phone = TextEditingController(text: '+254712345678');
  final _otp = TextEditingController();

  AuthStep _step = AuthStep.phone;
  bool _busy = false;
  String? _error;
  String? _devCode;
  AuthSession? _session;
  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a phone number in international format, e.g. +254712345678');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _api.requestOtp(phone);
      setState(() {
        _busy = false;
        _step = AuthStep.otp;
        _devCode = result.devCode;
        if (result.devCode != null) _otp.text = result.devCode!;
      });
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Could not reach the Uko? API. $e'; });
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final session = await _api.verifyOtp(_phone.text.trim(), code);
      await _api.me(session.accessToken);
      _api.accessToken = session.accessToken;
      setState(() { _busy = false; _session = session; _step = AuthStep.home; });
      unawaited(_registerPush(session));
      _listenForNotificationTaps();
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Verification failed. $e'; });
    }
  }

  void _listenForNotificationTaps() {
    _notificationTapSub?.cancel();
    FirebaseMessaging.instance.getInitialMessage().then(_openFromNotification);
    _notificationTapSub = FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification);
  }

  void _openFromNotification(RemoteMessage? message) {
    final rideId = message?.data['rideId'];
    if (rideId is! String || rideId.isEmpty || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FindingDriverPage(api: _api, rideId: rideId),
    ));
  }

  Future<void> _registerPush(AuthSession session) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null) return;
      _api.accessToken = session.accessToken;
      await _api.registerDevice(token);
      FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
        _api.registerDevice(refreshed);
      });
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  void _signOut() {
    setState(() {
      _session = null;
      _step = AuthStep.phone;
      _otp.clear();
      _devCode = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_step == AuthStep.home && _session != null) {
      return HomeScreen(api: _api, session: _session!, onSignOut: _signOut);
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: switch (_step) {
                AuthStep.phone => _buildPhoneStep(context),
                AuthStep.otp => _buildOtpStep(context),
                AuthStep.home => const SizedBox.shrink(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: const Color(0xFF0C8C86), borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.center,
          child: const Text('?', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildPhoneStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo(),
        Text('Welcome to Uko?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Book a Boda now or schedule one for later.', style: TextStyle(color: Color(0xFF5C7077))),
        const SizedBox(height: 24),
        TextField(
          key: const Key('phone_field'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number', hintText: '+254712345678'),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF2F7F6), borderRadius: BorderRadius.circular(10)),
          child: const Text('Pilot test login: +254712345678 · OTP 123456', style: TextStyle(fontSize: 12, color: Color(0xFF3D5A60))),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('send_otp'),
            onPressed: _busy ? null : _sendOtp,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send code'),
          ),
        ),
        const SizedBox(height: 18),
        Text('API: $kApiBase', style: const TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
      ],
    );
  }

  Widget _buildOtpStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo(),
        Text('Enter your code', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('We sent a 6-digit code to ${_phone.text.trim()}.',
            style: const TextStyle(color: Color(0xFF5C7077))),
        if (_devCode != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFDF3E2), borderRadius: BorderRadius.circular(10)),
            child: Text('Development code: $_devCode (debug builds only)',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B4E16))),
          ),
        ],
        const SizedBox(height: 18),
        TextField(
          key: const Key('otp_field'),
          controller: _otp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('verify_otp'),
            onPressed: _busy ? null : _verifyOtp,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify and continue'),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : () => setState(() { _step = AuthStep.phone; _error = null; }),
          child: const Text('Use a different number'),
        ),
      ],
    );
  }

}

class BookingPage extends StatefulWidget {
  const BookingPage({super.key, required this.api, required this.session, this.initialDropoff, this.initialDropoffPlace});
  final ApiClient api;
  final AuthSession session;
  final String? initialDropoff;
  final PlaceSuggestion? initialDropoffPlace;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _pickup = TextEditingController(text: 'Locating your pickup…');
  final _dropoff = TextEditingController();
  PlaceSuggestion? _pickupPlace;
  PlaceSuggestion? _dropoffPlace;
  List<PlaceSuggestion> _pickupSuggestions = const [];
  List<PlaceSuggestion> _dropoffSuggestions = const [];
  RouteResult? _route;
  Timer? _searchDebounce;
  final _scroll = ScrollController();
  bool _locating = true;
  Quote? _quote;
  bool _busy = false;
  String? _error;
  String _payment = 'mpesa';

  @override
  void initState() {
    super.initState();
    if (widget.initialDropoffPlace != null) {
      _dropoffPlace = widget.initialDropoffPlace;
      _dropoff.text = widget.initialDropoffPlace!.name;
    } else if (widget.initialDropoff != null) {
      _dropoff.text = widget.initialDropoff!;
      _dropoffPlace = null;
    }
    _locatePickup();
  }

  Future<void> _locatePickup() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Location services are off');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final rough = PlaceSuggestion(
        id: 'gps-pickup',
        name: 'Current location',
        address: 'Finding your address…',
        lat: position.latitude,
        lng: position.longitude,
      );
      setState(() {
        _pickupPlace = rough;
        _pickup.text = 'Current location';
        _locating = false;
      });
      try {
        final resolved = await widget.api.reverseGeocode(position.latitude, position.longitude);
        if (resolved != null && mounted) {
          setState(() {
            _pickupPlace = resolved;
            _pickup.text = resolved.name;
          });
        }
      } catch (_) {}
      _refreshRoute();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _pickupPlace = const PlaceSuggestion(
          id: 'fallback-pickup',
          name: 'Thika Town',
          address: 'Thika Town, Kiambu County',
          lat: -1.0333,
          lng: 37.0693,
        );
        _pickup.text = 'Thika Town';
      });
      _refreshRoute();
    }
  }

  void _onPlaceChanged(String value, bool pickup) {
    setState(() {
      if (pickup) {
        _pickupPlace = null;
      } else {
        _dropoffPlace = null;
      }
    });
    _searchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        if (pickup) {
          _pickupSuggestions = const [];
        } else {
          _dropoffSuggestions = const [];
        }
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final places = await widget.api.searchPlaces(value.trim());
        if (!mounted) return;
        setState(() {
          if (pickup) {
            _pickupSuggestions = places;
          } else {
            _dropoffSuggestions = places;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
      } catch (_) {/* offline: keep manual entry */}
    });
  }

  void _selectPlace(PlaceSuggestion place, bool pickup) {
    setState(() {
      if (pickup) {
        _pickup.text = place.name;
        _pickupPlace = place;
        _pickupSuggestions = const [];
      } else {
        _dropoff.text = place.name;
        _dropoffPlace = place;
        _dropoffSuggestions = const [];
      }
    });
    _refreshRoute();
  }

  Future<void> _refreshRoute() async {
    final pickup = _pickupPlace;
    final dropoff = _dropoffPlace;
    if (pickup == null || dropoff == null) return;
    try {
      final route = await widget.api.getRoute(
        pickupLat: pickup.lat, pickupLng: pickup.lng,
        dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      );
      if (mounted) setState(() => _route = route);
    } catch (_) {
      // Keep the straight-line preview if routing is unavailable.
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() { _locating = true; _error = null; });
    await _locatePickup();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _pickup.dispose();
    _dropoff.dispose();
    super.dispose();
  }

  Future<void> _saveDropoff() async {
    final place = _dropoffPlace;
    if (place == null) return;
    final controller = TextEditingController(text: place.name);
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save place'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Label (Home, Work, …)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    await SavedPlacesStore.add(SavedPlace(label: label, address: place.name, lat: place.lat, lng: place.lng));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved “$label” to saved places')));
  }

  Future<void> _getQuote() async {
    if (_pickup.text.trim().isEmpty || _dropoff.text.trim().isEmpty) {
      setState(() => _error = 'Enter both pickup and drop-off');
      return;
    }
    setState(() { _busy = true; _error = null; _quote = null; });
    try {
      final pickup = _pickupPlace;
      final dropoff = _dropoffPlace;
      if (pickup == null || dropoff == null) {
        setState(() { _busy = false; _error = 'Pick pickup and drop-off from the suggestions, or use your location.'; });
        return;
      }
      final quote = await widget.api.quote(
        pickupAddress: _pickup.text.trim(),
        dropoffAddress: _dropoff.text.trim(),
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        dropoffLat: dropoff.lat,
        dropoffLng: dropoff.lng,
      );
      setState(() { _busy = false; _quote = quote; });
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Could not get a price. $e'; });
    }
  }

  Future<void> _confirm() async {
    final quote = _quote;
    if (quote == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ride = await widget.api.createRide(quote.id, _payment);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => FindingDriverPage(api: widget.api, rideId: ride.id),
      ));
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Could not book the ride. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Stack(children: [
                        Positioned.fill(child: UkoMap(
                          pickup: _pickup.text,
                          dropoff: _dropoff.text,
                          pickupPoint: _pickupPlace == null ? null : LatLng(_pickupPlace!.lat, _pickupPlace!.lng),
                          dropoffPoint: _dropoffPlace == null ? null : LatLng(_dropoffPlace!.lat, _dropoffPlace!.lng),
                          routePoints: _route?.points,
                        )),
                        Positioned(top: 8, right: 8, child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: IconButton(
                            key: const Key('expand_booking_map'),
                            tooltip: 'Open map',
                            icon: const Icon(Icons.fullscreen, size: 20),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => RouteMapPage(
                                title: 'Your route',
                                pickupAddress: _pickup.text,
                                dropoffAddress: _dropoff.text,
                                pickupPoint: _pickupPlace == null ? const LatLng(-1.2841, 36.8233) : LatLng(_pickupPlace!.lat, _pickupPlace!.lng),
                                dropoffPoint: _dropoffPlace == null ? const LatLng(-1.2657, 36.8075) : LatLng(_dropoffPlace!.lat, _dropoffPlace!.lng),
                                route: _route,
                              ),
                            )),
                          ),
                        )),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Where to?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Boda only during the pilot. Price is fixed before you confirm.',
                      style: TextStyle(color: Color(0xFF5C7077))),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('pickup_field'),
                    controller: _pickup,
                    onChanged: (value) => _onPlaceChanged(value, true),
                    decoration: InputDecoration(
                      labelText: 'Pickup',
                      prefixIcon: const Icon(Icons.trip_origin),
                      suffixIcon: IconButton(
                        key: const Key('use_location'),
                        tooltip: 'Use my current location',
                        onPressed: _locating ? null : _useCurrentLocation,
                        icon: _locating
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location),
                      ),
                    ),
                  ),
                  if (_pickupSuggestions.isNotEmpty)
                    _PlaceSuggestions(places: _pickupSuggestions, onSelected: (place) => _selectPlace(place, true)),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('dropoff_field'),
                    controller: _dropoff,
                    onChanged: (value) => _onPlaceChanged(value, false),
                    decoration: const InputDecoration(labelText: 'Drop-off', prefixIcon: Icon(Icons.place_outlined)),
                  ),
                  if (_dropoffSuggestions.isNotEmpty)
                    _PlaceSuggestions(places: _dropoffSuggestions, onSelected: (place) => _selectPlace(place, false)),
                  if (_dropoffPlace != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const Key('save_dropoff'),
                        onPressed: _saveDropoff,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save place'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const Key('get_quote'),
                      onPressed: _busy ? null : _getQuote,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Get price'),
                    ),
                  ),
                  if (_quote != null) ...[
                    const SizedBox(height: 20),
                    _QuoteCard(quote: _quote!),
                    const SizedBox(height: 16),
                    const Text('Payment', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _PaymentOption(
                          label: 'M-Pesa',
                          icon: Icons.phone_iphone,
                          selected: _payment == 'mpesa',
                          onTap: () => setState(() => _payment = 'mpesa'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PaymentOption(
                          label: 'Cash',
                          icon: Icons.payments_outlined,
                          selected: _payment == 'cash',
                          onTap: () => setState(() => _payment = 'cash'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('confirm_ride'),
                        onPressed: _busy ? null : _confirm,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: Text('Confirm Boda · KES ${_quote!.fare}'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final distanceFare = (quote.breakdown['distanceFare'] ?? 0) as num;
    final timeFare = (quote.breakdown['timeFare'] ?? 0) as num;
    final baseFare = (quote.breakdown['baseFare'] ?? 0) as num;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE7E6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Boda', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('KES ${quote.fare}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF0C8C86))),
        ]),
        const SizedBox(height: 6),
        Text('${quote.distanceKm.toStringAsFixed(1)} km · about ${quote.durationMin} min',
            style: const TextStyle(color: Color(0xFF5C7077), fontSize: 13)),
        const Divider(height: 22),
        _FareRow(label: 'Base', value: 'KES ${baseFare.toInt()}'),
        _FareRow(label: 'Distance', value: 'KES ${distanceFare.toInt()}'),
        _FareRow(label: 'Time', value: 'KES ${timeFare.toInt()}'),
        const SizedBox(height: 4),
        Text('${quote.pickupAddress} → ${quote.dropoffAddress}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
      ]),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Color(0xFF5C7077), fontSize: 13)),
      Text(value, style: const TextStyle(fontSize: 13)),
    ]),
  );
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE9F7F4) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? const Color(0xFF0C8C86) : const Color(0xFFDCE7E6), width: selected ? 1.6 : 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: selected ? const Color(0xFF0C8C86) : const Color(0xFF5C7077)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? const Color(0xFF0A3B3A) : const Color(0xFF2A4048))),
        ]),
      ),
    );
  }
}

class FindingDriverPage extends StatefulWidget {
  const FindingDriverPage({super.key, required this.api, required this.rideId});
  final ApiClient api;
  final String rideId;
  @override
  State<FindingDriverPage> createState() => _FindingDriverPageState();
}

class _FindingDriverPageState extends State<FindingDriverPage> {
  Timer? _timer;
  Timer? _locationTimer;
  Timer? _paymentTimer;
  Ride? _ride;
  DriverLocation? _driverLocation;
  RouteResult? _route;
  int? _driverEtaMin;
  DateTime? _lastEtaUpdate;
  Payment? _payment;
  String? _error;
  String? _paymentError;
  bool _cancelled = false;
  bool _busyCancel = false;
  bool _paymentBusy = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _pollDriverLocation();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _locationTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollDriverLocation());
  }

  Future<void> _pollDriverLocation() async {
    try {
      final location = await widget.api.getDriverLocation(widget.rideId);
      if (!mounted) return;
      if (location != null) {
        setState(() => _driverLocation = location);
        await _updateDriverEta(location);
      }
    } catch (_) {
      // best-effort; retry on next tick
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationTimer?.cancel();
    _paymentTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final ride = await widget.api.getRide(widget.rideId);
      if (!mounted) return;
      setState(() { _ride = ride; _error = null; });
      if (_route == null && ride.pickupLat != null && ride.dropoffLat != null) {
        try {
          final route = await widget.api.getRoute(
            pickupLat: ride.pickupLat!, pickupLng: ride.pickupLng!,
            dropoffLat: ride.dropoffLat!, dropoffLng: ride.dropoffLng!,
          );
          if (mounted) setState(() => _route = route);
        } catch (_) {}
      }
      if (ride.state == 'COMPLETED') {
        _timer?.cancel();
        _refreshPayment();
      } else if (ride.state == 'CANCELLED') {
        _timer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Connection lost. Retrying…');
    }
  }

  Future<void> _updateDriverEta(DriverLocation location) async {
    final ride = _ride;
    if (ride == null || ride.state == 'COMPLETED' || ride.state == 'CANCELLED') return;
    final now = DateTime.now();
    if (_lastEtaUpdate != null && now.difference(_lastEtaUpdate!) < const Duration(seconds: 10)) return;
    final toDropoff = ride.state == 'IN_PROGRESS';
    final lat = toDropoff ? ride.dropoffLat : ride.pickupLat;
    final lng = toDropoff ? ride.dropoffLng : ride.pickupLng;
    if (lat == null || lng == null) return;
    _lastEtaUpdate = now;
    try {
      final route = await widget.api.getRoute(
        pickupLat: location.lat, pickupLng: location.lng,
        dropoffLat: lat, dropoffLng: lng,
      );
      if (!mounted) return;
      setState(() => _driverEtaMin = route.durationMin);
    } catch (_) {}
  }

  Future<void> _cancel() async {
    const reasons = [
      'Driver is too far away',
      'Changed my plans',
      'Wrong pickup location',
      'Waiting too long',
      'Booked by mistake',
      'Other reason',
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Why are you cancelling?'),
        children: [
          for (final option in reasons)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(option),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(option)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Keep my ride')),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    setState(() { _busyCancel = true; _error = null; });
    try {
      await widget.api.cancelRide(widget.rideId, reason: reason);
      if (!mounted) return;
      setState(() { _cancelled = true; _busyCancel = false; });
      _timer?.cancel();
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _busyCancel = false; _error = e.message; });
      _poll();
    } catch (e) {
      if (!mounted) return;
      setState(() { _busyCancel = false; _error = 'Could not cancel: $e'; });
    }
  }

  Future<void> _refreshPayment() async {
    final ride = _ride;
    if (ride == null) return;
    try {
      final payment = await widget.api.ridePayment(ride.id);
      if (!mounted) return;
      setState(() => _payment = payment);
    } catch (_) {
      // Payment state is best-effort here; the pay button still works.
    }
  }

  Future<void> _payMpesa() async {
    final ride = _ride;
    if (ride == null) return;
    setState(() { _paymentBusy = true; _paymentError = null; });
    try {
      final payment = await widget.api.requestMpesa(ride.id);
      if (!mounted) return;
      setState(() { _payment = payment; _paymentBusy = false; });
      _startPaymentPolling();
    } on ApiException catch (e) {
      setState(() { _paymentBusy = false; _paymentError = e.message; });
    } catch (e) {
      setState(() { _paymentBusy = false; _paymentError = 'Could not start M-Pesa. $e'; });
    }
  }

  Future<void> _payCash() async {
    final ride = _ride;
    if (ride == null) return;
    setState(() { _paymentBusy = true; _paymentError = null; });
    try {
      final payment = await widget.api.confirmCash(ride.id);
      if (!mounted) return;
      setState(() { _payment = payment; _paymentBusy = false; });
    } on ApiException catch (e) {
      setState(() { _paymentBusy = false; _paymentError = e.message; });
    } catch (e) {
      setState(() { _paymentBusy = false; _paymentError = 'Could not confirm cash. $e'; });
    }
  }

  void _startPaymentPolling() {
    _paymentTimer?.cancel();
    _paymentTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final payment = _payment;
      if (payment == null) return;
      try {
        final updated = await widget.api.getPayment(payment.id);
        if (!mounted) return;
        setState(() => _payment = updated);
        if (updated.status == 'SUCCESS' || updated.status == 'FAILED') _paymentTimer?.cancel();
      } catch (_) {}
    });
  }

  String _stateLabel(String state) => switch (state) {
    'ASSIGNED' => 'Driver assigned',
    'ARRIVING' => 'Driver is on the way',
    'ARRIVED' => 'Driver has arrived',
    'IN_PROGRESS' => 'On the way to your destination',
    'COMPLETED' => 'Trip completed',
    _ => state,
  };

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final driver = ride?.driver;
    final completed = ride?.state == 'COMPLETED';
    final cancelled = ride?.state == 'CANCELLED';
    final showDriver = driver != null && !completed && !cancelled;
    final canCancel = ride != null && ['ASSIGNED', 'ARRIVING'].contains(ride.state);
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (ride == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: CircularProgressIndicator(),
                    )
                  else if (cancelled) ...[
                    const SizedBox(height: 30),
                    const Icon(Icons.cancel_outlined, size: 48, color: Color(0xFFB3261E)),
                    const SizedBox(height: 12),
                    const Text('Ride cancelled', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (ride.cancellationLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(ride.cancellationLabel!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5C7077))),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                    ),
                  ] else if (ride.state == 'SEARCHING') ...[
                    const SizedBox(height: 30),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('Finding your Boda…',
                        key: Key('ride_state'),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('Matching you with a nearby rider. Keep the app open.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF5C7077))),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('cancel_ride'),
                        onPressed: _cancelled || _busyCancel ? null : _cancel,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                        child: const Text('Cancel ride'),
                      ),
                    ),
                  ] else if (completed) ...[
                    const SizedBox(height: 30),
                    const Icon(Icons.check_circle, size: 56, color: Color(0xFF0C8C86)),
                    const SizedBox(height: 12),
                    const Text('Trip completed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('KES ${ride.fare} · ${ride.paymentMethod.toUpperCase()}',
                        style: const TextStyle(color: Color(0xFF5C7077))),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                      child: Row(children: [
                        const Icon(Icons.receipt_long, color: Color(0xFF0C8C86)),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${ride.pickupAddress} → ${ride.dropoffAddress}', style: const TextStyle(fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (_payment?.status == 'SUCCESS')
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: Color(0xFF0C8C86)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Payment received · KES ${ride.fare}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${ride.paymentMethod.toUpperCase()}${_payment?.receipt != null ? ' · ${_payment!.receipt}' : ''}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                          ])),
                        ]),
                      )
                    else if (_payment?.status == 'PENDING')
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFFFDF3E2), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Check your phone for the M-Pesa prompt to pay KES ${ride.fare}…',
                              style: const TextStyle(fontSize: 13))),
                        ]),
                      )
                    else if (_payment?.status == 'FAILED')
                      Text('Payment failed. Try again.', style: const TextStyle(color: Color(0xFFB3261E))),
                    if (_paymentError != null) ...[
                      const SizedBox(height: 8),
                      Text(_paymentError!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
                    ],
                    if (_payment?.status != 'SUCCESS' && _payment?.status != 'PENDING') ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: Key(ride.paymentMethod == 'cash' ? 'pay_cash' : 'pay_mpesa'),
                          onPressed: _paymentBusy ? null : (ride.paymentMethod == 'cash' ? _payCash : _payMpesa),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                          child: Text(ride.paymentMethod == 'cash'
                              ? 'Confirm cash paid · KES ${ride.fare}'
                              : 'Pay KES ${ride.fare} with M-Pesa'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('ride_done'),
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: const Text('Done'),
                      ),
                    ),
                  ] else if (showDriver) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: 230,
                        width: double.infinity,
                        child: Stack(children: [
                          Positioned.fill(child: UkoMap(
                            pickup: ride.pickupAddress,
                            dropoff: ride.dropoffAddress,
                            driverAssigned: true,
                            driverPoint: _driverLocation == null ? null : LatLng(_driverLocation!.lat, _driverLocation!.lng),
                            routePoints: _route?.points,
                          )),
                          Positioned(top: 8, right: 8, child: Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            child: IconButton(
                              key: const Key('expand_trip_map'),
                              tooltip: 'Open map',
                              icon: const Icon(Icons.fullscreen, size: 20),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => RouteMapPage(
                                  title: 'Your trip',
                                  pickupAddress: ride.pickupAddress,
                                  dropoffAddress: ride.dropoffAddress,
                                  pickupPoint: ride.pickupLat == null ? const LatLng(-1.2841, 36.8233) : LatLng(ride.pickupLat!, ride.pickupLng!),
                                  dropoffPoint: ride.dropoffLat == null ? const LatLng(-1.2657, 36.8075) : LatLng(ride.dropoffLat!, ride.dropoffLng!),
                                  route: _route,
                                  driverPoint: _driverLocation == null ? null : LatLng(_driverLocation!.lat, _driverLocation!.lng),
                                ),
                              )),
                            ),
                          )),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDCE7E6)),
                      ),
                      child: Column(children: [
                        const CircleAvatar(radius: 30, backgroundColor: Color(0xFFE9F7F4),
                            child: Icon(Icons.person, size: 32, color: Color(0xFF0C8C86))),
                        const SizedBox(height: 12),
                        Text(driver.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('${driver.vehicle} · ${driver.plate}', style: const TextStyle(color: Color(0xFF5C7077))),
                        const SizedBox(height: 4),
                        Text('★ ${driver.rating} · ${_stateLabel(ride.state)}', key: const Key('ride_state'),
                            style: const TextStyle(color: Color(0xFF0C8C86), fontWeight: FontWeight.w600)),
                        if (_driverEtaMin != null)
                          Text(
                            ride.state == 'IN_PROGRESS' ? '$_driverEtaMin min to destination' : 'Driver $_driverEtaMin min away',
                            key: const Key('driver_eta'),
                            style: const TextStyle(color: Color(0xFF08222B), fontWeight: FontWeight.w800),
                          ),
                        if (ride.pickupCode != null) ...[
                          const Divider(height: 24),
                          const Text('Pickup code', style: TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                          Text(ride.pickupCode!, key: const Key('ride_code'),
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 8, color: Color(0xFF0C8C86))),
                          const Text('Share this code with your driver', style: TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
                        ],
                        const SizedBox(height: 10),
                        Text('${ride.pickupAddress} → ${ride.dropoffAddress}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('trip_sos'),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SafetyPage(api: widget.api, rideId: ride.id),
                          )),
                          icon: const Icon(Icons.sos, size: 18, color: Color(0xFFB3261E)),
                          label: const Text('SOS', style: TextStyle(color: Color(0xFFB3261E))),
                        ),
                      ]),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
                    ],
                    const SizedBox(height: 20),
                    if (canCancel)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('cancel_ride'),
                          onPressed: _cancelled || _busyCancel ? null : _cancel,
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                          child: _busyCancel
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Cancel ride'),
                        ),
                      ),
                    if (ride.state == 'ARRIVED') ...[
                      const SizedBox(height: 10),
                      const Text('Your driver has arrived. Cancellation is handled by dispatch now.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF8A9DA2))),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmtDate(DateTime d) => '${_weekdayShort[d.weekday - 1]} ${d.day} ${_monthShort[d.month - 1]} ${d.year}';
String _fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.api,
    required this.session,
    this.initialPickup,
    this.initialDropoff,
    this.initialWhen,
  });
  final ApiClient api;
  final AuthSession session;
  final String? initialPickup;
  final String? initialDropoff;
  final DateTime? initialWhen;
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _pickup = TextEditingController(text: 'Thika Town');
  final _dropoff = TextEditingController();
  PlaceSuggestion? _pickupPlace = const PlaceSuggestion(
      id: 'default-pickup', name: 'Thika Town', address: 'Thika Town, Kiambu County', lat: -1.0333, lng: 37.0693);
  PlaceSuggestion? _dropoffPlace;
  List<PlaceSuggestion> _pickupSuggestions = const [];
  List<PlaceSuggestion> _dropoffSuggestions = const [];
  Timer? _searchDebounce;
  final _scroll = ScrollController();
  DateTime _when = DateTime.now().add(const Duration(hours: 2));
  DateTime _endDate = DateTime.now().add(const Duration(days: 28));
  final Set<int> _weekdays = <int>{};
  ScheduledRide? _ride;
  ScheduleSeries? _series;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialPickup != null) {
      _pickup.text = widget.initialPickup!;
      _pickupPlace = null;
    }
    if (widget.initialDropoff != null) {
      _dropoff.text = widget.initialDropoff!;
      _dropoffPlace = null;
    }
    if (widget.initialWhen != null) _when = widget.initialWhen!;
    _endDate = _when.add(const Duration(days: 28));
    _weekdays.add(_when.weekday);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _pickup.dispose();
    _dropoff.dispose();
    super.dispose();
  }

  void _onPlaceChanged(String value, bool pickup) {
    setState(() {
      if (pickup) {
        _pickupPlace = null;
      } else {
        _dropoffPlace = null;
      }
    });
    _searchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        if (pickup) {
          _pickupSuggestions = const [];
        } else {
          _dropoffSuggestions = const [];
        }
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final places = await widget.api.searchPlaces(value.trim());
        if (!mounted) return;
        setState(() {
          if (pickup) {
            _pickupSuggestions = places;
          } else {
            _dropoffSuggestions = places;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
      } catch (_) {}
    });
  }

  void _selectPlace(PlaceSuggestion place, bool pickup) {
    setState(() {
      if (pickup) {
        _pickup.text = place.name;
        _pickupPlace = place;
        _pickupSuggestions = const [];
      } else {
        _dropoff.text = place.name;
        _dropoffPlace = place;
        _dropoffSuggestions = const [];
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: now.add(const Duration(minutes: 45)),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() => _when = DateTime(picked.year, picked.month, picked.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (picked == null) return;
    setState(() => _when = DateTime(_when.year, _when.month, _when.day, picked.hour, picked.minute));
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _ride?.scheduledAt ?? DateTime.now().add(const Duration(days: 1)),
      lastDate: (_ride?.scheduledAt ?? DateTime.now()).add(const Duration(days: 56)),
    );
    if (picked == null) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  Future<List<double>> _resolvePlace(String text) async {
    const known = <String, List<double>>{
      'kenyatta avenue': [-1.2841, 36.8233],
      'westlands': [-1.2657, 36.8075],
      'jkia': [-1.3169, 36.9289],
      'jomo kenyatta international airport': [-1.3169, 36.9289],
      'kileleshwa': [-1.2783, 36.7826],
      'kilimani': [-1.2921, 36.7867],
      'upper hill': [-1.2987, 36.8145],
      'lavington': [-1.2692, 36.7710],
    };
    final match = known[text.toLowerCase()];
    if (match != null) return match;
    final places = await widget.api.searchPlaces(text);
    if (places.isEmpty) throw Exception('No location found for "$text"');
    return [places.first.lat, places.first.lng];
  }

  Future<void> _schedule() async {
    setState(() { _busy = true; _error = null; });
    try {
      final pickup = _pickupPlace != null
          ? [_pickupPlace!.lat, _pickupPlace!.lng]
          : await _resolvePlace(_pickup.text.trim());
      final dropoff = _dropoffPlace != null
          ? [_dropoffPlace!.lat, _dropoffPlace!.lng]
          : await _resolvePlace(_dropoff.text.trim());
      final ride = await widget.api.scheduleRide(
        pickupAddress: _pickup.text.trim(),
        dropoffAddress: _dropoff.text.trim(),
        pickupLat: pickup[0],
        pickupLng: pickup[1],
        dropoffLat: dropoff[0],
        dropoffLng: dropoff[1],
        scheduledAt: _when,
      );
      setState(() {
        _busy = false;
        _ride = ride;
        _weekdays
          ..clear()
          ..add(ride.scheduledAt.weekday);
        _endDate = ride.scheduledAt.add(const Duration(days: 28));
      });
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Could not schedule the ride. $e'; });
    }
  }

  Future<void> _createSeries() async {
    final ride = _ride;
    if (ride == null || _weekdays.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final series = await widget.api.repeatRide(ride.id, _weekdays.toList()..sort(), _endDate);
      setState(() { _busy = false; _series = series; });
    } on ApiException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Could not create the weekly series. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Plan ahead', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Book a Boda up to 90 days ahead. Price is fixed at booking.',
                    style: TextStyle(color: Color(0xFF5C7077))),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('sched_pickup'),
                  controller: _pickup,
                  onChanged: (value) => _onPlaceChanged(value, true),
                  decoration: const InputDecoration(labelText: 'Pickup', prefixIcon: Icon(Icons.trip_origin)),
                ),
                if (_pickupSuggestions.isNotEmpty)
                  _PlaceSuggestions(places: _pickupSuggestions, onSelected: (place) => _selectPlace(place, true)),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('sched_dropoff'),
                  controller: _dropoff,
                  onChanged: (value) => _onPlaceChanged(value, false),
                  decoration: const InputDecoration(labelText: 'Drop-off', prefixIcon: Icon(Icons.place_outlined)),
                ),
                if (_dropoffSuggestions.isNotEmpty)
                  _PlaceSuggestions(places: _dropoffSuggestions, onSelected: (place) => _selectPlace(place, false)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('sched_date'),
                      onPressed: _busy ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_fmtDate(_when)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const Key('sched_time'),
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_fmtTime(_when)),
                  ),
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('schedule_ride'),
                    onPressed: _busy ? null : _schedule,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Schedule ride'),
                  ),
                ),
                if (_ride != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Ride scheduled', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('KES ${_ride!.fare}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF0C8C86))),
                      ]),
                      const SizedBox(height: 6),
                      Text('${_fmtDate(_ride!.scheduledAt)} · ${_fmtTime(_ride!.scheduledAt)}', style: const TextStyle(fontSize: 13, color: Color(0xFF5C7077))),
                      Text('${_ride!.pickupAddress} → ${_ride!.dropoffAddress}', style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                    ]),
                  ),
                  const Divider(height: 30),
                  const Text('Make it a weekly series', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Choose the days. The series runs for up to 8 weeks and generates occurrences 14 days ahead.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        key: Key('weekday_$day'),
                        label: Text(_weekdayShort[day - 1]),
                        selected: _weekdays.contains(day),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _weekdays.add(day);
                          } else {
                            _weekdays.remove(day);
                          }
                        }),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('series_end_date'),
                    onPressed: _busy ? null : _pickEndDate,
                    icon: const Icon(Icons.event_repeat, size: 18),
                    label: Text('Ends ${_fmtDate(_endDate)}'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('create_series'),
                      onPressed: _busy || _weekdays.isEmpty ? null : _createSeries,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      child: const Text('Create weekly series'),
                    ),
                  ),
                  if (_series != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Weekly series created', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('${_series!.weekdays.map((d) => _weekdayShort[d - 1]).join(' & ')} · ${_series!.timeOfDay} · ${_series!.occurrenceCount} upcoming occurrences', style: const TextStyle(fontSize: 12, color: Color(0xFF2A4048))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('view_scheduled'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ScheduledRidesPage(api: widget.api, session: widget.session),
                        )),
                        child: const Text('View scheduled rides'),
                      ),
                    ),
                  ],
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduledRidesPage extends StatefulWidget {
  const ScheduledRidesPage({super.key, required this.api, required this.session});
  final ApiClient api;
  final AuthSession session;
  @override
  State<ScheduledRidesPage> createState() => _ScheduledRidesPageState();
}

class _ScheduledRidesPageState extends State<ScheduledRidesPage> {
  List<ScheduledRide> _rides = [];
  List<ScheduleSeries> _series = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rides = await widget.api.scheduledRides();
      final series = await widget.api.scheduleSeries();
      if (!mounted) return;
      setState(() { _rides = rides; _series = series; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load scheduled rides. $e'; });
    }
  }

  Future<void> _toggleSeries(ScheduleSeries series) async {
    try {
      await widget.api.updateSeries(series.id, series.status == 'ACTIVE' ? 'PAUSED' : 'ACTIVE');
      await _load();
    } catch (e) {
      setState(() => _error = 'Could not update the series. $e');
    }
  }

  Future<void> _cancelRide(ScheduledRide ride) async {
    try {
      await widget.api.cancelScheduledRide(ride.id);
      await _load();
    } catch (e) {
      setState(() => _error = 'Could not cancel the ride. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UkoTopBar(actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                        const SizedBox(height: 12),
                      ],
                      Text('Upcoming rides', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (_rides.isEmpty)
                        const Text('No scheduled rides yet.', style: TextStyle(color: Color(0xFF5C7077)))
                      else
                        for (final ride in _rides) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCE7E6))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('${_fmtDate(ride.scheduledAt)} · ${_fmtTime(ride.scheduledAt)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(ride.status, style: const TextStyle(fontSize: 12, color: Color(0xFF0C8C86))),
                              ]),
                              const SizedBox(height: 4),
                              Text('${ride.pickupAddress} → ${ride.dropoffAddress}', style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                              const SizedBox(height: 4),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('KES ${ride.fare}${ride.seriesId != null ? ' · part of a series' : ''}', style: const TextStyle(fontSize: 12)),
                                if (ride.status == 'SCHEDULED')
                                  TextButton(onPressed: () => _cancelRide(ride), child: const Text('Cancel')),
                              ]),
                            ]),
                          ),
                        ],
                      const SizedBox(height: 18),
                      Text('Weekly series', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (_series.isEmpty)
                        const Text('No recurring series yet.', style: TextStyle(color: Color(0xFF5C7077)))
                      else
                        for (final series in _series) ...[
                          Container(
                            key: Key('series_${series.id}'),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCE7E6))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text(series.weekdays.map((d) => _weekdayShort[d - 1]).join(' & '), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(series.status, style: TextStyle(fontSize: 12, color: series.status == 'ACTIVE' ? const Color(0xFF0C8C86) : const Color(0xFFB26A00))),
                              ]),
                              const SizedBox(height: 4),
                              Text('${series.timeOfDay} · ${series.startDate} → ${series.endDate} · ${series.occurrenceCount} upcoming', style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  key: Key('toggle_series_${series.id}'),
                                  onPressed: () => _toggleSeries(series),
                                  child: Text(series.status == 'ACTIVE' ? 'Pause' : 'Resume'),
                                ),
                              ),
                            ]),
                          ),
                        ],
                    ]),
                  ),
          ),
        ),
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.api, required this.session});
  final ApiClient api;
  final AuthSession session;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  bool _busy = false;
  bool _requested = false;
  bool _denied = false;
  String? _error;
  List<CalendarSuggestion> _suggestions = [];

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _calendarChannel.invokeMapMethod<String, dynamic>('getSuggestions');
      if (!mounted) return;
      final permission = result?['permission'] == true;
      final raw = (result?['suggestions'] as List?) ?? const [];
      final suggestions = raw
          .map((e) => CalendarSuggestion.fromMap((e as Map).cast<dynamic, dynamic>()))
          .take(3)
          .toList();
      setState(() {
        _busy = false;
        _requested = true;
        _denied = !permission;
        _suggestions = suggestions;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _requested = true;
        _error = 'Could not read the calendar. ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = 'Could not read the calendar. $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ride to your next event', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('We can suggest rides from events that have a location in the next 7 days.',
                    style: TextStyle(color: Color(0xFF5C7077))),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(12)),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_outline, color: Color(0xFF0C8C86), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Calendar access is optional. Events are read on this device only — Uko? never stores or uploads your calendar. Only the destination and time you choose are sent when you book.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF2A4048)),
                      ),
                    ),
                  ]),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                ],
                const SizedBox(height: 18),
                if (!_requested)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('allow_calendar'),
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(_busy ? 'Opening calendar…' : 'Allow calendar access'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  )
                else if (_denied) ...[
                  const Text('Calendar access was not granted.',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('You can allow it in Android settings → Apps → Uko? Rider → Permissions → Calendar.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const Key('retry_calendar'),
                      onPressed: _busy ? null : _load,
                      child: const Text('Try again'),
                    ),
                  ),
                ] else if (_busy)
                  const Center(child: CircularProgressIndicator())
                else if (_suggestions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCE7E6))),
                    child: const Text('No events with a location in the next 7 days.',
                        style: TextStyle(color: Color(0xFF5C7077))),
                  )
                else ...[
                  for (final suggestion in _suggestions) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Expanded(child: Text(suggestion.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          const Icon(Icons.calendar_today, size: 18, color: Color(0xFF0C8C86)),
                        ]),
                        const SizedBox(height: 4),
                        Text('${_fmtDate(suggestion.start)} · ${_fmtTime(suggestion.start)}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                        const SizedBox(height: 2),
                        Text(suggestion.location, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                              builder: (_) => SchedulePage(
                                api: widget.api,
                                session: widget.session,
                                initialDropoff: suggestion.location,
                                initialWhen: suggestion.start,
                              ),
                            )),
                            child: const Text('Schedule a ride to this event'),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 4),
                  TextButton(
                    key: const Key('refresh_calendar'),
                    onPressed: _busy ? null : _load,
                    child: const Text('Refresh suggestions'),
                  ),
                  const Text('Showing up to 3 events from the next 7 days. Only events with a location are used.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key, required this.api, this.rideId});
  final ApiClient api;
  final String? rideId;
  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  List<EmergencyContact> _contacts = [];
  SafetyIncident? _incident;
  bool _loading = true;
  bool _sosBusy = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await widget.api.safetyContacts();
      if (!mounted) return;
      setState(() { _contacts = contacts; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load contacts. $e'; });
    }
  }

  Future<void> _addContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relationship = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add emergency contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'Jane W.')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', hintText: '+254712345679')),
          const SizedBox(height: 10),
          TextField(controller: relationship, decoration: const InputDecoration(labelText: 'Relationship (optional)', hintText: 'Sister')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('save_contact'),
            onPressed: () {
              if (name.text.trim().length < 2 || !RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone.text.trim())) {
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.addSafetyContact(
        name: name.text.trim(),
        phone: phone.text.trim(),
        relationship: relationship.text.trim(),
      );
      await _loadContacts();
    } catch (e) {
      setState(() => _error = 'Could not add the contact. $e');
    }
  }

  Future<void> _removeContact(EmergencyContact contact) async {
    try {
      await widget.api.removeSafetyContact(contact.id);
      await _loadContacts();
    } catch (e) {
      setState(() => _error = 'Could not remove the contact. $e');
    }
  }

  Future<void> _sendSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS?'),
        content: const Text('This alerts Uko? ops on-call and your emergency contacts. Use it only in an emergency.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm_sos'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _sosBusy = true; _error = null; });
    try {
      final incident = await widget.api.triggerSos(rideId: widget.rideId, note: 'SOS sent from the Uko? rider app');
      if (!mounted) return;
      setState(() { _incident = incident; _sosBusy = false; });
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        final current = _incident;
        if (current == null) return;
        try {
          final updated = await widget.api.getIncident(current.id);
          if (!mounted) return;
          setState(() => _incident = updated);
          if (['ACKED', 'RESOLVED', 'CANCELLED'].contains(updated.state)) _pollTimer?.cancel();
        } catch (_) {}
      });
    } catch (e) {
      setState(() { _sosBusy = false; _error = 'Could not send SOS. $e'; });
    }
  }

  Future<void> _cancelSos() async {
    final incident = _incident;
    if (incident == null) return;
    try {
      final updated = await widget.api.cancelIncident(incident.id);
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() => _incident = updated);
    } catch (e) {
      setState(() => _error = 'Could not cancel the SOS. $e');
    }
  }

  String _incidentMessage(String state) => switch (state) {
    'OPEN' => 'SOS received. Uko? ops on-call is being alerted…',
    'ACKED' => 'Help acknowledged. A private responder is being dispatched and your emergency contacts are being notified.',
    'CANCELLED' => 'SOS cancelled — marked as a false alarm.',
    'RESOLVED' => 'Incident resolved.',
    _ => state,
  };

  @override
  Widget build(BuildContext context) {
    final incident = _incident;
    return Scaffold(
      appBar: const UkoTopBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Your safety', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('Private response during the pilot: Uko? ops on-call and a private responder. Uko? does not dial 999.',
                          style: TextStyle(color: Color(0xFF5C7077))),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                      ],
                      const SizedBox(height: 18),
                      if (incident != null)
                        Container(
                          key: const Key('sos_status'),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: incident.state == 'CANCELLED' ? const Color(0xFFF1F3F3) : const Color(0xFFFDECEA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: incident.state == 'CANCELLED' ? const Color(0xFFDCE7E6) : const Color(0xFFE7A29A)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(incident.state == 'CANCELLED' ? Icons.check_circle_outline : Icons.emergency,
                                  color: incident.state == 'CANCELLED' ? const Color(0xFF0C8C86) : const Color(0xFFB3261E)),
                              const SizedBox(width: 8),
                              Text('SOS · ${incident.state}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ]),
                            const SizedBox(height: 6),
                            Text(_incidentMessage(incident.state), style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${incident.contactsNotified} emergency contact(s) on file · ${_fmtTime(incident.createdAt)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF5C7077))),
                            if (!['CANCELLED', 'RESOLVED'].contains(incident.state)) ...[
                              const SizedBox(height: 10),
                              OutlinedButton(
                                key: const Key('cancel_sos'),
                                onPressed: _cancelSos,
                                child: const Text('Cancel SOS — false alarm'),
                              ),
                            ],
                          ]),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('send_sos'),
                            onPressed: _sosBusy ? null : _sendSos,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB3261E),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            icon: const Icon(Icons.sos),
                            label: Text(_sosBusy ? 'Sending SOS…' : 'Send SOS'),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Emergency contacts', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        TextButton(onPressed: _addContact, child: const Text('Add contact')),
                      ]),
                      if (_contacts.isEmpty)
                        const Text('No emergency contacts yet. Add someone Uko? can notify during a trip.',
                            style: TextStyle(color: Color(0xFF5C7077)))
                      else
                        for (final contact in _contacts)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCE7E6))),
                            child: Row(children: [
                              const CircleAvatar(backgroundColor: Color(0xFFE9F7F4), child: Icon(Icons.person, color: Color(0xFF0C8C86))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('${contact.phone}${contact.relationship != null ? ' · ${contact.relationship}' : ''}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                              ])),
                              IconButton(
                                tooltip: 'Remove contact',
                                onPressed: () => _removeContact(contact),
                                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF8A9DA2)),
                              ),
                            ]),
                          ),
                      const SizedBox(height: 10),
                      const Text('Your emergency contacts are stored with your Uko? account and only used for safety incidents.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8A9DA2))),
                    ]),
                  ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.api, required this.session, required this.onSignOut});
  final ApiClient api;
  final AuthSession session;
  final VoidCallback onSignOut;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const UkoMap(hero: true),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: const Color(0xFF08222B), borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: const Text('?', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      const Text('Uko?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF08222B))),
                      const Spacer(),
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
                        child: IconButton(
                          tooltip: 'Notifications',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.notifications_none, size: 20, color: Color(0xFF08222B)),
                          onPressed: () => _open(context, NotificationsPage(api: api)),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.location_on, size: 14, color: Color(0xFF0C8C86)),
                          SizedBox(width: 4),
                          Text('Thika', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2A4048))),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Account',
                        onSelected: (value) async {
                          if (value == 'signout') {
                            onSignOut();
                          } else if (value == 'report') {
                            await reportClientError('rider', 'Pilot diagnostic sent from rider app', StackTrace.current, token: session.accessToken);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostic sent to the Uko? team')));
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'report', child: Text('Report a problem')),
                          PopupMenuItem(value: 'signout', child: Text('Sign out')),
                        ],
                        child: CircleAvatar(
                          radius: 21,
                          backgroundColor: const Color(0xFF0C8C86),
                          child: Text(
                            session.phone.length >= 4 ? session.phone.substring(session.phone.length - 4) : 'UK',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
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
                          Center(
                            child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFDCE7E6), borderRadius: BorderRadius.circular(2))),
                          ),
                          const SizedBox(height: 14),
                          Text('$_greeting, rider', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('Where are you headed today?', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: () async {
                              final dropoff = await showModalBottomSheet<PlaceSuggestion>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => BookingSheet(api: api),
                              );
                              if (dropoff != null && context.mounted) {
                                _open(context, BookingPage(api: api, session: session, initialDropoffPlace: dropoff));
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F7F6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFDCE7E6)),
                              ),
                              child: Row(children: [
                                const Icon(Icons.search, color: Color(0xFF0C8C86)),
                                const SizedBox(width: 10),
                                const Expanded(child: Text('Where to?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                                  child: const Text('Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0C8C86))),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right, color: Color(0xFF8A9DA2)),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(children: [
                            _QuickAction(
                              icon: Icons.two_wheeler,
                              label: 'Book a Boda',
                              onTap: () => _open(context, BookingPage(api: api, session: session)),
                            ),
                            const SizedBox(width: 10),
                            _QuickAction(
                              icon: Icons.event_available,
                              label: 'Schedule',
                              onTap: () => _open(context, SchedulePage(api: api, session: session)),
                            ),
                            const SizedBox(width: 10),
                            _QuickAction(
                              icon: Icons.calendar_month,
                              label: 'Calendar',
                              onTap: () => _open(context, CalendarPage(api: api, session: session)),
                            ),
                            const SizedBox(width: 10),
                            _QuickAction(
                              icon: Icons.health_and_safety,
                              label: 'Safety',
                              onTap: () => _open(context, SafetyPage(api: api)),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: () => _open(context, TripsPage(api: api)),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFF6FAF9), borderRadius: BorderRadius.circular(14)),
                              child: Row(children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.receipt_long, size: 20, color: Color(0xFF0C8C86)),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(child: Text('Trips & receipts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8A9DA2)),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: Text('Boda only during the pilot · Uko? does not call 999',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
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
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(color: const Color(0xFFF6FAF9), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE4EEEC))),
          child: Column(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 20, color: const Color(0xFF0C8C86)),
            ),
            const SizedBox(height: 7),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2A4048))),
          ]),
        ),
      ),
    );
  }
}

class RideMap extends StatelessWidget {
  const RideMap({super.key, this.hero = false, this.pickup, this.dropoff, this.driverAssigned = false});
  final bool hero;
  final String? pickup;
  final String? dropoff;
  final bool driverAssigned;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _RideMapPainter(hero: hero, driverAssigned: driverAssigned)),
        if (!hero && pickup != null && dropoff != null)
          Positioned(
            left: 14, right: 14, bottom: 12,
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x1808222B), blurRadius: 8)]),
                  child: Row(children: [
                    const Icon(Icons.trip_origin, size: 15, color: Color(0xFF0C8C86)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(pickup!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                    const Icon(Icons.arrow_forward, size: 13, color: Color(0xFF8A9DA2)),
                    const SizedBox(width: 6),
                    const Icon(Icons.place, size: 15, color: Color(0xFFB3261E)),
                    const SizedBox(width: 4),
                    Expanded(child: Text(dropoff!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
              if (driverAssigned) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xFF08222B), borderRadius: BorderRadius.circular(12)),
                  child: const Text('3 min', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
      ],
    );
  }
}

class _RideMapPainter extends CustomPainter {
  _RideMapPainter({required this.hero, required this.driverAssigned});
  final bool hero;
  final bool driverAssigned;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFEAF2EE);
    canvas.drawRect(Offset.zero & size, bg);

    final blockPaint = Paint()..color = const Color(0xFFF7FBF9);
    final blockEdge = Paint()..color = const Color(0xFFDDE9E4)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      for (var j = 0; j < 6; j++) {
        if ((i + j) % 3 == 0) continue;
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(20.0 + i * (size.width / 7), 20.0 + j * (size.height / 6), size.width / 7 - 16, size.height / 6 - 16),
          const Radius.circular(10),
        );
        canvas.drawRRect(r, blockPaint);
        canvas.drawRRect(r, blockEdge);
      }
    }

    final road = Paint()..color = Colors.white..strokeWidth = 7..strokeCap = StrokeCap.round;
    final roadEdge = Paint()..color = const Color(0xFFD6E3DE)..strokeWidth = 11..strokeCap = StrokeCap.round;
    for (var i = 1; i < 4; i++) {
      final y = size.height * (0.18 + i * 0.18);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadEdge);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    for (var i = 1; i < 5; i++) {
      final x = size.width * (i * 0.2);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadEdge);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }

    final avenue = Paint()..color = const Color(0xFFFFF6E1)..strokeWidth = 14..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height * 0.82), Offset(size.width, size.height * 0.12), avenue);

    final river = Paint()..color = const Color(0xFFCCE5EF)..strokeWidth = 20..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final riverPath = Path()
      ..moveTo(size.width * 0.12, -20)
      ..cubicTo(size.width * 0.28, size.height * 0.25, size.width * 0.02, size.height * 0.55, size.width * 0.22, size.height + 20);
    canvas.drawPath(riverPath, river);

    final route = Paint()
      ..color = const Color(0xFF0C8C86)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final routePath = Path()
      ..moveTo(size.width * 0.22, size.height * 0.78)
      ..cubicTo(size.width * 0.38, size.height * 0.62, size.width * 0.46, size.height * 0.58, size.width * 0.58, size.height * 0.48)
      ..cubicTo(size.width * 0.70, size.height * 0.38, size.width * 0.76, size.height * 0.34, size.width * 0.84, size.height * 0.24);
    canvas.drawPath(routePath, route);

    canvas.drawCircle(Offset(size.width * 0.22, size.height * 0.78), 9, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width * 0.22, size.height * 0.78), 5.5, Paint()..color = const Color(0xFF0C8C86));
    _drawPin(canvas, Offset(size.width * 0.84, size.height * 0.24), const Color(0xFFB3261E));

    if (driverAssigned) {
      final p = Offset(size.width * 0.52, size.height * 0.52);
      canvas.drawCircle(p, 20, Paint()..color = const Color(0x330C8C86));
      canvas.drawCircle(p, 12, Paint()..color = Colors.white);
      canvas.drawCircle(p, 6.5, Paint()..color = const Color(0xFF08222B));
    }

    if (hero) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'Thika · Boda pilot',
          style: TextStyle(fontSize: 10, color: Color(0xFF7A918A), fontWeight: FontWeight.w600, letterSpacing: 0.4),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(20, size.height - 26));
    }
  }

  void _drawPin(Canvas canvas, Offset center, Color color) {
    final pin = Paint()..color = color;
    final path = Path()
      ..moveTo(center.dx, center.dy + 12)
      ..cubicTo(center.dx - 12, center.dy - 4, center.dx - 9, center.dy - 16, center.dx, center.dy - 16)
      ..cubicTo(center.dx + 9, center.dy - 16, center.dx + 12, center.dy - 4, center.dx, center.dy + 12)
      ..close();
    canvas.drawPath(path, pin);
    canvas.drawCircle(Offset(center.dx, center.dy - 6), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RideMapPainter oldDelegate) =>
      oldDelegate.hero != hero || oldDelegate.driverAssigned != driverAssigned;
}

class TripsPage extends StatefulWidget {
  const TripsPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  List<Ride> _rides = [];
  Map<String, Payment?> _payments = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rides = await widget.api.rides();
      final payments = <String, Payment?>{};
      for (final ride in rides.where((r) => r.state == 'COMPLETED')) {
        try {
          payments[ride.id] = await widget.api.ridePayment(ride.id);
        } catch (_) {
          payments[ride.id] = null;
        }
      }
      if (!mounted) return;
      setState(() { _rides = rides; _payments = payments; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load trips. $e'; });
    }
  }

  String _statusLabel(String state) => switch (state) {
    'COMPLETED' => 'Completed',
    'CANCELLED' => 'Cancelled',
    'SEARCHING' => 'Searching',
    'ASSIGNED' || 'ARRIVING' || 'ARRIVED' => 'In progress',
    'IN_PROGRESS' => 'On trip',
    _ => state,
  };

  void _showReceipt(Ride ride) {
    final payment = _payments[ride.id];
    var selectedStars = 0;
    var submitted = false;
    var submitting = false;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Receipt', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${_fmtDate(ride.createdAt)} · ${_fmtTime(ride.createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.trip_origin, size: 16, color: Color(0xFF0C8C86)),
              const SizedBox(width: 8),
              Expanded(child: Text(ride.pickupAddress, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.place, size: 16, color: Color(0xFFB3261E)),
              const SizedBox(width: 8),
              Expanded(child: Text(ride.dropoffAddress, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const Divider(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Fare'),
              Text('KES ${ride.fare}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Payment · ${ride.paymentMethod.toUpperCase()}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text(
                payment?.status == 'SUCCESS' ? 'Paid' : payment?.status == 'PENDING' ? 'Pending' : 'Unpaid',
                style: TextStyle(fontWeight: FontWeight.w700, color: payment?.status == 'SUCCESS' ? const Color(0xFF0C8C86) : const Color(0xFFB26A00)),
              ),
            ]),
            if (payment?.receipt != null) ...[
              const SizedBox(height: 6),
              Text('Receipt: ${payment!.receipt}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 6),
            Text('Ride ${ride.id}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const Divider(height: 28),
            const Text('Rate your driver', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(submitted ? 'Thanks for the feedback — it helps the pilot.' : 'Tap a star to rate this trip.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Row(children: [
              for (var star = 1; star <= 5; star += 1)
                IconButton(
                  key: Key('rate_star_$star'),
                  visualDensity: VisualDensity.compact,
                  onPressed: submitted || submitting
                      ? null
                      : () async {
                          setSheetState(() { selectedStars = star; submitting = true; });
                          try {
                            await widget.api.rateRide(ride.id, star);
                            if (ctx.mounted) setSheetState(() { submitted = true; submitting = false; });
                          } catch (_) {
                            if (ctx.mounted) setSheetState(() { submitting = false; });
                          }
                        },
                  icon: Icon(selectedStars >= star ? Icons.star : Icons.star_border,
                      size: 32, color: selectedStars >= star ? const Color(0xFFF5B942) : const Color(0xFF8A9DA2)),
                ),
              if (submitting) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UkoTopBar(actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (_error != null) ...[
                          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
                          const SizedBox(height: 12),
                        ],
                        if (_rides.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                            child: Column(children: [
                              const Icon(Icons.receipt_long, size: 40, color: Color(0xFF8A9DA2)),
                              const SizedBox(height: 10),
                              const Text('No trips yet', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('Your completed rides and receipts will appear here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ]),
                          )
                        else
                          for (final ride in _rides) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE7E6))),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: ride.state == 'COMPLETED' ? () => _showReceipt(ride) : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Text(_fmtDate(ride.createdAt), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      Text(' · ${_fmtTime(ride.createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: ride.state == 'COMPLETED' ? const Color(0xFFE9F7F4) : const Color(0xFFF3F7F6), borderRadius: BorderRadius.circular(20)),
                                        child: Text(_statusLabel(ride.state), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ride.state == 'COMPLETED' ? const Color(0xFF0C8C86) : const Color(0xFF5C7077))),
                                      ),
                                    ]),
                                    const SizedBox(height: 8),
                                    Text('${ride.pickupAddress} → ${ride.dropoffAddress}', style: const TextStyle(fontSize: 13)),
                                    const SizedBox(height: 8),
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                      Text('KES ${ride.fare}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                      if (ride.state == 'COMPLETED')
                                        Text(
                                          _payments[ride.id]?.status == 'SUCCESS' ? 'Paid · receipt' : 'Payment pending',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _payments[ride.id]?.status == 'SUCCESS' ? const Color(0xFF0C8C86) : const Color(0xFFB26A00)),
                                        ),
                                    ]),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.api});
  final ApiClient api;
  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  final _destination = TextEditingController();
  List<String> _recent = [];
  List<SavedPlace> _saved = List.of(SavedPlacesStore.defaults);
  List<PlaceSuggestion> _suggestions = const [];
  bool _loadingRecent = true;
  bool _searching = false;
  Timer? _searchDebounce;

  IconData _placeIcon(String label) {
    switch (label.toLowerCase()) {
      case 'home':
        return Icons.home_outlined;
      case 'work':
        return Icons.work_outline;
      case 'airport':
        return Icons.flight_takeoff;
      case 'mall':
        return Icons.shopping_bag_outlined;
      default:
        return Icons.bookmark_outline;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await SavedPlacesStore.load();
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  Future<void> _editSaved(SavedPlace place) async {
    final controller = TextEditingController(text: place.label);
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename saved place'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Label')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    await SavedPlacesStore.update(place, label);
    await _loadSaved();
  }

  Future<void> _deleteSaved(SavedPlace place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${place.label}?'),
        content: Text(place.address),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await SavedPlacesStore.remove(place.label);
    await _loadSaved();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _destination.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() { _suggestions = const []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(Duration(milliseconds: query.length == 1 ? 60 : 130), () async {
      try {
        final places = await widget.api.searchPlaces(query);
        if (!mounted) return;
        setState(() { _suggestions = places; _searching = false; });
      } catch (_) {
        if (!mounted) return;
        setState(() { _suggestions = const []; _searching = false; });
      }
    });
  }

  void _choosePlace(PlaceSuggestion place) {
    Navigator.of(context).pop<PlaceSuggestion>(place);
  }

  Future<void> _chooseAddress(String address) async {
    setState(() => _searching = true);
    try {
      final places = await widget.api.searchPlaces(address);
      if (!mounted) return;
      setState(() => _searching = false);
      if (places.isNotEmpty) {
        _choosePlace(places.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find "$address". Try searching for the area or landmark.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  Future<void> _submitQuery() async {
    final query = _destination.text.trim();
    if (query.isEmpty) return;
    if (_suggestions.isNotEmpty) {
      _choosePlace(_suggestions.first);
    } else {
      await _chooseAddress(query);
    }
  }

  Future<void> _loadRecent() async {
    try {
      final rides = await widget.api.rides();
      final seen = <String>{};
      final recent = <String>[];
      for (final ride in rides.where((r) => r.state == 'COMPLETED')) {
        final address = ride.dropoffAddress.trim();
        if (address.isNotEmpty && seen.add(address)) {
          recent.add(address);
          if (recent.length == 3) break;
        }
      }
      if (!mounted) return;
      setState(() { _recent = recent; _loadingRecent = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFDCE7E6), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Where to?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sheet_destination'),
              controller: _destination,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search Thika, a landmark or address',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF0C8C86)),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward, color: Color(0xFF0C8C86)),
                        onPressed: _submitQuery,
                      ),
              ),
              onSubmitted: (_) => _submitQuery(),
            ),
            const SizedBox(height: 14),
            if (_destination.text.trim().isNotEmpty) ...[
              if (_suggestions.isEmpty && !_searching)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(children: [
                    const Icon(Icons.search_off, size: 36, color: Color(0xFF8A9DA2)),
                    const SizedBox(height: 8),
                    Text('No places found. Try a landmark like "Ananas Mall" or "Thika Town".',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ]),
                ),
              for (final place in _suggestions)
                ListTile(
                  key: Key('place_${place.id}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  leading: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.place_outlined, size: 20, color: Color(0xFF0C8C86)),
                  ),
                  title: Text(place.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(place.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.north_east, size: 16, color: Color(0xFF8A9DA2)),
                  onTap: () => _choosePlace(place),
                ),
            ] else ...[
              const Text('Saved places', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5C7077))),
              const SizedBox(height: 6),
              for (final place in _saved)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: const Color(0xFFE9F7F4), borderRadius: BorderRadius.circular(10)),
                    child: Icon(_placeIcon(place.label), size: 20, color: const Color(0xFF0C8C86)),
                  ),
                  title: Text(place.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(place.address, style: const TextStyle(fontSize: 12)),
                  trailing: PopupMenuButton<String>(
                    key: Key('saved_menu_${place.label}'),
                    icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF8A9DA2)),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editSaved(place);
                      } else if (value == 'delete') {
                        _deleteSaved(place);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
                  onTap: () => _choosePlace(PlaceSuggestion(
                    id: 'saved-${place.label}',
                    name: place.label,
                    address: place.address,
                    lat: place.lat,
                    lng: place.lng,
                  )),
                ),
              const SizedBox(height: 8),
              const Text('Recent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5C7077))),
              const SizedBox(height: 6),
              if (_loadingRecent)
                const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_recent.isEmpty)
                Text('No recent destinations yet', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              else
                for (final address in _recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, color: Color(0xFF8A9DA2)),
                    title: Text(address),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8A9DA2)),
                    onTap: () => _chooseAddress(address),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}


class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.api});
  final ApiClient api;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<UkoNotification> _items = [];
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
    final now = DateTime.now();
    final diff = now.difference(date);
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
                          Text('Trip updates and payment receipts will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF5C7077))),
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


const bool kRealMapsEnabled = bool.fromEnvironment('UKO_REAL_MAPS', defaultValue: true);
const _ukoPickup = LatLng(-1.0333, 37.0693);
const _ukoDropoff = LatLng(-1.0408, 37.0910);

/// Real Google map when built with `--dart-define=UKO_REAL_MAPS=true` and a
/// Maps API key configured; otherwise falls back to the offline stylised map.
class UkoMap extends StatefulWidget {
  const UkoMap({super.key, this.hero = false, this.pickup, this.dropoff, this.driverAssigned = false, this.pickupPoint, this.dropoffPoint, this.driverPoint, this.routePoints});
  final bool hero;
  final String? pickup;
  final String? dropoff;
  final bool driverAssigned;
  final LatLng? pickupPoint;
  final LatLng? dropoffPoint;
  final LatLng? driverPoint;
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

  Widget _fallback() => RideMap(
        hero: widget.hero,
        pickup: widget.pickup,
        dropoff: widget.dropoff,
        driverAssigned: widget.driverAssigned,
      );

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
    final driverPoint = widget.driverPoint;
    final routePoints = widget.routePoints;
    return Stack(fit: StackFit.expand, children: [
      FlutterMap(
        key: ValueKey('${start.latitude},${start.longitude}-${end.latitude},${end.longitude}-${routePoints?.length ?? 0}'),
        options: MapOptions(
          initialCenter: LatLng((start.latitude + end.latitude) / 2, (start.longitude + end.longitude) / 2),
          initialZoom: 12.5,
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([...?routePoints, start, end, if (driverPoint != null) driverPoint]),
            padding: const EdgeInsets.all(28),
            maxZoom: 14.5,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'ke.uko.rider',
            maxZoom: 19,
          ),
          if (routePoints != null)
            PolylineLayer(polylines: [
              Polyline(points: routePoints, strokeWidth: 4, color: const Color(0xFF0C8C86)),
            ]),
          if (!widget.hero || routePoints != null || driverPoint != null || widget.pickupPoint != null || widget.dropoffPoint != null)
            MarkerLayer(markers: [
              Marker(point: start, width: 44, height: 44, child: const Icon(Icons.trip_origin, color: Color(0xFF0C8C86), size: 30)),
              Marker(point: end, width: 44, height: 44, child: const Icon(Icons.location_on, color: Color(0xFFB3261E), size: 34)),
              if (driverPoint != null)
                Marker(
                  point: driverPoint,
                  width: 46,
                  height: 46,
                  child: Container(
                    decoration: const BoxDecoration(color: Color(0xFF08222B), shape: BoxShape.circle),
                    child: const Icon(Icons.two_wheeler, color: Colors.white, size: 26),
                  ),
                ),
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


class _PlaceSuggestions extends StatelessWidget {
  const _PlaceSuggestions({required this.places, required this.onSelected});
  final List<PlaceSuggestion> places;
  final ValueChanged<PlaceSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E2E0)),
      ),
      child: Column(
        children: places.take(5).map((place) => ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, size: 18),
              title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onSelected(place),
            )).toList(),
      ),
    );
  }
}


class RouteMapPage extends StatefulWidget {
  const RouteMapPage({
    super.key,
    required this.title,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupPoint,
    required this.dropoffPoint,
    this.route,
    this.driverPoint,
  });
  final String title;
  final String pickupAddress;
  final String dropoffAddress;
  final LatLng pickupPoint;
  final LatLng dropoffPoint;
  final RouteResult? route;
  final LatLng? driverPoint;

  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  final MapController _map = MapController();
  static const _zoom = 13.5;

  @override
  Widget build(BuildContext context) {
    final start = widget.pickupPoint;
    final end = widget.dropoffPoint;
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
              padding: const EdgeInsets.only(top: 190, bottom: 350, left: 30, right: 30),
              maxZoom: 15,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ke.uko.rider',
              maxZoom: 19,
            ),
            PolylineLayer(polylines: [
              Polyline(points: route?.points ?? const [], strokeWidth: 5, color: const Color(0xFF0C8C86)),
            ]),
            MarkerLayer(markers: [
              Marker(point: start, width: 46, height: 46, child: const Icon(Icons.trip_origin, color: Color(0xFF0C8C86), size: 32)),
              Marker(point: end, width: 46, height: 46, child: const Icon(Icons.location_on, color: Color(0xFFB3261E), size: 36)),
              if (widget.driverPoint != null)
                Marker(point: widget.driverPoint!, width: 46, height: 46, child: Container(
                  decoration: const BoxDecoration(color: Color(0xFF08222B), shape: BoxShape.circle),
                  child: const Icon(Icons.two_wheeler, color: Colors.white, size: 26),
                )),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Material(color: Colors.white, shape: const CircleBorder(), child: IconButton(
              key: const Key('map_back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            )),
            const SizedBox(width: 10),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), overflow: TextOverflow.ellipsis),
            )),
          ]),
        )),
        Positioned(
          top: 90, left: 12, right: 90,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.97), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(route == null ? 'Calculating route…' : '${route.distanceKm} km · about ${route.durationMin} min',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('${widget.pickupAddress} → ${widget.dropoffAddress}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
            ]),
          ),
        ),
        Positioned(
          right: 12, bottom: 330,
          child: Column(children: [
            _MapButton(icon: Icons.add, onTap: () => _map.move(_map.camera.center, _map.camera.zoom + 1)),
            const SizedBox(height: 8),
            _MapButton(icon: Icons.remove, onTap: () => _map.move(_map.camera.center, _map.camera.zoom - 1)),
            const SizedBox(height: 8),
            _MapButton(icon: Icons.my_location, onTap: () => _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(route?.points ?? [start, end]), padding: const EdgeInsets.only(top: 190, bottom: 350, left: 30, right: 30), maxZoom: 15))),
          ]),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: const Color(0xFFD7E2E0), borderRadius: BorderRadius.circular(2))),
              Row(children: [
                const Icon(Icons.alt_route, size: 18, color: Color(0xFF0C8C86)),
                const SizedBox(width: 8),
                const Text('Turn-by-turn', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                Text(route == null ? '' : '${route.steps.length} steps', style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
              ]),
              const SizedBox(height: 8),
              Flexible(child: route == null || route.steps.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Route directions are unavailable for this trip.', style: TextStyle(color: Color(0xFF5C7077))))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: route.steps.length,
                      itemBuilder: (context, i) {
                        final step = route.steps[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.turn_right, size: 16, color: Color(0xFF0C8C86)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(step.instruction, style: const TextStyle(fontSize: 13))),
                            const SizedBox(width: 8),
                            Text(step.distanceM >= 1000 ? '${(step.distanceM / 1000).toStringAsFixed(1)} km' : '${step.distanceM} m',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF5C7077))),
                          ]),
                        );
                      },
                    )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('open_google_maps'),
                  onPressed: () async {
                    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&travelmode=driving');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Open in Google Maps'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    child: IconButton(icon: Icon(icon, size: 20), onPressed: onTap),
  );
}
