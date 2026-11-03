import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/db_helpers.dart';
import '../../../core/utils/money.dart';
import '../../../shared/providers/providers.dart';
import '../data/expense_repository.dart';
import '../domain/split_engine.dart';

const kExpenseCategories = [
  'food', 'groceries', 'transport', 'accommodation', 'shopping',
  'entertainment', 'utilities', 'rent', 'travel', 'other',
];

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String groupId;
  const AddExpenseScreen({super.key, required this.groupId});
  @override
  ConsumerState<AddExpenseScreen> createState() => _State();
}

class _State extends ConsumerState<AddExpenseScreen> {
  // One key per screen visit: double-taps and retries can never duplicate.
  final _requestId = newId();
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _values = {};
  final Set<String> _selected = {};
  String _category = 'food';
  SplitMethod _method = SplitMethod.equal;
  DateTime _date = DateTime.now();
  String? _paidBy;
  bool _saving = false;
  bool _initialised = false;

  TextEditingController _ctl(String id) =>
      _values.putIfAbsent(id, () => TextEditingController(text: _method == SplitMethod.shares ? '1' : ''));

  /// Returns shares or an error message for the live preview.
  ({Map<String, int>? shares, String? error}) _preview(String currency) {
    final total = parseToMinor(_amount.text, currency);
    if (total == null || total <= 0) return (shares: null, error: 'Enter a valid amount');
    final entries = <SplitEntry>[];
    for (final id in _selected) {
      final text = _ctl(id).text;
      int? v = 0;
      switch (_method) {
        case SplitMethod.equal:
          v = 0;
        case SplitMethod.exact:
        case SplitMethod.custom:
          v = text.isEmpty ? 0 : parseToMinor(text, currency);
        case SplitMethod.percentage:
          v = text.isEmpty ? 0 : parsePercentToBps(text);
        case SplitMethod.shares:
          v = int.tryParse(text);
      }
      if (v == null) return (shares: null, error: 'Invalid number entered');
      entries.add(SplitEntry(id, v));
    }
    try {
      return (
        shares: computeSplit(totalMinor: total, method: _method, entries: entries),
        error: null
      );
    } on AppException catch (e) {
      return (shares: null, error: e.message);
    }
  }

  Future<void> _save(String currency) async {
    final p = _preview(currency);
    if (p.shares == null) {
      _toast(p.error ?? 'Check the split');
      return;
    }
    setState(() => _saving = true);
    try {
      final total = parseToMinor(_amount.text, currency)!;
      await ref.read(expenseRepoProvider).create(ExpenseInput(
            clientRequestId: _requestId,
            groupId: widget.groupId,
            actorId: ref.read(meIdProvider),
            description: _desc.text,
            amountMinor: total,
            currency: currency,
            category: _category,
            date: _date,
            paidBy: _paidBy!,
            method: _method,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            entries: [
              for (final id in _selected)
                SplitEntry(id, _entryValue(id, currency)),
            ],
          ));
      refreshAll(ref, widget.groupId);
      if (mounted) context.go('/group/${widget.groupId}');
    } on AppException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _entryValue(String id, String currency) {
    final t = _ctl(id).text;
    switch (_method) {
      case SplitMethod.equal:
        return 0;
      case SplitMethod.exact:
      case SplitMethod.custom:
        return t.isEmpty ? 0 : parseToMinor(t, currency)!;
      case SplitMethod.percentage:
        return t.isEmpty ? 0 : parsePercentToBps(t)!;
      case SplitMethod.shares:
        return int.parse(t);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _hint() => switch (_method) {
        SplitMethod.exact || SplitMethod.custom => 'Amount',
        SplitMethod.percentage => '%',
        SplitMethod.shares => 'Shares',
        SplitMethod.equal => '',
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupDetailProvider(widget.groupId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (d) {
        final members = d.members.where((m) => m.active).toList();
        final cur = d.group.currency;
        if (!_initialised) {
          _initialised = true;
          _paidBy = ref.read(meIdProvider);
          _selected.addAll(members.map((m) => m.id));
        }
        final prev = _preview(cur);
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => context.go('/group/${widget.groupId}')),
            title: const Text('Add expense'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(Gap.m),
            children: [
              TextField(
                  controller: _desc,
                  decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: Gap.s),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Amount', prefixText: currencyOf(cur).symbol),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.s),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in kExpenseCategories)
                    DropdownMenuItem(value: c, child: Text(c[0].toUpperCase() + c.substring(1)))
                ],
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: Gap.s),
              DropdownButtonFormField<String>(
                value: _paidBy,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: [
                  for (final m in members)
                    DropdownMenuItem(value: m.id, child: Text(m.name))
                ],
                onChanged: (v) => setState(() => _paidBy = v),
              ),
              const SizedBox(height: Gap.s),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final p = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)));
                  if (p != null) setState(() => _date = p);
                },
              ),
              const SizedBox(height: Gap.s),
              Text('Split method', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Gap.s),
              Wrap(spacing: Gap.s, children: [
                for (final m in SplitMethod.values)
                  ChoiceChip(
                    label: Text(m.name),
                    selected: _method == m,
                    onSelected: (_) => setState(() {
                      _method = m;
                      for (final c in _values.values) {
                        c.text = m == SplitMethod.shares ? '1' : '';
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: Gap.m),
              for (final m in members)
                Row(children: [
                  Checkbox(
                    value: _selected.contains(m.id),
                    onChanged: (v) => setState(
                        () => v == true ? _selected.add(m.id) : _selected.remove(m.id)),
                  ),
                  Expanded(child: Text(m.name)),
                  if (_method != SplitMethod.equal && _selected.contains(m.id))
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _ctl(m.id),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(hintText: _hint(), isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      prev.shares?[m.id] == null ? '' : formatMinor(prev.shares![m.id]!, cur),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ]),
              if (prev.error != null && _amount.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.s),
                  child: Text(prev.error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: Gap.m),
              TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: Gap.l),
              FilledButton(
                onPressed: _saving || prev.shares == null ? null : () => _save(cur),
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save expense'),
              ),
            ],
          ),
        );
      },
    );
  }
}
