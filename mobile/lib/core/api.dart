import 'ru.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class ApiFailure implements Exception {
  final String message;
  final int status;
  ApiFailure(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api extends ChangeNotifier {
  static const base = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  final storage = const FlutterSecureStorage();
  final http.Client client;
  Api({http.Client? client}) : client = client ?? http.Client();
  String? token;
  String device = '';
  Map<String, dynamic>? me;
  Map<String, dynamic> health = {};
  final Map<String, Uint8List> images = {};
  final Map<String, Future<Uint8List>> inflight = {};
  int epoch = 0;
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  Future<dynamic> call(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final r = http.Request(method, Uri.parse('$base$path'))
        ..headers.addAll(headers);
      if (data != null) r.body = jsonEncode(data);
      final response = await http.Response.fromStream(
        await client.send(r).timeout(const Duration(seconds: 25)),
      );
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && token != null) await clear();
        throw ApiFailure(
          value['detail'] is String ? value['detail'] : Ru.text80,
          response.statusCode,
        );
      }
      return value;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure(Ru.text79);
    }
  }

  Future<void> init() async {
    device = await storage.read(key: 'device') ?? const Uuid().v4();
    await storage.write(key: 'device', value: device);
    token = await storage.read(key: 'token');
    health = Map<String, dynamic>.from(await call('GET', '/health'));
    if (token != null) await refreshMe();
  }

  Future<void> login(String value) async {
    epoch++;
    images.clear();
    inflight.clear();
    token = value;
    await storage.write(key: 'token', value: value);
    await refreshMe();
  }

  Future<void> refreshMe() async {
    me = Map<String, dynamic>.from(await call('GET', '/me'));
    notifyListeners();
  }

  Future<void> clear() async {
    epoch++;
    token = null;
    me = null;
    images.clear();
    inflight.clear();
    await storage.delete(key: 'token');
    notifyListeners();
  }

  Future<String> upload(Uint8List bytes, String scope) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw ApiFailure(Ru.text78);
    }
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$base/media?scope=$scope'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'photo.jpg'),
      );
      final r = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 45)),
      );
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode >= 400) throw ApiFailure(d['detail'] as String);
      return d['id'] as String;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure(Ru.text77);
    }
  }

  Future<Uint8List> photo(String id) {
    if (images.containsKey(id)) return Future.value(images[id]);
    return inflight.putIfAbsent(id, () async {
      final generation = epoch;
      try {
        final r = await client
            .get(Uri.parse('$base/media/$id'), headers: headers)
            .timeout(const Duration(seconds: 25));
        if (r.statusCode != 200 || generation != epoch) {
          throw ApiFailure(Ru.text76);
        }
        // RAM only. Private files are never written to a public disk cache.
        if (images.length > 48) images.clear();
        images[id] = r.bodyBytes;
        return r.bodyBytes;
      } finally {
        inflight.remove(id);
      }
    });
  }

  void invalidateImages() {
    images.clear();
    inflight.clear();
  }
}
