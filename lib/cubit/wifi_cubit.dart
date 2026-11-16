import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/api.dart';

class WifiState {
  final bool loading;
  final String? error;
  final String? message;
  final List<Map<String, dynamic>> networks;
  const WifiState({
    this.loading = false,
    this.error,
    this.message,
    this.networks = const [],
  });
}

class WifiCubit extends Cubit<WifiState> {
  final RouterApi api;
  WifiCubit(this.api) : super(const WifiState());

  static const _reconnectTimeout = Duration(seconds: 90);
  static const _retryEvery = Duration(seconds: 5);

  Future<void> load() async {
    emit(WifiState(loading: true, networks: state.networks));
    try {
      emit(WifiState(networks: extractList(await api.wlanList())));
    } catch (e) {
      emit(WifiState(networks: state.networks, error: describeError(e)));
    }
  }

  Future<void> save({
    required Map<String, dynamic> network,
    required int id,
    required String ssid,
    required String password,
    required bool enable,
  }) async {
    final current = state.networks;
    emit(WifiState(loading: true, networks: current, message: 'Saving…'));
    try {
      await api.setWifi(id: id, enable: enable, ssid: ssid, password: password);
    } catch (e) {
      if (!isConnectionDrop(e)) {
        emit(WifiState(networks: current, error: describeError(e)));
        return;
      }
      emit(WifiState(
          loading: true,
          networks: current,
          message: 'Router is applying the change and restarting WiFi. '
              'Reconnecting…'));
    }
    await _verify(id, ssid, password, enable, current);
  }

  Future<void> _verify(int id, String ssid, String password, bool enable,
      List<Map<String, dynamic>> previous) async {
    final deadline = DateTime.now().add(_reconnectTimeout);
    Object? lastError;
    List<Map<String, dynamic>>? lastNetworks;
    List<String> lastDiff = const [];
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(_retryEvery);
      try {
        await api.relogin();
        final networks = extractList(await api.wlanList());
        lastNetworks = networks;
        lastError = null;
        final n = networks.firstWhere(
            (n) => pick(n, ['oid', 'id'], '') == '$id',
            orElse: () => const {});
        lastDiff = [
          if (n.isEmpty) 'SSID id $id not found',
          if (n.isNotEmpty && pick(n, ['SSID'], '') != ssid)
            'name is "${pick(n, ['SSID'], '')}"',
          if (n.isNotEmpty && pick(n, ['PreSharedKey'], '') != password)
            'password unchanged',
          if (n.isNotEmpty && (pick(n, ['Enable'], '') == '1') != enable)
            'still ${enable ? 'disabled' : 'enabled'}',
        ];
        if (lastDiff.isEmpty) {
          emit(WifiState(
              networks: networks, message: 'Saved ✓ "$ssid" updated.'));
          return;
        }
        emit(WifiState(
            loading: true,
            networks: networks,
            message: 'Router is back. Waiting for it to apply the change…'));
      } catch (e) {
        lastError = e;
      }
    }
    if (lastNetworks != null) {
      emit(WifiState(
          networks: lastNetworks,
          error: 'Router did not apply the change: ${lastDiff.join(', ')}.\n'
              'Router replies — ${api.lastSaveReply ?? '(none)'}'));
      return;
    }
    emit(WifiState(
        networks: previous,
        error: 'Could not reach the router after saving '
            '(${lastError == null ? 'timeout' : describeError(lastError)}). '
            'If you changed the network your phone uses, reconnect to it '
            'with the new name/password, then pull to refresh.'));
  }
}
