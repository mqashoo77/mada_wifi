import 'dart:convert';


const parentalStatusPath = '/parental_ctrl_nok_status_app.cgi';
const parentalSetPath = '/parental_ctrl_nok_app.cgi';

const _hiddenProfilePrefix = 'hidden_nwcc';

const maxProfileNameLength = 15;
const maxScheduleNameLength = 15;
final profileNameRe = RegExp(r"^[\u0080-￿a-zA-Z0-9.@#'’_ \-]+$");

const weekDayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class PcDevice {
  final int id;
  final String mac;
  final String name;
  const PcDevice({required this.id, required this.mac, required this.name});
}

class PcSchedule {
  final int id;
  final String name;
  final bool enabled;
  final bool bedtime;
  final String start;
  final String end;
  final List<int> days;
  const PcSchedule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.bedtime,
    required this.start,
    required this.end,
    required this.days,
  });
}

class PcUrl {
  final int id;
  final String address;
  const PcUrl({required this.id, required this.address});
}

class ParentalProfile {
  final int id;
  final String name;
  final bool isHome;
  final bool internetOn;
  final List<PcDevice> devices;
  final List<PcSchedule> schedules;
  final int urlFilterId;
  final bool urlFilterOn;
  final List<PcUrl> urls;
  const ParentalProfile({
    required this.id,
    required this.name,
    required this.isHome,
    required this.internetOn,
    required this.devices,
    required this.schedules,
    required this.urlFilterId,
    required this.urlFilterOn,
    required this.urls,
  });

  bool hasDevice(String mac) => devices.any((d) => d.mac == normMac(mac));
}

String normMac(String mac) => mac.trim().toLowerCase().replaceAll('-', ':');

int _int(dynamic v, [int fallback = 0]) => v is int
    ? v
    : (v is num ? v.toInt() : int.tryParse('$v'.trim()) ?? fallback);

bool _flag(dynamic v) {
  final s = '$v'.trim().toLowerCase();
  return s == '1' || s == 'true' || s == 'on';
}

String _str(Map m, List<String> keys) {
  for (final k in keys) {
    for (final e in m.entries) {
      if ('${e.key}'.toLowerCase() == k.toLowerCase() &&
          e.value != null &&
          e.value is! Map &&
          e.value is! List) {
        final s = '${e.value}'.trim();
        if (s.isNotEmpty) return s;
      }
    }
  }
  return '';
}

List<Map> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().toList() : (v is Map ? [v] : const []);

dynamic _find(dynamic data, String key) {
  if (data is Map) {
    if (data.containsKey(key)) return data[key];
    for (final v in data.values) {
      final r = _find(v, key);
      if (r != null) return r;
    }
  } else if (data is List) {
    for (final v in data) {
      final r = _find(v, key);
      if (r != null) return r;
    }
  }
  return null;
}

List<ParentalProfile> parseProfiles(dynamic data) {
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return const [];
    }
  }
  final list = _maps(_find(data, 'NPCProfileList'));
  final out = <ParentalProfile>[];
  for (final p in list) {
    final name = _str(p, ['Name', 'ProfileName']);
    if (name.startsWith(_hiddenProfilePrefix)) continue;
    final isHome = _int(p['HomeGroup']) == 1;
    final filter = _maps(p['UrlFilter']);
    final f = filter.isEmpty ? const {} : filter.first;
    out.add(ParentalProfile(
      id: _int(p['_oid']),
      name: isHome && (name.isEmpty || name.toUpperCase() == 'HOME')
          ? 'Home'
          : name,
      isHome: isHome,
      internetOn: p['AccessInternet'] == null || _flag(p['AccessInternet']),
      devices: [
        for (final d in _maps(p['Device']))
          if (_str(d, ['MACAddress', 'mac']).isNotEmpty)
            PcDevice(
              id: _int(d['_oid'], -1),
              mac: normMac(_str(d, ['MACAddress', 'mac'])),
              name: _str(d, ['FriendlyName', 'HostAlias', 'HostName', 'Name']),
            ),
      ],
      schedules: [
        for (final s in _maps(p['Schedule']))
          PcSchedule(
            id: _int(s['_oid']),
            name: _str(s, ['Name']),
            enabled: _flag(s['Enable']),
            bedtime: _flag(s['IsBedtime']),
            start: _str(s, ['StartTime']),
            end: _str(s, ['EndTime']),
            days: parseDays('${s['DayOfWeek'] ?? ''}'),
          ),
      ],
      urlFilterId: _int(f['_oid']),
      urlFilterOn: _flag(f['UrlFilterEnable']),
      urls: [
        for (final u in _maps(f['UrlAddress']))
          if (_str(u, ['Address', 'UrlAddr']).isNotEmpty)
            PcUrl(
                id: _int(u['_oid']), address: _str(u, ['Address', 'UrlAddr'])),
      ],
    ));
  }
  out.sort((a, b) => a.isHome == b.isHome ? 0 : (a.isHome ? 1 : -1));
  return out;
}

List<int> parseDays(String s) => s
    .split(RegExp(r'[,\s]+'))
    .map(int.tryParse)
    .whereType<int>()
    .where((d) => d >= 0 && d <= 6)
    .toSet()
    .toList()
  ..sort();

String daysText(List<int> days) {
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && !days.contains(0) && !days.contains(6)) {
    return 'Weekdays';
  }
  if (days.length == 2 && days.contains(0) && days.contains(6)) {
    return 'Weekends';
  }
  return days.map((d) => weekDayNames[d]).join(', ');
}


String _enc(String s) => Uri.encodeComponent(s);

String createProfileBody(String name) =>
    'act=NPCSetProfile&pid=0&profileName=${_enc(name)}&internetCtrl=1';

String internetAccessBody(int pid, bool on) =>
    'act=NPCSetProfile&pid=$pid&profileName=&internetCtrl=${on ? 1 : 0}';

String deleteProfileBody(int pid) => 'act=NPCDeleteProfile&pid=$pid';

class DeviceMove {
  final int srcPid, destPid;
  final List<int> devIds;
  final List<String> macs;
  const DeviceMove(this.srcPid, this.destPid,
      {this.devIds = const [], this.macs = const []});
  Map<String, dynamic> toJson() => {
        'srcPid': srcPid,
        'destPid': destPid,
        if (devIds.isNotEmpty) 'devIdxs': devIds,
        if (macs.isNotEmpty) 'macIds': macs,
      };
}

String moveDevicesBody(List<DeviceMove> moves) =>
    'act=NPCMoveDevicesJsonArray&mvJsonArray='
    '${jsonEncode({
          'NPCDevMoveReqList': moves.map((m) => m.toJson()).toList()
        })}';

List<DeviceMove> movesInto(
    List<ParentalProfile> profiles, int destPid, Iterable<String> macs) {
  final home = profiles.where((p) => p.isHome).firstOrNull;
  final byProfile = <int, List<int>>{};
  final unknown = <String>[];
  for (final raw in macs) {
    final mac = normMac(raw);
    ParentalProfile? owner;
    PcDevice? dev;
    for (final p in profiles) {
      for (final d in p.devices) {
        if (d.mac == mac) {
          owner = p;
          dev = d;
        }
      }
    }
    if (owner?.id == destPid) continue;
    if (owner != null && dev != null && dev.id >= 0) {
      byProfile.putIfAbsent(owner.id, () => []).add(dev.id);
    } else {
      unknown.add(mac);
    }
  }
  return [
    for (final e in byProfile.entries)
      DeviceMove(e.key, destPid, devIds: e.value),
    if (unknown.isNotEmpty) DeviceMove(home?.id ?? 1, destPid, macs: unknown),
  ];
}

DeviceMove moveToHome(List<ParentalProfile> profiles, ParentalProfile profile,
        List<int> ids) =>
    DeviceMove(profile.id, profiles.where((p) => p.isHome).firstOrNull?.id ?? 1,
        devIds: ids);

String scheduleBody({
  required int pid,
  int schid = 0,
  bool enabled = true,
  required bool bedtime,
  String name = '',
  required String start,
  required String end,
  required List<int> days,
}) =>
    'act=NPCSetSchedule&parentid=$pid&schid=$schid'
    '&schEnable=${enabled ? 1 : 0}&schBedtime=${bedtime ? 1 : 0}'
    '&schName=${bedtime ? '' : _enc(name)}&startTime=$start&endTime=$end'
    '&dayOfWeek=${(days.toSet().toList()..sort()).join(',')}'
    '&schBedtimeOverride=0';

String scheduleToggleBody(int pid, int schid, bool enabled) =>
    'act=NPCSetSchedule&parentid=$pid&schid=$schid&schEnable=${enabled ? 1 : 0}'
    '&schBedtime=&schName=&startTime=&endTime=&dayOfWeek=&schBedtimeOverride=0';

String deleteScheduleBody(int pid, int schid) =>
    'act=NPCDeleteSchedule&parentid=$pid&schid=$schid';

String urlFilterBody(ParentalProfile p, bool on) =>
    'act=NPCSetUrl&parentid=${p.id}&urlid=${p.urlFilterId}'
    '&urlEnable=${on ? 1 : 0}&UrlFilterMode=black&UrlAddr=';

String addUrlBody(ParentalProfile p, String address) =>
    'act=NPCSetUrl&parentid=${p.id}&urlid=0'
    '&urlEnable=${p.urlFilterOn ? 1 : 0}&UrlFilterMode=black'
    '&UrlAddr=${_enc(address)}';

String deleteUrlBody(int pid, int urlId) =>
    'act=NPCDeleteUrl&parentid=$pid&urlid=$urlId';

String? cleanSite(String input) {
  var s = input.trim().toLowerCase();
  s = s.replaceFirst(RegExp(r'^[a-z]+://'), '');
  s = s.split(RegExp(r'[/?#]')).first;
  if (!RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(s)) return null;
  return s;
}
