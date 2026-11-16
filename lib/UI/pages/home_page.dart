import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../cubit/dashboard_cubit.dart';
import '../../cubit/parental_cubit.dart';
import '../../cubit/wifi_cubit.dart';
import 'parental_page.dart';
import 'settings_page.dart';
import '../widgets/app_dialog.dart';
import '../widgets/mada_logo.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    context.read<DashboardCubit>().load();
    context.read<WifiCubit>().load();
    context.read<ParentalCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [_HomeTab(), ParentalTab(), SettingsTab()];
    const titles = ['Home', 'Parental control', 'Settings'];
    return Scaffold(
      appBar: AppBar(
        title: index == 0 ? const MadaLogo(height: 44) : Text(titles[index]),
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.family_restroom), label: 'Parental'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(builder: (context, s) {
      final dash = context.read<DashboardCubit>();
      if (s.loading && s.clients.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (s.error != null) return _ErrorView(s.error!, dash.load);
      return RefreshIndicator(
        onRefresh: () => Future.wait([
          dash.load(),
          context.read<WifiCubit>().load(),
        ]),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          _InternetCard(s.loading ? null : s.internetUp, checking: s.loading),
          const _WifiCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text('Connected devices',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              _CountChip('${s.clients.length} online', Colors.green),
            ]),
          ),
          Card(
            child: Column(children: [
              if (s.clients.isEmpty)
                const ListTile(title: Text('No connected devices found.')),
              for (final d in s.clients) _DeviceTile(d),
            ]),
          ),
        ]),
      );
    });
  }
}

class _InternetCard extends StatelessWidget {
  final bool? up;
  final bool checking;
  const _InternetCard(this.up, {required this.checking});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (up) {
      true => (Icons.public, MadaColors.online, 'Connected to the internet'),
      false => (Icons.public_off, scheme.error, 'No internet connection'),
      null => (
          Icons.public,
          scheme.outline,
          checking ? 'Checking internet…' : 'Internet status unknown'
        ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _WifiCard extends StatelessWidget {
  const _WifiCard();
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WifiCubit, WifiState>(builder: (context, w) {
      final on = w.networks.where((n) => _ssidEnabled(n) == true).toList();
      final names = on
          .map((n) => pick(n, ['ssid'], ''))
          .where((s) => s.isNotEmpty)
          .toSet();
      return Card(
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [MadaColors.magenta, Color(0xFFA8125A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Icon(Icons.wifi, size: 36, color: Colors.white),
            title: Text('WiFi networks',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(
              w.loading && w.networks.isEmpty
                  ? 'Loading…'
                  : names.isEmpty
                      ? 'Tap to manage'
                      : names.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (w.networks.isNotEmpty)
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${on.length}/${w.networks.length}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('on',
                      style: TextStyle(fontSize: 11, color: Colors.white)),
                ]),
              Icon(Icons.chevron_right, color: Colors.white),
            ]),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const WifiPage())),
          ),
        ),
      );
    });
  }
}

class _DeviceTile extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DeviceTile(this.d);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ip = pick(d, ['ip', 'ipaddress', 'ipaddr'], '');
    final mac = pick(d, ['mac', 'macaddress', 'macaddr'], '');
    final wifi = [
      pick(d, ['SSID'], ''),
      pick(d, ['Band'], '')
    ].where((s) => s.isNotEmpty).join(' ');
    final iface = pick(d, ['Interface'], '');
    return ListTile(
      leading: Stack(clipBehavior: Clip.none, children: [
        const Icon(Icons.devices, color: Colors.green),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 1.5),
            ),
          ),
        ),
      ]),
      title: Text(pick(d, ['hostname', 'devicename', 'name', 'host'])),
      subtitle: Text([
        if (ip.isNotEmpty && ip != '-') ip,
        if (wifi.isNotEmpty) wifi else if (iface.isNotEmpty) iface,
        mac,
      ].join('  •  ')),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String text;
  final Color color;
  const _CountChip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class WifiPage extends StatelessWidget {
  const WifiPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi networks')),
      body: const _WifiList(),
    );
  }
}

class _WifiList extends StatelessWidget {
  const _WifiList();
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WifiCubit, WifiState>(
      listener: (context, s) {
        final msg = s.loading ? s.error : (s.error ?? s.message);
        if (msg != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor:
                  s.error != null ? Theme.of(context).colorScheme.error : null,
              duration: Duration(seconds: s.error != null ? 8 : 4),
            ));
        }
      },
      builder: (context, s) {
        final cubit = context.read<WifiCubit>();
        if (s.loading && s.networks.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.networks.isEmpty) {
          return _ErrorView(s.error ?? 'No networks found', cubit.load);
        }
        final scheme = Theme.of(context).colorScheme;
        return Column(children: [
          if (s.loading) ...[
            const LinearProgressIndicator(),
            if (s.message != null)
              Container(
                width: double.infinity,
                color: scheme.secondaryContainer,
                padding: const EdgeInsets.all(12),
                child: Text(s.message!,
                    style: TextStyle(color: scheme.onSecondaryContainer)),
              ),
          ],
          Expanded(
            child: RefreshIndicator(
              onRefresh: cubit.load,
              child: ListView(children: [
                for (var i = 0; i < s.networks.length; i++)
                  Builder(builder: (context) {
                    final n = s.networks[i];
                    final enabled = _ssidEnabled(n);
                    final color = switch (enabled) {
                      true => Colors.green,
                      false => scheme.error,
                      null => scheme.outline,
                    };
                    final band = pick(n, ['Type'], '');
                    return ListTile(
                      enabled: !s.loading,
                      leading: Icon(
                        enabled == false ? Icons.wifi_off : Icons.wifi,
                        color: color,
                      ),
                      title: Text(
                        pick(n, ['ssid']),
                        style: enabled == false
                            ? TextStyle(color: scheme.onSurfaceVariant)
                            : null,
                      ),
                      subtitle: Text([
                        'id: ${pick(n, ['oid', 'id'], '$i')}',
                        if (band.isNotEmpty) band,
                      ].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        _StatusChip(enabled: enabled, color: color),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit),
                      ]),
                      onTap: () => _edit(context, n, i),
                    );
                  }),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  void _edit(BuildContext context, Map<String, dynamic> n, int fallbackId) {
    final ssid = TextEditingController(text: pick(n, ['ssid'], ''));
    final pass = TextEditingController(text: pick(n, ['PreSharedKey'], ''));
    final id = int.tryParse(pick(n, ['oid', 'id'], '')) ?? fallbackId;
    var enable = _ssidEnabled(n) ?? true;
    var showPass = false;
    String? problem;
    final cubit = context.read<WifiCubit>();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AppDialog(
          title: const Text('Edit WiFi'),
          fields: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: enable,
              onChanged: (v) => setLocal(() => enable = v),
            ),
            TextField(
                controller: ssid,
                decoration: const InputDecoration(
                    labelText: 'Network name', prefixIcon: Icon(Icons.wifi))),
            TextField(
              controller: pass,
              obscureText: !showPass,
              decoration: InputDecoration(
                labelText: 'Password (min 8)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon:
                      Icon(showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setLocal(() => showPass = !showPass),
                ),
              ),
            ),
            if (problem != null) DialogError(problem!),
          ],
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ssid.text.trim().isEmpty) {
                  return setLocal(() => problem = 'Enter a network name.');
                }
                if (pass.text.length < 8) {
                  return setLocal(() =>
                      problem = 'Password must be at least 8 characters.');
                }
                Navigator.pop(dialogCtx);
                cubit.save(
                  network: n,
                  id: id,
                  ssid: ssid.text.trim(),
                  password: pass.text,
                  enable: enable,
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

bool? _ssidEnabled(Map<String, dynamic> n) => switch ('${n['Enable']}') {
      '1' => true,
      '0' => false,
      _ => null,
    };

class _StatusChip extends StatelessWidget {
  final bool? enabled;
  final Color color;
  const _StatusChip({required this.enabled, required this.color});
  @override
  Widget build(BuildContext context) {
    final label = switch (enabled) {
      true => 'Enabled',
      false => 'Disabled',
      null => 'Unknown',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String msg;
  final VoidCallback retry;
  const _ErrorView(this.msg, this.retry);
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(msg, textAlign: TextAlign.center)),
          OutlinedButton(onPressed: retry, child: const Text('Retry')),
        ]),
      );
}
