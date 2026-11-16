import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/api.dart';
import 'core/theme.dart';
import 'cubit/auth_cubit.dart';
import 'cubit/dashboard_cubit.dart';
import 'cubit/parental_cubit.dart';
import 'cubit/wifi_cubit.dart';
import 'UI/pages/home_page.dart';
import 'UI/pages/login_page.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => RouterApi(),
      child: Builder(builder: (context) {
        final api = context.read<RouterApi>();
        return MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => AuthCubit(api)),
            BlocProvider(create: (_) => DashboardCubit(api)),
            BlocProvider(create: (_) => WifiCubit(api)),
            BlocProvider(create: (_) => ParentalCubit(api)),
          ],
          child: MaterialApp(
            title: 'mada WiFi',
            debugShowCheckedModeBanner: false,
            theme: madaTheme(Brightness.light),
            darkTheme: madaTheme(Brightness.dark),
            home: BlocBuilder<AuthCubit, AuthState>(
              builder: (_, s) => s.status == AuthStatus.loggedIn
                  ? const HomePage()
                  : const LoginPage(),
            ),
          ),
        );
      }),
    );
  }
}
