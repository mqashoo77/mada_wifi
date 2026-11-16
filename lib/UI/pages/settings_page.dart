import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/auth_cubit.dart';
import '../widgets/app_dialog.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading:
              Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: Text('Log out',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _logout(context),
        ),
      ),
    ]);
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('Log out?'),
        fields: const [
          Text('You will need the router password to log in again.'),
        ],
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<AuthCubit>().logout();
  }
}
