import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/expense.dart';
import '../utils/currency_formatter.dart';

class AddExpenseScreen extends StatefulWidget {
  final String siteId;
  final Expense? existingExpense;
  const AddExpenseScreen({super.key, required this.siteId, this.existingExpense});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _descController = TextEditingController();
  final _unitController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _totalController = TextEditingController();
  late ExpenseCategory _category = widget.existingExpense?.category ?? ExpenseCategory.materials;
  String? _receiptPath;
  bool _saving = false;

  bool get _isEditing => widget.existingExpense != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _descController.text = widget.existingExpense!.displayDescription;
      _unitController.text = widget.existingExpense!.unit ?? '';
      _unitPriceController.text = (widget.existingExpense!.unitPrice ?? widget.existingExpense!.amount).toString();
      _totalController.text = widget.existingExpense!.amount.toString();
      _receiptPath = widget.existingExpense!.receiptPhotoPath;
    }
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final savedPath = p.join(appDir.path, 'receipts', fileName);
    await Directory(p.join(appDir.path, 'receipts')).create(recursive: true);
    await File(file.path).copy(savedPath);

    setState(() => _receiptPath = savedPath);
  }

  Future<void> _save() async {
    final unitPrice = double.tryParse(_unitPriceController.text.trim());
    final total = double.tryParse(_totalController.text.trim());
    final desc = _descController.text.trim();

    if (desc.isEmpty || unitPrice == null || unitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter description and a valid unit price')),
      );
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now();
    final monthKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final serialNo = _isEditing
        ? widget.existingExpense!.serialNo
        : await DatabaseHelper.instance.getNextExpenseSerialNo(widget.siteId, monthKey);

    final amount = total ?? unitPrice;

    if (_isEditing) {
      final updated = Expense(
        id: widget.existingExpense!.id,
        siteId: widget.siteId,
        date: widget.existingExpense!.date,
        category: _category,
        amount: amount,
        note: desc,
        receiptPhotoPath: _receiptPath,
        serialNo: serialNo,
        description: desc,
        unit: _unitController.text.trim().isEmpty ? null : _unitController.text.trim(),
        unitPrice: unitPrice,
        month: widget.existingExpense!.month,
      );
      await DatabaseHelper.instance.updateExpense(updated);
    } else {
      final expense = Expense(
        id: const Uuid().v4(),
        siteId: widget.siteId,
        date: now,
        category: _category,
        amount: amount,
        note: desc,
        receiptPhotoPath: _receiptPath,
        serialNo: serialNo,
        description: desc,
        unit: _unitController.text.trim().isEmpty ? null : _unitController.text.trim(),
        unitPrice: unitPrice,
        month: monthKey,
      );
      await DatabaseHelper.instance.insertExpense(expense);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Expense' : 'New Expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<ExpenseCategory>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: ExpenseCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _unitController,
                  decoration: const InputDecoration(labelText: 'Unit (e.g. 2kg, 1 Bag)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _unitPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Unit Price (N)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _totalController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Total (N)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickReceipt,
            icon: Icon(_receiptPath == null ? Icons.camera_alt : Icons.check_circle),
            label: Text(_receiptPath == null ? 'Attach Receipt Photo' : 'Receipt Attached'),
          ),
          if (_receiptPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_receiptPath!), height: 100),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator()
                : Text(_isEditing ? 'Update Expense' : 'Save Expense'),
          ),
        ],
      ),
    );
  }
}
