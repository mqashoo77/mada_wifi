import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/api.dart';

class ParentalState {
  final bool loading;
  final bool saving;
  final String? error;
  final String? message;
  final List<ParentalProfile> profiles;

  final List<Map<String, dynamic>> clients;
  const ParentalState({
    this.loading = false,
    this.saving = false,
    this.error,
    this.message,
    this.profiles = const [],
    this.clients = const [],
  });

  ParentalState copyWith({
    bool? loading,
    bool? saving,
    String? error,
    String? message,
    List<ParentalProfile>? profiles,
    List<Map<String, dynamic>>? clients,
  }) =>
      ParentalState(
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        error: error,
        message: message,
        profiles: profiles ?? this.profiles,
        clients: clients ?? this.clients,
      );

  ParentalProfile? profile(int id) =>
      profiles.where((p) => p.id == id).firstOrNull;

  String deviceName(String mac, [String fallback = '']) {
    final m = normMac(mac);
    for (final c in clients) {
      if (normMac(pick(c, ['mac', 'macaddress'], '')) == m) {
        final n = pick(c, ['hostname', 'devicename', 'name', 'host'], '');
        if (n.trim().isNotEmpty && normMac(n) != m) return n;
      }
    }
    return fallback.isNotEmpty ? fallback : m;
  }

  bool isOnline(String mac) => clients
      .any((c) => normMac(pick(c, ['mac', 'macaddress'], '')) == normMac(mac));

  ParentalProfile? ownerOf(String mac) =>
      profiles.where((p) => p.hasDevice(mac)).firstOrNull;
}

class ParentalCubit extends Cubit<ParentalState> {
  final RouterApi api;
  ParentalCubit(this.api) : super(const ParentalState());

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final clients = api
        .connectedDevices()
        .then(connectedClients)
        .catchError((_) => state.clients);
    try {
      final profiles = await api.parentalProfiles();
      emit(state.copyWith(loading: false, profiles: profiles));
    } catch (e) {
      emit(state.copyWith(loading: false, error: describeError(e)));
    }
    final c = await clients;
    if (!isClosed) emit(state.copyWith(clients: c));
  }

  Future<void> _refreshProfiles() async {
    emit(state.copyWith(saving: true, profiles: await api.parentalProfiles()));
  }

  Future<bool> _change(String done, List<String> bodies) async {
    if (state.saving) return false;
    emit(state.copyWith(saving: true));
    try {
      for (final b in bodies) {
        await api.parentalSet(b);
      }
      await _refreshProfiles();
      emit(state.copyWith(saving: false, message: done));
      return true;
    } catch (e) {
      try {
        await _refreshProfiles();
      } catch (_) {}
      emit(state.copyWith(saving: false, error: describeError(e)));
      return false;
    }
  }

  Future<int?> createProfile(String name, Iterable<String> macs) async {
    if (state.saving) return null;
    emit(state.copyWith(saving: true));
    try {
      final reply = await api.parentalSet(createProfileBody(name));
      await _refreshProfiles();
      final pid = int.tryParse('${reply['newgrpschidx'] ?? ''}') ??
          state.profiles.where((p) => p.name == name).firstOrNull?.id;
      if (pid == null) throw RouterRejected('Profile created but not found.');
      final moves = movesInto(state.profiles, pid, macs);
      if (moves.isNotEmpty) {
        await api.parentalSet(moveDevicesBody(moves));
        await _refreshProfiles();
      }
      emit(state.copyWith(saving: false, message: 'Profile "$name" created'));
      return pid;
    } catch (e) {
      try {
        await _refreshProfiles();
      } catch (_) {}
      emit(state.copyWith(saving: false, error: describeError(e)));
      return null;
    }
  }

  Future<bool> deleteProfile(ParentalProfile p) =>
      _change('Profile "${p.name}" deleted', [deleteProfileBody(p.id)]);

  Future<bool> setInternet(ParentalProfile p, bool on) => _change(
      on ? 'Internet resumed for ${p.name}' : 'Internet paused for ${p.name}',
      [internetAccessBody(p.id, on)]);

  Future<bool> addDevices(ParentalProfile p, Iterable<String> macs) {
    final moves = movesInto(state.profiles, p.id, macs);
    if (moves.isEmpty) return Future.value(true);
    return _change('Devices added to ${p.name}', [moveDevicesBody(moves)]);
  }

  Future<bool> removeDevice(ParentalProfile p, PcDevice d) =>
      _change('Device removed from ${p.name}', [
        moveDevicesBody([
          moveToHome(state.profiles, p, [d.id])
        ])
      ]);

  Future<bool> saveSchedule(
    ParentalProfile p, {
    PcSchedule? existing,
    required bool bedtime,
    required String name,
    required String start,
    required String end,
    required List<int> days,
  }) =>
      _change(existing == null ? 'Schedule added' : 'Schedule saved', [
        scheduleBody(
          pid: p.id,
          schid: existing?.id ?? 0,
          enabled: existing?.enabled ?? true,
          bedtime: bedtime,
          name: name,
          start: start,
          end: end,
          days: days,
        )
      ]);

  Future<bool> toggleSchedule(ParentalProfile p, PcSchedule s, bool on) =>
      _change(on ? 'Schedule on' : 'Schedule off',
          [scheduleToggleBody(p.id, s.id, on)]);

  Future<bool> deleteSchedule(ParentalProfile p, PcSchedule s) =>
      _change('Schedule deleted', [deleteScheduleBody(p.id, s.id)]);

  Future<bool> setWebsiteFiltering(ParentalProfile p, bool on) => _change(
      on ? 'Website filtering on' : 'Website filtering off',
      [urlFilterBody(p, on)]);

  Future<bool> blockSite(ParentalProfile p, String site) =>
      _change('$site blocked', [addUrlBody(p, site)]);

  Future<bool> unblockSite(ParentalProfile p, PcUrl u) =>
      _change('${u.address} unblocked', [deleteUrlBody(p.id, u.id)]);
}
