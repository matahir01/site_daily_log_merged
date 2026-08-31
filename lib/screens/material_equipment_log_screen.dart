import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';

/// Tabbed screen for daily material stock ledger and equipment fuel dipping.
/// Auto-creates a [DailyLog] for today if none exists.
class MaterialEquipmentLogScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const MaterialEquipmentLogScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<MaterialEquipmentLogScreen> createState() =>
      _MaterialEquipmentLogScreenState();
}

class _MaterialEquipmentLogScreenState
    extends State<MaterialEquipmentLogScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper.instance;
  late TabController _tabController;
  String? _dailyLogId;
  bool _isLoading = true;

  final List<Map<String, String>> _materialItems = const [
    {'name': 'Y25mm Rebar', 'unit': 'length'},
    {'name': 'Y20mm Rebar', 'unit': 'length'},
    {'name': 'Y16mm Rebar', 'unit': 'length'},
    {'name': 'Y12mm Rebar', 'unit': 'length'},
    {'name': 'Cement', 'unit': 'Bags'},
    {'name': 'Diesel', 'unit': 'Litres'},
  ];
  final Map<String, TextEditingController> _matOpen = {};
  final Map<String, TextEditingController> _matRecv = {};
  final Map<String, TextEditingController> _matIssue = {};
  final Map<String, TextEditingController> _matClose = {};

  final List<String> _equipmentNames = const [
    'Excavator',
    'Mixer',
    'Generator',
    'Compactor',
  ];
  final Map<String, TextEditingController> _eqOpen = {};
  final Map<String, TextEditingController> _eqClose = {};
  final Map<String, TextEditingController> _eqDiesel = {};
  final Map<String, TextEditingController> _eqOil = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
  }

  Future<void> _initialize() async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final logs = await _db.getLogsForSite(widget.siteId);
    final todayLog = logs.where((l) {
      final d = l.date;
      return d.year == todayStart.year &&
          d.month == todayStart.month &&
          d.day == todayStart.day;
    }).toList();

    if (todayLog.isNotEmpty) {
      _dailyLogId = todayLog.first.id;
    } else {
      final log = DailyLog(
        id: const Uuid().v4(),
        siteId: widget.siteId,
        date: todayStart,
        workCompleted: '',
        weather: '',
      );
      await _db.insertDailyLog(log);
      _dailyLogId = log.id;
    }

    for (final item in _materialItems) {
      final name = item['name']!;
      _matOpen[name] = TextEditingController();
      _matRecv[name] = TextEditingController();
      _matIssue[name] = TextEditingController();
      _matClose[name] = TextEditingController();
    }
    for (final name in _equipmentNames) {
      _eqOpen[name] = TextEditingController();
      _eqClose[name] = TextEditingController();
      _eqDiesel[name] = TextEditingController();
      _eqOil[name] = TextEditingController();
    }

    final existingMat =
        await _db.getMaterialStockLogsForLog(_dailyLogId!);
    for (final log in existingMat) {
      _matOpen[log.itemName]?.text = log.openingBalance.toString();
      _matRecv[log.itemName]?.text = log.received.toString();
      _matIssue[log.itemName]?.text = log.issued.toString();
      _matClose[log.itemName]?.text = log.closingBalance.toString();
    }

    final existingEq =
        await _db.getEquipmentDippingLogsForLog(_dailyLogId!);
    for (final log in existingEq) {
      _eqOpen[log.equipmentName]?.text = log.openingDipCm?.toString() ?? '';
      _eqClose[log.equipmentName]?.text = log.closingDipCm?.toString() ?? '';
      _eqDiesel[log.equipmentName]?.text = log.dieselIssuedLitres.toString();
      _eqOil[log.equipmentName]?.text = log.engineOilIssuedLitres.toString();
    }

    for (final item in _materialItems) {
      final name = item['name']!;
      final lastBal = await _db.getLastClosingBalance(widget.siteId, name);
      if (lastBal != null && _matOpen[name]!.text.isEmpty) {
        _matOpen[name]!.text = lastBal.toString();
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveMaterialLogs() async {
    if (_dailyLogId == null) return;
    for (final item in _materialItems) {
      final name = item['name']!;
      final unit = item['unit']!;
      final log = MaterialStockLog(
        id: const Uuid().v4(),
        dailyLogId: _dailyLogId!,
        itemName: name,
        unit: unit,
        openingBalance: double.tryParse(_matOpen[name]!.text) ?? 0.0,
        received: double.tryParse(_matRecv[name]!.text) ?? 0.0,
        issued: double.tryParse(_matIssue[name]!.text) ?? 0.0,
        closingBalance: double.tryParse(_matClose[name]!.text) ?? 0.0,
      );
      await _db.insertMaterialStockLog(log);
    }
  }

  Future<void> _saveEquipmentLogs() async {
    if (_dailyLogId == null) return;
    for (final name in _equipmentNames) {
      final log = EquipmentDippingLog(
        id: const Uuid().v4(),
        dailyLogId: _dailyLogId!,
        equipmentName: name,
        openingDipCm: double.tryParse(_eqOpen[name]!.text),
        closingDipCm: double.tryParse(_eqClose[name]!.text),
        dieselIssuedLitres: double.tryParse(_eqDiesel[name]!.text) ?? 0.0,
        engineOilIssuedLitres: double.tryParse(_eqOil[name]!.text) ?? 0.0,
      );
      await _db.insertEquipmentDippingLog(log);
    }
  }

  Future<void> _saveAll() async {
    await _saveMaterialLogs();
    await _saveEquipmentLogs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All logs saved successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Material & Equipment — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Material Stock'),
            Tab(icon: Icon(Icons.local_gas_station), text: 'Equipment Dip'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAll,
            tooltip: 'Save All',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMaterialTab(),
                _buildEquipmentTab(),
              ],
            ),
    );
  }

  Widget _buildMaterialTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _materialItems.map((item) {
          final name = item['name']!;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, size: 12, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item['unit']!,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(_matOpen[name]!, 'Opening'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildNumberField(_matRecv[name]!, 'Received'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(_matIssue[name]!, 'Issued'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildNumberField(_matClose[name]!, 'Closing'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEquipmentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _equipmentNames.map((name) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(
                          _eqOpen[name]!,
                          'Open Dip (cm)',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildNumberField(
                          _eqClose[name]!,
                          'Close Dip (cm)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(
                          _eqDiesel[name]!,
                          'Diesel (L)',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildNumberField(
                          _eqOil[name]!,
                          'Engine Oil (L)',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNumberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _matOpen.values) c.dispose();
    for (final c in _matRecv.values) c.dispose();
    for (final c in _matIssue.values) c.dispose();
    for (final c in _matClose.values) c.dispose();
    for (final c in _eqOpen.values) c.dispose();
    for (final c in _eqClose.values) c.dispose();
    for (final c in _eqDiesel.values) c.dispose();
    for (final c in _eqOil.values) c.dispose();
    super.dispose();
  }
}
