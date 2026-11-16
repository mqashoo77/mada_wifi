import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/api.dart';

enum AuthStatus { loggedOut, loading, loggedIn, failure }

class AuthState {
  final AuthStatus status;
  final String? error;
  const AuthState(this.status, [this.error]);
}

class AuthCubit extends Cubit<AuthState> {
  final RouterApi api;
  AuthCubit(this.api) : super(const AuthState(AuthStatus.loggedOut));

  Future<void> login(String user, String pass) async {
    emit(const AuthState(AuthStatus.loading));
    try {
      api.configure();
      await api.login(user.trim(), pass);
      emit(const AuthState(AuthStatus.loggedIn));
    } catch (e) {
      emit(AuthState(AuthStatus.failure, 'Login failed: $e'));
    }
  }

  Future<void> logout() async {
    await api.logout();
    emit(const AuthState(AuthStatus.loggedOut));
  }
}
