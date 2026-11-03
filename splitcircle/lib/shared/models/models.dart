import '../../features/expenses/domain/split_engine.dart';

class Member {
  final String id;
  final String name;
  final String role;
  final bool active;
  const Member(this.id, this.name, this.role, [this.active = true]);
}

class GroupSummary {
  final String id;
  final String name;
  final String category;
  final int color;
  final String currency;
  final bool archived;
  const GroupSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.currency,
    required this.archived,
  });
}

class ExpenseView {
  final String id;
  final String description;
  final int amountMinor;
  final String currency;
  final String category;
  final DateTime date;
  final String paidBy;
  final SplitMethod method;
  final String? notes;
  final Map<String, int> shares;
  const ExpenseView({
    required this.id,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.category,
    required this.date,
    required this.paidBy,
    required this.method,
    required this.notes,
    required this.shares,
  });
}

class SettlementView {
  final String id;
  final String fromId;
  final String toId;
  final int amountMinor;
  final String currency;
  final String method;
  final DateTime date;
  final String status;
  final String? note;
  const SettlementView({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.date,
    required this.status,
    required this.note,
  });
}
