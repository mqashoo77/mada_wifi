import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'parental.dart';

export 'parental.dart';

const routerHost = 'www.webgui.Nokiawifi.com';

class RouterApi {
  late Dio _dio;

  void configure() {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://$routerHost',
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _dio.interceptors.add(CookieManager(CookieJar()));
  }

  dynamic _decode(dynamic data) {
    if (data is! String) return data;
    try {
      return jsonDecode(data);
    } catch (_) {}
    for (final pair in const [('{', '}'), ('[', ']')]) {
      final s = data.indexOf(pair.$1), e = data.lastIndexOf(pair.$2);
      if (s != -1 && e > s) {
        try {
          return jsonDecode(data.substring(s, e + 1));
        } catch (_) {}
      }
    }
    return data;
  }

  Future<Response> _authed(
      String path, Future<Response> Function() send) async {
    try {
      return await send();
    } on DioException catch (e) {
      final canRelogin = e.response?.statusCode == 403 &&
          _user != null &&
          !path.startsWith('/login_app.cgi');
      if (!canRelogin) rethrow;
      await relogin();
      return send();
    }
  }

  Future<dynamic> _get(String path) async =>
      _decode((await _authed(path, () => _dio.get(path))).data);

  Future<dynamic> _postForm(String path, Map<String, dynamic> form) async =>
      _decode((await _dio.post(path,
              data: form,
              options: Options(contentType: Headers.formUrlEncodedContentType)))
          .data);

  Future<dynamic> _postJson(String path, Object body) async =>
      _decode((await _authed(
              path,
              () => _dio.post(path,
                  data: jsonEncode(body),
                  options: Options(contentType: 'application/json'))))
          .data);

  String? _user, _pass;

  Future<void> login(String user, String pass) async {
    await _postForm('/login_app.cgi', {'name': user, 'pswd': pass, 'srip': ''});
    _user = user;
    _pass = pass;
    await _get('/device_status_app.cgi');
  }

  Future<void> relogin() async {
    _dio.interceptors.removeWhere((i) => i is CookieManager);
    _dio.interceptors.add(CookieManager(CookieJar()));
    await _postForm(
        '/login_app.cgi', {'name': _user, 'pswd': _pass, 'srip': ''});
  }

  Future<void> logout() async {
    await _closeEventSocket();
    try {
      await _get('/login_app.cgi?out');
    } catch (_) {}
  }

  Future<dynamic> internetStatus() => _get('/wan_internet_status_app.cgi');

  Future<dynamic> connectedDevices() async {
    final results = <String, dynamic>{};
    final errors = <String>[];
    try {
      results[liveDevicesKey] = await liveDevices();
    } catch (e) {
      errors.add('$liveDevicesKey: ${describeError(e)}');
      debugPrint('AllDeviceInfo failed: $e');
    }
    for (final path in const [
      deviceHistoryPath,
      wlanClientsPath,
    ]) {
      try {
        results[path] = await _get(path);
      } catch (e) {
        errors.add('$path: $e');
      }
    }
    if (results.isEmpty) throw Exception(errors.join('\n'));
    return results;
  }

  Future<dynamic> wlanList() => _get('/wlan_list_app.cgi');

  Future<dynamic> setWifi({
    required int id,
    required bool enable,
    required String ssid,
    required String password,
  }) async {
    final body = {
      'action': 'WLANConfig',
      'paralist': [
        {
          'id': [id],
          'Enable': enable ? 'true' : 'false',
          'SSID': ssid,
          'PreSharedKey': password,
        }
      ],
    };
    lastSaveReply = null;
    debugPrint('WLANConfig request: ${jsonEncode(body)}');
    await _openEventSocket();
    final session = await _sessionStart();
    final dynamic reply;
    try {
      reply = await _postJson('/service_function2_app.cgi', body);
    } finally {
      lastSaveReply = 'session: $session; save: no reply (connection closed)';
    }
    lastSaveReply =
        'session: $session; save: ${reply is String ? reply : jsonEncode(reply)}';
    debugPrint('WLANConfig reply:   $lastSaveReply');
    unawaited(_sessionStop());
    final result = reply is Map ? reply['result'] : null;
    if (result != null && '$result' != '0') {
      throw RouterRejected('Router rejected the change (result $result'
          '${reply['reason'] != null ? ', reason ${reply['reason']}' : ''}).');
    }
    return reply;
  }

  String? lastSaveReply;

  WebSocket? _ws;

  Future<void> _openEventSocket() async {
    if (_ws != null && _ws!.closeCode == null) return;
    try {
      final ws = await WebSocket.connect('ws://$routerHost:8099')
          .timeout(const Duration(seconds: 5));
      ws.add(base64Encode(utf8.encode('$_user:$_pass')));
      ws.listen((m) => debugPrint('ws 8099: $m'),
          onError: (_) {}, onDone: () => _ws = null, cancelOnError: true);
      _ws = ws;
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('ws 8099 not available: $e');
    }
  }

  Future<void> _closeEventSocket() async {
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  Future<String> _sessionStart() async {
    final replies = <String>[];
    for (final cmd in const ['Session_START{Mobile}', 'Session_STARTMobile']) {
      try {
        final r = _decode(await _postRaw(
            '/websoc_session_app.cgi', 'command=$cmd&timeout=1800'));
        final text = r is String ? r : jsonEncode(r);
        replies.add('$cmd -> $text');
        final result = r is Map ? r['result'] : null;
        if (result == null || '$result' == '0') break;
      } catch (e) {
        replies.add('$cmd -> ${describeError(e)}');
      }
    }
    debugPrint('sessionStart: ${replies.join(' | ')}');
    return replies.join(' | ');
  }

  Future<String> _postRaw(String path, String body) async {
    final r = await _dio.post(path,
        data: body,
        options: Options(contentType: Headers.formUrlEncodedContentType));
    return '${r.data}';
  }

  Future<List<Map<String, dynamic>>> liveDevices(
      {Duration timeout = const Duration(seconds: 15)}) async {
    final ws = await WebSocket.connect('ws://$routerHost:8099')
        .timeout(const Duration(seconds: 5));
    final done = Completer<List<Map<String, dynamic>>>();
    final sub = ws.listen((m) async {
      final text = '$m'.trim();
      final compact = text.toLowerCase().replaceAll(' ', '');
      if (compact == '200ok') {
        await _sessionStart();
        return;
      }
      if (compact.startsWith('401')) {
        if (!done.isCompleted) {
          done.completeError(Exception('WebSocket login refused (401)'));
        }
        return;
      }
      try {
        final j = jsonDecode(text);
        if (j is Map && j['event'] == 'AllDeviceInfo' && !done.isCompleted) {
          done.complete([
            for (final d in (j['payload'] as List? ?? const []))
              if (d is Map) Map<String, dynamic>.from(d),
          ]);
        }
      } catch (_) {}
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    }, onDone: () {
      if (!done.isCompleted) {
        done.completeError(Exception('WebSocket closed before AllDeviceInfo'));
      }
    });
    ws.add(base64Encode(utf8.encode('$_user:$_pass')));
    try {
      return await done.future.timeout(timeout);
    } finally {
      await sub.cancel();
      await ws.close();
    }
  }

  Future<void> _sessionStop() async {
    try {
      await _postRaw('/websoc_session_app.cgi', 'command=Session_STOP{Mobile}');
    } catch (_) {}
  }


  Future<List<ParentalProfile>> parentalProfiles() async =>
      parseProfiles(await _get('$parentalStatusPath?gmode=getallinfo'));

  Future<Map> parentalSet(String body) async {
    debugPrint('parental request: $body');
    await _openEventSocket();
    await _sessionStart();
    final dynamic reply;
    try {
      reply = _decode(await _authedRaw(
          parentalSetPath, () => _postRaw(parentalSetPath, body)));
    } finally {
      unawaited(_sessionStop());
    }
    debugPrint('parental reply:   $reply');
    if (reply is! Map) {
      throw RouterRejected('Unexpected router reply: $reply');
    }
    final result = '${reply['result'] ?? 0}';
    if (result != '0') {
      throw RouterRejected('Router rejected the change (result $result'
          '${reply['reason'] != null ? ', reason ${reply['reason']}' : ''}).');
    }
    return reply;
  }

  Future<String> _authedRaw(String path, Future<String> Function() send) async {
    try {
      return await send();
    } on DioException catch (e) {
      if (e.response?.statusCode != 403 || _user == null) rethrow;
      await relogin();
      return send();
    }
  }
}

class RouterRejected implements Exception {
  final String message;
  RouterRejected(this.message);
  @override
  String toString() => message;
}

bool isConnectionDrop(Object e) =>
    e is DioException &&
    e.response == null &&
    (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.unknown);

String describeError(Object e) {
  if (e is! DioException) return e.toString();
  final path = e.requestOptions.path;
  final status = e.response?.statusCode;
  if (status != null) {
    var body = (e.response?.data ?? '').toString().trim();
    body = body
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (body.length > 150) body = '${body.substring(0, 150)}…';
    return 'Router refused $path (HTTP $status)${body.isEmpty ? '' : ': $body'}';
  }
  return switch (e.type) {
    DioExceptionType.connectionTimeout =>
      'Router not reachable ($path timed out)',
    DioExceptionType.receiveTimeout => 'Router did not answer $path in time',
    _ => 'Connection to router lost ($path)',
  };
}

List<Map<String, dynamic>> extractList(dynamic data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (data is Map) {
    for (final v in data.values) {
      final l = extractList(v);
      if (l.isNotEmpty) return l;
    }
  }
  return [];
}

final _macRe = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');

const deviceHistoryPath = '/device_name_status_app.cgi?gmode=all';
const wlanClientsPath = '/wlan_devices_status_app.cgi';
const liveDevicesKey = 'ws:AllDeviceInfo';

List<Map<String, dynamic>> _liveConnected(
    List live, Map<String, Map<String, dynamic>> history) {
  final out = <Map<String, dynamic>>[];
  for (final d in live) {
    if (d is! Map) continue;
    if ('${d['active']}' != '1' && d['active'] != true) continue;
    if (d['isBeacon'] == true || '${d['isBeacon']}' == '1') continue;
    final mac = _normMac('${d['mac'] ?? ''}');
    String name = '${d['friendlyname'] ?? ''}'.trim();
    if (name.isEmpty) name = '${d['host'] ?? ''}'.trim();
    final h = history[mac];
    if (name.isEmpty && h != null) {
      name = pick(h, ['HostAlias'], '').trim();
      if (name.isEmpty) name = pick(h, ['HostName'], '').trim();
    }
    out.add({
      'HostName': name.isEmpty ? mac : name,
      'IPAddress': d['ip'] ?? '',
      'MACAddress': mac,
      'Interface': d['interface'] ?? '',
      if (d['ssid'] != null) 'SSID': d['ssid'],
      if (d['band'] != null) 'Band': d['band'],
    });
  }
  out.sort((a, b) => '${a['HostName']}'
      .toLowerCase()
      .compareTo('${b['HostName']}'.toLowerCase()));
  return out;
}

String _normMac(String mac) => mac.trim().toLowerCase().replaceAll('-', ':');

List<Map<String, dynamic>> connectedClients(dynamic raw) {
  if (raw is Map && raw[liveDevicesKey] is List) {
    final history = {
      for (final d in _extractDevices(raw[deviceHistoryPath]))
        _normMac(pick(d, ['mac', 'macaddress'], '')): d,
    };
    return _liveConnected(raw[liveDevicesKey] as List, history);
  }
  if (raw is! Map || !raw.containsKey(wlanClientsPath)) {
    return _extractDevices(raw);
  }
  final wlan = raw[wlanClientsPath];

  final liveByMac = <String, Map<String, dynamic>>{};
  for (final d in _extractDevices(wlan)) {
    final mac = _normMac(pick(d, ['mac', 'macaddress', 'macaddr'], ''));
    if (_macRe.hasMatch(mac)) liveByMac.putIfAbsent(mac, () => d);
  }

  final macs = <String>{...liveByMac.keys, ...findMacs(wlan)};

  final history = {
    for (final d in _extractDevices(raw[deviceHistoryPath]))
      _normMac(pick(d, ['mac', 'macaddress'], '')): d,
  };
  return [
    for (final mac in macs)
      _withName({
        'MACAddress': mac,
        ...?history[mac],
        ...?liveByMac[mac],
      }..removeWhere((k, v) => v == null)),
  ];
}

final _macAnywhere = RegExp(
    r'(?<![0-9A-Fa-f])([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f])');
final _bareMac = RegExp(r'^[0-9A-Fa-f]{12}$');

Set<String> findMacs(dynamic data) {
  final out = <String>{};
  void addFrom(String s, {bool macKey = false}) {
    for (final m in _macAnywhere.allMatches(s)) {
      out.add(_normMac(m.group(0)!));
    }
    final t = s.trim();
    if (macKey && _bareMac.hasMatch(t)) {
      out.add([for (var i = 0; i < 12; i += 2) t.substring(i, i + 2)]
          .join(':')
          .toLowerCase());
    }
  }

  void walk(dynamic d, {bool macKey = false}) {
    if (d is Map) {
      d.forEach((k, v) {
        addFrom('$k');
        walk(v, macKey: '$k'.toLowerCase().contains('mac'));
      });
    } else if (d is List) {
      for (final e in d) {
        walk(e, macKey: macKey);
      }
    } else if (d != null) {
      addFrom('$d', macKey: macKey);
    }
  }

  walk(data);
  out.removeWhere((m) => m == '00:00:00:00:00:00' || m == 'ff:ff:ff:ff:ff:ff');
  return out;
}

Map<String, dynamic> _withName(Map<String, dynamic> m) {
  final name = pick(m, ['hostname', 'devicename', 'name', 'host'], '');
  if (name.trim().isNotEmpty) return m;
  final alias = pick(m, ['hostalias'], '');
  return alias.trim().isEmpty ? m : {...m, 'HostName': alias};
}

List<Map<String, dynamic>> _extractDevices(dynamic data) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  void walk(dynamic d) {
    if (d is List) {
      for (final e in d) {
        walk(e);
      }
    } else if (d is Map) {
      final m = Map<String, dynamic>.from(d);
      final mac = pick(m, ['mac', 'macaddress', 'macaddr', 'mac_addr'], '');
      if (_macRe.hasMatch(mac.trim())) {
        if (seen.add(mac.toLowerCase())) out.add(m);
      } else {
        for (final v in m.values) {
          walk(v);
        }
      }
    }
  }

  walk(data);
  return out.isNotEmpty ? out : extractList(data);
}

bool? isInternetUp(dynamic data) {
  if (data is! Map || data['gwwanup'] == null) return null;
  return '${data['gwwanup']}'.trim() == '1' || data['gwwanup'] == true;
}

String pick(Map<String, dynamic> m, List<String> keys,
    [String fallback = '-']) {
  for (final k in keys) {
    for (final e in m.entries) {
      if (e.key.toLowerCase() == k.toLowerCase() && e.value != null) {
        return e.value.toString();
      }
    }
  }
  for (final k in keys) {
    for (final e in m.entries) {
      if (e.key.toLowerCase().contains(k.toLowerCase()) &&
          e.value != null &&
          e.value is! Map &&
          e.value is! List) {
        return e.value.toString();
      }
    }
  }
  return fallback;
}
