import 'package:intl/intl.dart';

/// The 10 mandatory, locked expense categories.
enum ExpenseCategory {
  fuelAndLubricants,
  materials,
  wagesAllowancesAdvances,
  transport,
  repairsAndMaintenance,
  toolsAndEquipment,
  medicalExpenses,
  labour,
  siteWelfareAndSafety,
  other,
}

extension ExpenseCategoryX on ExpenseCategory {
  String get label {
    switch (this) {
      case ExpenseCategory.fuelAndLubricants:
        return 'Fuel & Lubricants';
      case ExpenseCategory.materials:
        return 'Materials';
      case ExpenseCategory.wagesAllowancesAdvances:
        return 'Wages, Allowances & Advances';
      case ExpenseCategory.transport:
        return 'Transport';
      case ExpenseCategory.repairsAndMaintenance:
        return 'Repairs & Maintenance';
      case ExpenseCategory.toolsAndEquipment:
        return 'Tools & Equipment';
      case ExpenseCategory.medicalExpenses:
        return 'Medical Expenses';
      case ExpenseCategory.labour:
        return 'Labour';
      case ExpenseCategory.siteWelfareAndSafety:
        return 'Site Welfare & Safety';
      case ExpenseCategory.other:
        return 'Other / Miscellaneous';
    }
  }

  static ExpenseCategory fromLabelOrName(String value) {
    for (final c in ExpenseCategory.values) {
      if (c.name == value || c.label == value) return c;
    }
    switch (value) {
      case 'materials':
        return ExpenseCategory.materials;
      case 'labor':
        return ExpenseCategory.labour;
      case 'equipment':
        return ExpenseCategory.toolsAndEquipment;
      default:
        return ExpenseCategory.other;
    }
  }
}

/// A single expense line in the site's itemized ledger.
class Expense {
  final String id;
  final String siteId;
  final DateTime date;
  final ExpenseCategory category;
  final double amount;
  final String? note;
  final String? receiptPhotoPath;
  final int? serialNo;
  final String? description;
  final String? unit;
  final double? unitPrice;
  final String? month;

  Expense({
    required this.id,
    required this.siteId,
    required this.date,
    required this.category,
    required this.amount,
    this.note,
    this.receiptPhotoPath,
    this.serialNo,
    this.description,
    this.unit,
    this.unitPrice,
    this.month,
  });

  String get displayDescription => description ?? note ?? '';
  String get monthKey => month ?? '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'siteId': siteId,
        'date': date.toIso8601String(),
        'category': category.name,
        'amount': amount,
        'note': note,
        'receiptPhotoPath': receiptPhotoPath,
        'serial_no': serialNo,
        'description': description ?? note,
        'unit': unit,
        'unit_price': unitPrice ?? amount,
        'total_amount': amount,
        'month': monthKey,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'],
        siteId: map['siteId'],
        date: DateTime.parse(map['date']),
        category: ExpenseCategoryX.fromLabelOrName(map['category']),
        amount: (map['total_amount'] as num?)?.toDouble() ?? (map['amount'] as num).toDouble(),
        note: map['note'],
        receiptPhotoPath: map['receiptPhotoPath'],
        serialNo: map['serial_no'] as int?,
        description: map['description'] as String?,
        unit: map['unit'] as String?,
        unitPrice: (map['unit_price'] as num?)?.toDouble(),
        month: map['month'] as String?,
      );
}
