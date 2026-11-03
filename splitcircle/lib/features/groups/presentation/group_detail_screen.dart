import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/db_helpers.dart';
import '../../../core/utils/money.dart';
import '../../../shared/providers/providers.dart';
import '../../settlements/data/settlement_repository.dart';

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() f) async {
    try {
      await f();
      refreshAll(ref, groupId);
    } on AppException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupDetailProvider(groupId));
    final me = ref.watch(meIdProvider);
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (d) {
        final g = d.group;
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => context.go('/')),
            title: Text(g.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'archive') {
                    _run(context, ref, () async {
                      await ref.read(groupRepoProvider).setArchived(
                          groupId: groupId, actorId: me, archived: !g.archived);
                    });
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'archive',
                      child: Text(g.archived ? 'Unarchive group' : 'Archive group')),
                ],
              ),
            ],
          ),
          floatingActionButton: g.archived
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => context.go('/group/$groupId/add-expense'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add expense'),
                ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.m),
            children: [
              if (g.archived)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.archive),
                        title: Text('Archived. History is read-only.'))),
              Text('Total spent: ${formatMinor(d.totalSpent, g.currency)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.m),
              Text('Balances', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.s),
              Card(
                child: Column(children: [
                  for (final m in d.members.where((m) => m.active))
                    Builder(builder: (_) {
                      final v = d.balances[g.currency]?[m.id] ?? 0;
                      return ListTile(
                        leading: CircleAvatar(child: Text(m.name[0].toUpperCase())),
                        title: Text(m.id == me ? '${m.name} (you)' : m.name),
                        trailing: Text(
                          v == 0
                              ? 'settled'
                              : v > 0
                                  ? '+${formatMinor(v, g.currency)}'
                                  : formatMinor(v, g.currency),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: v > 0
                                  ? AppColors.received
                                  : v < 0
                                      ? AppColors.owed
                                      : null),
                        ),
                      );
                    }),
                ]),
              ),
              const SizedBox(height: Gap.l),
              Text('Suggested settlements', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.s),
              if (d.suggestions.isEmpty)
                const Text('Everyone is settled up.')
              else
                for (final e in d.suggestions.entries)
                  for (final t in e.value)
                    Card(
                      child: ListTile(
                        title: Text('${d.nameOf(t.fromId)} pays ${d.nameOf(t.toId)}'),
                        subtitle: Text(formatMinor(t.amountMinor, e.key)),
                        trailing: g.archived
                            ? null
                            : TextButton(
                                onPressed: () async {
                                  final method = await _pickMethod(context);
                                  if (method == null || !context.mounted) return;
                                  await _run(context, ref, () async {
                                    await ref.read(settlementRepoProvider).record(
                                          clientRequestId: newId(),
                                          groupId: groupId,
                                          actorId: me,
                                          fromId: t.fromId,
                                          toId: t.toId,
                                          amountMinor: t.amountMinor,
                                          currency: e.key,
                                          method: method,
                                          date: DateTime.now(),
                                          confirmedByReceiver: true,
                                        );
                                  });
                                },
                                child: const Text('Mark paid'),
                              ),
                      ),
                    ),
              const Padding(
                padding: EdgeInsets.only(top: Gap.xs),
                child: Text(
                  '"Mark paid" records a payment made outside the app (cash, UPI, bank). SplitCircle does not move money.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: Gap.l),
              Text('Expenses', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.s),
              if (d.expenses.isEmpty) const Text('No expenses yet.'),
              for (final x in d.expenses)
                Card(
                  child: ListTile(
                    title: Text(x.description),
                    subtitle: Text(
                        '${d.nameOf(x.paidBy)} paid · ${DateFormat.yMMMd().format(x.date)} · ${x.method.name}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(formatMinor(x.amountMinor, x.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (!g.archived)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _run(context, ref, () async {
                            await ref.read(expenseRepoProvider).delete(
                                expenseId: x.id, groupId: groupId, actorId: me);
                          }),
                        ),
                    ]),
                  ),
                ),
              const SizedBox(height: Gap.l),
              Text('Settlement history', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Gap.s),
              if (d.settlements.isEmpty) const Text('No settlements yet.'),
              for (final s in d.settlements)
                Card(
                  child: ListTile(
                    title: Text(
                        '${d.nameOf(s.fromId)} → ${d.nameOf(s.toId)}  ${formatMinor(s.amountMinor, s.currency)}'),
                    subtitle: Text('${s.method} · ${s.status}'),
                    trailing: s.status == 'reversed' || g.archived
                        ? null
                        : TextButton(
                            child: const Text('Reverse'),
                            onPressed: () async {
                              final reason = await _askReason(context);
                              if (reason == null || !context.mounted) return;
                              await _run(context, ref, () async {
                                await ref.read(settlementRepoProvider).reverse(
                                    settlementId: s.id, actorId: me, reason: reason);
                              });
                            },
                          ),
                  ),
                ),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _pickMethod(BuildContext context) => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('How was it paid?'),
          children: [
            for (final m in kPaymentMethods)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, m),
                  child: Text(m.replaceAll('_', ' '))),
          ],
        ),
      );

  Future<String?> _askReason(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse settlement'),
        content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Reason (required)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Reverse')),
        ],
      ),
    );
  }
}
