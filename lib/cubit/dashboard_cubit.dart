import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/api.dart';

class DashboardState {
  final bool loading;
  final String? error;

  final bool? internetUp;
  final List<Map<String, dynamic>> clients;
  const DashboardState({
    this.loading = false,
    this.error,
    this.internetUp,
    this.clients = const [],
  });
}

class DashboardCubit extends Cubit<DashboardState> {
  final RouterApi api;
  DashboardCubit(this.api) : super(const DashboardState());

  Future<void> load() async {
    emit(DashboardState(loading: true, internetUp: state.internetUp));
    bool? internetUp;
    try {
      internetUp = isInternetUp(await api.internetStatus());
    } catch (_) {}
    try {
      final raw = await api.connectedDevices();
      emit(DashboardState(
          internetUp: internetUp, clients: connectedClients(raw)));
    } catch (e) {
      emit(DashboardState(internetUp: internetUp, error: describeError(e)));
    }
  }
}
