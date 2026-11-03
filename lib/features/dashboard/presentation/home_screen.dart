import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../shared/providers/providers.dart';

const kGroupCategories = ['trip', 'home', 'couple', 'family', 'friends', 'other'];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SplitCircle')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(Icons.group_add),
        label: const Text('New group'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: ListView(
            padding: const EdgeInsets.all(Gap.m),
            children: [
              _BalanceCard(owedToMe: d.owedToMe, iOwe: d.iOwe),
              const SizedBox(height: Gap.l),
              Text('Your groups', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.s),
              if (d.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.xl),
                  child: Center(
                      child: Text('No groups yet. Create one to start splitting.')),
                ),
              for (final r in d.groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.s),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(r.group.color),
                        child: const Icon(Icons.groups, color: Colors.white),
                      ),
                      title: Text(r.group.name),
                      subtitle: Text(r.myNet == 0
                          ? 'Settled up'
                          : r.myNet > 0
                              ? 'You are owed ${formatMinor(r.myNet, r.group.currency)}'
                              : 'You owe ${formatMinor(-r.myNet, r.group.currency)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/group/${r.group.id}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final members = TextEditingController();
    var category = 'friends';
    var currency = 'INR';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            Gap.m, Gap.m, Gap.m, MediaQuery.of(ctx).viewInsets.bottom + Gap.m),
        child: StatefulBuilder(
          builder: (ctx, set) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create group', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: Gap.m),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Group name')),
              const SizedBox(height: Gap.s),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in kGroupCategories)
                    DropdownMenuItem(value: c, child: Text(c[0].toUpperCase() + c.substring(1)))
                ],
                onChanged: (v) => set(() => category = v!),
              ),
              const SizedBox(height: Gap.s),
              DropdownButtonFormField<String>(
                value: currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  for (final c in kCurrencies.keys)
                    DropdownMenuItem(value: c, child: Text(c))
                ],
                onChanged: (v) => set(() => currency = v!),
              ),
              const SizedBox(height: Gap.s),
              TextField(
                controller: members,
                decoration: const InputDecoration(
                    labelText: 'Other members (comma separated)',
                    hintText: 'Asha, Ravi'),
              ),
              const SizedBox(height: Gap.m),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Create')),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final id = await ref.read(groupRepoProvider).createGroup(
            actorId: ref.read(meIdProvider),
            name: name.text,
            category: category,
            currency: currency,
            memberNames: members.text.split(','),
          );
      ref.invalidate(dashboardProvider);
      if (context.mounted) context.go('/group/$id');
    } on AppException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  final Map<String, int> owedToMe;
  final Map<String, int> iOwe;
  const _BalanceCard({required this.owedToMe, required this.iOwe});

  String _fmt(Map<String, int> m) => m.isEmpty
      ? formatMinor(0, 'INR')
      : m.entries.map((e) => formatMinor(e.value, e.key)).join(' + ');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(Gap.m),
        child: Row(children: [
          Expanded(child: _Stat('You are owed', _fmt(owedToMe), AppColors.received, t)),
          Expanded(child: _Stat('You owe', _fmt(iOwe), AppColors.owed, t)),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  final TextTheme t;
  const _Stat(this.label, this.value, this.color, this.t);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelMedium?.copyWith(color: Colors.white70)),
          const SizedBox(height: Gap.xs),
          Text(value,
              style: t.titleLarge?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          Container(
              margin: const EdgeInsets.only(top: Gap.xs),
              height: 3,
              width: 28,
              color: color),
        ],
      );
}
