import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../cubit/parental_cubit.dart';
import '../widgets/app_dialog.dart';

class ParentalTab extends StatelessWidget {
  const ParentalTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ParentalCubit, ParentalState>(
      listenWhen: (a, b) => b.error != null || b.message != null,
      listener: _snack,
      builder: (context, s) {
        final cubit = context.read<ParentalCubit>();
        final users = s.profiles.where((p) => !p.isHome).toList();
        final home = s.profiles.where((p) => p.isHome).firstOrNull;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed:
                s.saving || s.loading ? null : () => _createProfile(context),
            icon: const Icon(Icons.add),
            label: const Text('Add profile'),
          ),
          body: s.loading && s.profiles.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: cubit.load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: [
                      if (s.saving || s.loading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: LinearProgressIndicator(),
                        ),
                      if (home != null) _HomeProfileCard(home),
                      _SectionHeader(
                        title: 'Other',
                        trailing: _CountChip(
                            '${users.length} profile${users.length == 1 ? '' : 's'}',
                            Theme.of(context).colorScheme.primary),
                      ),
                      Card(
                        child: Column(children: [
                          if (users.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                  'No profiles yet. Add one to pause the '
                                  'internet, set offline schedules or block '
                                  'websites for a group of devices.',
                                  textAlign: TextAlign.center),
                            ),
                          for (var i = 0; i < users.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                  height: 1, indent: 72, endIndent: 16),
                            _ProfileTile(users[i]),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _createProfile(BuildContext context) async {
    final cubit = context.read<ParentalCubit>();
    final result = await showDialog<(String, Set<String>)>(
      context: context,
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const _CreateProfileDialog()),
    );
    if (result == null) return;
    final pid = await cubit.createProfile(result.$1, result.$2);
    if (pid != null && context.mounted) {
      Navigator.push(context, _profileRoute(context, pid));
    }
  }
}

void _snack(BuildContext context, ParentalState s) {
  final msg = s.error ?? s.message;
  if (msg == null) return;
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: s.error != null ? scheme.error : null,
      duration: Duration(seconds: s.error != null ? 6 : 3),
    ));
}

Route _profileRoute(BuildContext context, int pid) {
  final cubit = context.read<ParentalCubit>();
  return MaterialPageRoute(
    builder: (_) =>
        BlocProvider.value(value: cubit, child: ProfilePage(pid: pid)),
  );
}

class _HomeProfileCard extends StatelessWidget {
  final ParentalProfile p;
  const _HomeProfileCard(this.p);
  @override
  Widget build(BuildContext context) {
    final s = context.read<ParentalCubit>().state;
    final on = p.devices.where((d) => s.isOnline(d.mac)).length;
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
          leading: const Icon(Icons.home, size: 36, color: Colors.white),
          title: Text(p.name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: const Text('Devices not in a profile',
              style: TextStyle(color: Colors.white)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$on/${p.devices.length}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const Text('online',
                  style: TextStyle(fontSize: 11, color: Colors.white)),
            ]),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
          onTap: () => Navigator.push(context, _profileRoute(context, p.id)),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final ParentalProfile p;
  const _ProfileTile(this.p);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = [
      '${p.devices.length} device${p.devices.length == 1 ? '' : 's'}',
      if (p.schedules.isNotEmpty)
        '${p.schedules.where((s) => s.enabled).length}/${p.schedules.length} schedules on',
      if (p.urlFilterOn) '${p.urls.length} sites blocked',
    ];
    final color = p.internetOn ? MadaColors.online : scheme.error;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(p.internetOn ? Icons.person : Icons.pause_circle,
            color: color),
      ),
      title: Text(p.name),
      subtitle: Text(parts.join('  •  ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _CountChip(p.internetOn ? 'Online' : 'Paused', color),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right),
      ]),
      onTap: () => Navigator.push(context, _profileRoute(context, p.id)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 4, 4),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          ?trailing,
        ]),
      );
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


class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog();
  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final name = TextEditingController();
  final selected = <String>{};
  String? problem;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ParentalCubit>().state;
    return AppDialog(
      title: const Text('New profile'),
      fields: [
        TextField(
          controller: name,
          maxLength: maxProfileNameLength,
          decoration: InputDecoration(
              labelText: 'Profile name (e.g. Kids)',
              prefixIcon: const Icon(Icons.person_outline),
              errorText: problem),
        ),
        Text('Devices', style: Theme.of(context).textTheme.titleSmall),
        _DevicePicker(
          state: s,
          selected: selected,
          onChanged: () => setState(() {}),
        ),
      ],
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = name.text.trim();
            final err = _checkName(n, s.profiles.map((p) => p.name));
            if (err != null) return setState(() => problem = err);
            Navigator.pop(context, (n, selected));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

String? _checkName(String n, Iterable<String> taken) {
  if (n.isEmpty) return 'Enter a name.';
  if (n.length > maxProfileNameLength) {
    return 'At most $maxProfileNameLength characters.';
  }
  if (!profileNameRe.hasMatch(n)) {
    return "Only letters, numbers, spaces and . @ # ' _ -";
  }
  if (taken.any((t) => t.toLowerCase() == n.toLowerCase())) {
    return 'A profile with this name exists.';
  }
  return null;
}

class _DevicePicker extends StatelessWidget {
  final ParentalState state;
  final Set<String> selected;
  final VoidCallback onChanged;
  final ParentalProfile? exclude;
  const _DevicePicker({
    required this.state,
    required this.selected,
    required this.onChanged,
    this.exclude,
  });

  @override
  Widget build(BuildContext context) {
    final names = <String, String>{};
    for (final c in state.clients) {
      final mac = normMac(pick(c, ['mac', 'macaddress'], ''));
      if (mac.isNotEmpty) names[mac] = state.deviceName(mac);
    }
    for (final p in state.profiles) {
      for (final d in p.devices) {
        names.putIfAbsent(d.mac, () => state.deviceName(d.mac, d.name));
      }
    }
    if (exclude != null) names.removeWhere((m, _) => exclude!.hasDevice(m));
    final macs = names.keys.toList()
      ..sort((a, b) {
        final on = (state.isOnline(b) ? 1 : 0) - (state.isOnline(a) ? 1 : 0);
        return on != 0
            ? on
            : names[a]!.toLowerCase().compareTo(names[b]!.toLowerCase());
      });
    if (macs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(state.loading
            ? 'Loading devices…'
            : 'No devices found. Pull to refresh on the Parental tab.'),
      );
    }
    return Column(children: [
      for (final mac in macs)
        Builder(builder: (context) {
          final owner = state.ownerOf(mac);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: Icon(Icons.devices,
                color: state.isOnline(mac)
                    ? Colors.green
                    : Theme.of(context).colorScheme.outline),
            title: Text(names[mac]!),
            subtitle: Text([
              mac,
              if (owner != null && !owner.isHome) 'in ${owner.name}',
            ].join(' · ')),
            value: selected.contains(mac),
            onChanged: (v) {
              v == true ? selected.add(mac) : selected.remove(mac);
              onChanged();
            },
          );
        }),
    ]);
  }
}


class ProfilePage extends StatelessWidget {
  final int pid;
  const ProfilePage({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ParentalCubit, ParentalState>(
      listenWhen: (a, b) => b.error != null || b.message != null,
      listener: _snack,
      builder: (context, s) {
        final p = s.profile(pid);
        final cubit = context.read<ParentalCubit>();
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
                child: s.loading || s.saving
                    ? const CircularProgressIndicator()
                    : const Text('This profile no longer exists.')),
          );
        }
        final busy = s.saving;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: Text(p.name), actions: [
            if (!p.isHome)
              IconButton(
                tooltip: 'Delete profile',
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : () => _delete(context, p),
              ),
          ]),
          body: RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              if (!p.isHome)
                Card(
                  color: p.internetOn ? null : scheme.errorContainer,
                  child: SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    secondary: Icon(
                        p.internetOn ? Icons.public : Icons.pause_circle_filled,
                        color: p.internetOn ? MadaColors.online : scheme.error),
                    title: const Text('Internet access'),
                    subtitle: Text(p.internetOn
                        ? 'On — follows the schedules below'
                        : 'Paused for all devices in this profile'),
                    value: p.internetOn,
                    onChanged: busy ? null : (v) => cubit.setInternet(p, v),
                  ),
                ),
              _SectionHeader(
                title: 'Devices',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _CountChip(
                      '${p.devices.where((d) => s.isOnline(d.mac)).length}'
                      '/${p.devices.length} online',
                      MadaColors.online),
                  if (!p.isHome)
                    TextButton.icon(
                        onPressed: busy ? null : () => _addDevices(context, p),
                        icon: const Icon(Icons.add),
                        label: const Text('Add')),
                ]),
              ),
              Card(
                child: Column(children: [
                  if (p.devices.isEmpty)
                    const ListTile(title: Text('No devices in this profile.')),
                  for (final d in p.devices)
                    ListTile(
                      leading: Icon(Icons.devices,
                          color: s.isOnline(d.mac)
                              ? MadaColors.online
                              : scheme.outline),
                      title: Text(s.deviceName(d.mac, d.name)),
                      subtitle: Text(
                          '${d.mac}${s.isOnline(d.mac) ? '  •  online' : ''}'),
                      trailing: p.isHome
                          ? null
                          : IconButton(
                              tooltip: 'Remove from profile',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed:
                                  busy ? null : () => cubit.removeDevice(p, d),
                            ),
                    ),
                ]),
              ),
              if (!p.isHome) ...[
                _SectionHeader(
                  title: 'Offline schedules',
                  subtitle: 'Internet is blocked during these times.',
                  trailing: TextButton.icon(
                      onPressed:
                          busy ? null : () => _editSchedule(context, p, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add')),
                ),
                Card(
                  child: Column(children: [
                    if (p.schedules.isEmpty)
                      const ListTile(title: Text('No schedules.')),
                    for (final sch in p.schedules)
                      ListTile(
                        leading:
                            Icon(sch.bedtime ? Icons.bedtime : Icons.schedule),
                        title: Text(sch.bedtime
                            ? 'Bedtime'
                            : (sch.name.isEmpty ? 'Schedule' : sch.name)),
                        subtitle: Text(
                            '${sch.start} – ${sch.end}  •  ${daysText(sch.days)}'),
                        onTap:
                            busy ? null : () => _editSchedule(context, p, sch),
                        trailing: Switch(
                          value: sch.enabled,
                          onChanged: busy
                              ? null
                              : (v) => cubit.toggleSchedule(p, sch, v),
                        ),
                      ),
                  ]),
                ),
                _SectionHeader(
                  title: 'Website filtering',
                  trailing: p.urls.isEmpty
                      ? null
                      : _CountChip('${p.urls.length} blocked',
                          p.urlFilterOn ? scheme.error : scheme.outline),
                ),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.filter_alt_outlined),
                      title: const Text('Block the sites below'),
                      value: p.urlFilterOn,
                      onChanged:
                          busy ? null : (v) => cubit.setWebsiteFiltering(p, v),
                    ),
                    for (final u in p.urls)
                      ListTile(
                        leading: Icon(Icons.block,
                            color:
                                p.urlFilterOn ? scheme.error : scheme.outline),
                        title: Text(u.address),
                        trailing: IconButton(
                          tooltip: 'Unblock',
                          icon: const Icon(Icons.close),
                          onPressed:
                              busy ? null : () => cubit.unblockSite(p, u),
                        ),
                      ),
                    ListTile(
                      leading: Icon(Icons.add_link, color: scheme.primary),
                      title: Text('Block a website',
                          style: TextStyle(color: scheme.primary)),
                      enabled: !busy,
                      onTap: () => _blockSite(context, p),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, ParentalProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('Delete "${p.name}"?'),
        fields: const [
          Text('Its schedules and blocked sites are removed and its devices '
              'go back to Home with normal internet access.'),
        ],
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final cubit = context.read<ParentalCubit>();
    if (await cubit.deleteProfile(p) && context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _addDevices(BuildContext context, ParentalProfile p) async {
    final cubit = context.read<ParentalCubit>();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: cubit,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AppDialog(
            title: Text('Add devices to ${p.name}'),
            fields: [
              BlocBuilder<ParentalCubit, ParentalState>(
                builder: (_, s) => _DevicePicker(
                  state: s,
                  selected: selected,
                  exclude: p,
                  onChanged: () => setLocal(() {}),
                ),
              ),
            ],
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed:
                      selected.isEmpty ? null : () => Navigator.pop(ctx, true),
                  child: const Text('Add')),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await cubit.addDevices(p, selected);
  }

  Future<void> _editSchedule(
      BuildContext context, ParentalProfile p, PcSchedule? sch) async {
    final cubit = context.read<ParentalCubit>();
    final r = await showDialog<_ScheduleResult>(
      context: context,
      builder: (_) => _ScheduleDialog(existing: sch),
    );
    if (r == null) return;
    if (r.delete) {
      await cubit.deleteSchedule(p, sch!);
    } else {
      await cubit.saveSchedule(p,
          existing: sch,
          bedtime: r.bedtime,
          name: r.name,
          start: r.start,
          end: r.end,
          days: r.days);
    }
  }

  Future<void> _blockSite(BuildContext context, ParentalProfile p) async {
    final cubit = context.read<ParentalCubit>();
    final ctrl = TextEditingController();
    String? problem;
    final site = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AppDialog(
          title: const Text('Block a website'),
          fields: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                  labelText: 'Website',
                  hintText: 'hello.com',
                  prefixIcon: const Icon(Icons.language),
                  errorText: problem),
            ),
          ],
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final s = cleanSite(ctrl.text);
                if (s == null) {
                  return setLocal(
                      () => problem = 'Enter a site like hello.com');
                }
                if (p.urls.any((u) => u.address.toLowerCase() == s)) {
                  return setLocal(() => problem = 'Already blocked.');
                }
                Navigator.pop(ctx, s);
              },
              child: const Text('Block'),
            ),
          ],
        ),
      ),
    );
    if (site == null) return;
    if (!p.urlFilterOn && !await cubit.setWebsiteFiltering(p, true)) return;
    final now = cubit.state.profile(p.id) ?? p;
    await cubit.blockSite(now, site);
  }
}


class _ScheduleResult {
  final bool delete, bedtime;
  final String name, start, end;
  final List<int> days;
  const _ScheduleResult({
    this.delete = false,
    this.bedtime = false,
    this.name = '',
    this.start = '',
    this.end = '',
    this.days = const [],
  });
}

class _ScheduleDialog extends StatefulWidget {
  final PcSchedule? existing;
  const _ScheduleDialog({this.existing});
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late bool bedtime = widget.existing?.bedtime ?? false;
  late TimeOfDay start = _parse(widget.existing?.start, 21, 0);
  late TimeOfDay end = _parse(widget.existing?.end, 6, 0);
  late final days = <int>{...?widget.existing?.days};
  String? problem;

  static TimeOfDay _parse(String? s, int h, int m) {
    final p = (s ?? '').split(':');
    return TimeOfDay(
        hour: int.tryParse(p.first) ?? h,
        minute: p.length > 1 ? int.tryParse(p[1]) ?? m : m);
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AppDialog(
      title: Text(isNew ? 'New offline schedule' : 'Edit schedule'),
      fields: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bedtime'),
          subtitle: const Text('Overnight block, no name'),
          value: bedtime,
          onChanged: (v) => setState(() => bedtime = v),
        ),
        if (!bedtime)
          TextField(
            controller: name,
            maxLength: maxScheduleNameLength,
            decoration: const InputDecoration(
                labelText: 'Name (e.g. Homework)',
                prefixIcon: Icon(Icons.edit_note)),
          ),
        Row(children: [
          Expanded(
            child: _TimeButton('From', start, (t) => setState(() => start = t)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TimeButton('To', end, (t) => setState(() => end = t)),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Days', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 0; d < 7; d++)
              FilterChip(
                label: Text(weekDayNames[d]),
                selected: days.contains(d),
                onSelected: (v) =>
                    setState(() => v ? days.add(d) : days.remove(d)),
              ),
          ]),
          Wrap(spacing: 4, children: [
            TextButton(
                onPressed: () => setState(() => days
                  ..clear()
                  ..addAll([0, 1, 2, 3, 4, 5, 6])),
                child: const Text('Every day')),
            TextButton(
                onPressed: () => setState(() => days
                  ..clear()
                  ..addAll([1, 2, 3, 4, 5])),
                child: const Text('Weekdays')),
          ]),
        ]),
        if (problem != null) DialogError(problem!),
      ],
      actions: [
        if (!isNew)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _ScheduleResult(delete: true)),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = name.text.trim();
            if (!bedtime) {
              if (n.isEmpty) return setState(() => problem = 'Enter a name.');
              if (!profileNameRe.hasMatch(n)) {
                return setState(() =>
                    problem = "Only letters, numbers, spaces and . @ # ' _ -");
              }
            }
            if (days.isEmpty) {
              return setState(() => problem = 'Pick at least one day.');
            }
            if (_fmt(start) == _fmt(end)) {
              return setState(
                  () => problem = 'Start and end time must differ.');
            }
            Navigator.pop(
                context,
                _ScheduleResult(
                  bedtime: bedtime,
                  name: bedtime ? '' : n,
                  start: _fmt(start),
                  end: _fmt(end),
                  days: days.toList()..sort(),
                ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onPicked;
  const _TimeButton(this.label, this.value, this.onPicked);
  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () async {
          final t = await showTimePicker(context: context, initialTime: value);
          if (t != null) onPicked(t);
        },
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value.format(context),
              style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}
