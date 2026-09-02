import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/expense.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../services/batch_export_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/sync_status_badge.dart';

/// Advanced, date-range-aware analytics & reporting dashboard for a single
/// site: financial trends, concrete pour volumes, diesel consumption rates,
/// worker attendance trends, and top-line KPI cards.
///
/// [project] is optional — when supplied, the app bar exposes a "Batch
/// Export" action that packages everything in the selected range (daily
/// logs, concrete pours, dipping logs, and the expense ledger) into a
/// single PDF and/or Excel report via [BatchExportService].
class AnalyticsScreen extends StatefulWidget {
  final String siteId;
  final String siteName;
  final Project? project;
  final Site? site;

  const AnalyticsScreen({
    super.key,
    required this.siteId,
    required this.siteName,
    this.project,
    this.site,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

enum _QuickRange { last7, last30, last90, thisMonth, allTime, custom }

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseHelper.instance;

  DateTimeRange _range = _rangeFor(_QuickRange.last30);
  _QuickRange _quickRange = _QuickRange.last30;
  bool _isLoading = true;
  bool _isExporting = false;

  // Financial
  Map<String, double> _categoryTotals = {};
  List<Map<String, dynamic>> _dailyBurn = [];
  List<_CashFloatData> _cashFlowData = [];
  double _totalExpenditure = 0;

  // Operations
  List<_TrendPoint> _concreteVolumeTrend = [];
  double _totalConcreteVolume = 0;
  List<_TrendPoint> _dieselTrend = [];
  double _totalDieselLitres = 0;

  // Workforce
  List<_AttendancePoint> _attendanceTrend = [];

  // KPIs (not range-scoped — running totals as of now)
  double? _cashFloatBalance;
  int _stockedItemCount = 0;
  List<MapEntry<String, Map<String, dynamic>>> _topStockItems = [];

  static DateTimeRange _rangeFor(_QuickRange r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (r) {
      case _QuickRange.last7:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case _QuickRange.last30:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case _QuickRange.last90:
        return DateTimeRange(start: today.subtract(const Duration(days: 89)), end: today);
      case _QuickRange.thisMonth:
        return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
      case _QuickRange.allTime:
        return DateTimeRange(start: DateTime(2000, 1, 1), end: today);
      case _QuickRange.custom:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final start = _range.start;
    final end = _range.end;

    final rangeExpenses = await _db.getExpensesForSiteInRange(widget.siteId, start, end);
    final cats = <String, double>{};
    for (final e in rangeExpenses) {
      final label = e.category.label;
      cats[label] = (cats[label] ?? 0.0) + e.amount;
    }

    final dailyMap = <String, double>{};
    for (final e in rangeExpenses) {
      final key = e.date.toIso8601String().split('T').first;
      dailyMap[key] = (dailyMap[key] ?? 0.0) + e.amount;
    }
    final sortedDates = dailyMap.keys.toList()..sort();
    final burnData =
        sortedDates.map((d) => {'date': d, 'amount': dailyMap[d]!}).toList();

    final cashFloatsInRange = await _db.getCashFloatsForSiteInRange(widget.siteId, start, end);
    double cumFloat = 0;
    double cumSpend = 0;
    final cfData = <_CashFloatData>[];
    for (final c in cashFloatsInRange) {
      cumFloat += c.floatReceived;
      cumSpend += c.totalExpenses;
      cfData.add(_CashFloatData(c.date.toIso8601String().split('T').first, cumFloat, cumSpend));
    }

    // Concrete pour volumes
    final pourRows = await _db.getConcretePourTrendForSite(widget.siteId, start, end);
    final concreteTrend = pourRows
        .map((r) => _TrendPoint(
              (r['log_date'] as String).split('T').first,
              (r['total_volume'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();
    final totalVolume = concreteTrend.fold<double>(0.0, (s, p) => s + p.value);

    // Diesel consumption rate (machines + activities combined, per day)
    final dieselRows = await _db.getDieselConsumptionTrendForSite(widget.siteId, start, end);
    final dieselTrend = dieselRows
        .map((r) => _TrendPoint(
              (r['log_date'] as String).split('T').first,
              ((r['machine_litres'] as num?)?.toDouble() ?? 0.0) +
                  ((r['activity_litres'] as num?)?.toDouble() ?? 0.0),
            ))
        .toList();
    final totalDiesel = dieselTrend.fold<double>(0.0, (s, p) => s + p.value);

    // Worker attendance trend
    final attendanceRows = await _db.getAttendanceTrendForSite(widget.siteId, start, end);
    final byDate = <String, _AttendancePoint>{};
    for (final r in attendanceRows) {
      final date = (r['log_date'] as String).split('T').first;
      final status = r['status'] as String;
      final cnt = (r['cnt'] as num).toInt();
      final point = byDate.putIfAbsent(date, () => _AttendancePoint(date, 0, 0, 0));
      switch (status) {
        case 'Present':
          point.present += cnt;
          break;
        case 'Absent':
          point.absent += cnt;
          break;
        case 'Half-Day':
          point.halfDay += cnt;
          break;
      }
    }
    final attendanceTrend = byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    // KPIs
    final latestFloat = await _db.getLatestCashFloat(widget.siteId);
    final stockLevels = await _db.getCurrentMaterialStockLevels(widget.siteId);
    final stockedEntries = stockLevels.entries.where((e) => (e.value['balance'] as double) > 0).toList()
      ..sort((a, b) => (b.value['balance'] as double).compareTo(a.value['balance'] as double));

    if (!mounted) return;
    setState(() {
      _categoryTotals = cats;
      _dailyBurn = burnData;
      _cashFlowData = cfData;
      _totalExpenditure = rangeExpenses.fold<double>(0.0, (s, e) => s + e.amount);
      _concreteVolumeTrend = concreteTrend;
      _totalConcreteVolume = totalVolume;
      _dieselTrend = dieselTrend;
      _totalDieselLitres = totalDiesel;
      _attendanceTrend = attendanceTrend;
      _cashFloatBalance = latestFloat?.expectedClosingBalance;
      _stockedItemCount = stockedEntries.length;
      _topStockItems = stockedEntries.take(3).toList();
      _isLoading = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _quickRange = _QuickRange.custom;
      });
      _loadData();
    }
  }

  void _selectQuickRange(_QuickRange r) {
    setState(() {
      _quickRange = r;
      _range = _rangeFor(r);
    });
    _loadData();
  }

  Future<void> _batchExport() async {
    final project = widget.project;
    final site = widget.site;
    if (project == null || site == null) return;

    final format = await showModalBottomSheet<BatchExportFormat>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF report'),
              onTap: () => Navigator.pop(ctx, BatchExportFormat.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel workbook'),
              onTap: () => Navigator.pop(ctx, BatchExportFormat.excel),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('Both (PDF + Excel)'),
              onTap: () => Navigator.pop(ctx, BatchExportFormat.both),
            ),
          ],
        ),
      ),
    );
    if (format == null) return;

    setState(() => _isExporting = true);
    try {
      await BatchExportService.generateAndShareSiteBatchReport(
        context: context,
        project: project,
        site: site,
        startDate: _range.start,
        endDate: _range.end,
        format: format,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Batch export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSpend = _categoryTotals.values.fold<double>(0.0, (s, v) => s + v);
    final colors = [
      Colors.blue.shade800,
      Colors.teal,
      Colors.amber.shade700,
      Colors.red.shade400,
      Colors.purple,
      Colors.green,
      Colors.orange,
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Analytics — ${widget.siteName}', overflow: TextOverflow.ellipsis),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: SyncStatusBadge(compact: true)),
          ),
          if (widget.project != null && widget.site != null)
            IconButton(
              icon: _isExporting
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
              tooltip: 'Batch export this range',
              onPressed: _isExporting ? null : _batchExport,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRangeSelector(),
                    const SizedBox(height: 16),
                    _buildKpiRow(),
                    const SizedBox(height: 24),

                    _SectionTitle('Expenditure by Category'),
                    SizedBox(
                      height: 280,
                      child: _categoryTotals.isEmpty
                          ? const _EmptyState()
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: (_categoryTotals.values.reduce((a, b) => a > b ? a : b)) * 1.2,
                                barTouchData: BarTouchData(enabled: true),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: true, reservedSize: 60),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        final keys = _categoryTotals.keys.toList();
                                        if (value.toInt() >= 0 && value.toInt() < keys.length) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              keys[value.toInt()].split(' ').first,
                                              style: const TextStyle(fontSize: 10),
                                            ),
                                          );
                                        }
                                        return const SizedBox();
                                      },
                                    ),
                                  ),
                                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: _categoryTotals.values.toList().asMap().entries.map((e) {
                                  return BarChartGroupData(
                                    x: e.key,
                                    barRods: [
                                      BarChartRodData(
                                        toY: e.value,
                                        color: colors[e.key % colors.length],
                                        width: 18,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Budget Share'),
                    SizedBox(
                      height: 240,
                      child: _categoryTotals.isEmpty
                          ? const _EmptyState()
                          : PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 40,
                                sections: _categoryTotals.entries.toList().asMap().entries.map((e) {
                                  final entry = e.value;
                                  final pct = totalSpend > 0 ? entry.value / totalSpend * 100 : 0;
                                  return PieChartSectionData(
                                    color: colors[e.key % colors.length],
                                    value: entry.value,
                                    title: '${pct.toStringAsFixed(0)}%',
                                    radius: 80,
                                    titleStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Daily Expense Burn Rate'),
                    SizedBox(
                      height: 240,
                      child: _dailyBurn.isEmpty
                          ? const _EmptyState()
                          : LineChart(_lineChartFor(
                              spots: _dailyBurn.asMap().entries.map((e) {
                                return FlSpot(e.key.toDouble(), e.value['amount'] as double);
                              }).toList(),
                              labels: _dailyBurn.map((e) => (e['date'] as String)).toList(),
                              color: Colors.red.shade400,
                              filled: true,
                            )),
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Cumulative Float vs Spend'),
                    SizedBox(
                      height: 240,
                      child: _cashFlowData.isEmpty
                          ? const _EmptyState()
                          : LineChart(
                              LineChartData(
                                gridData: FlGridData(show: true),
                                titlesData: _trendTitles(_cashFlowData.map((e) => e.date).toList()),
                                borderData: FlBorderData(show: true),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _cashFlowData.asMap().entries.map((e) {
                                      return FlSpot(e.key.toDouble(), e.value.cumFloat);
                                    }).toList(),
                                    isCurved: false,
                                    color: Colors.green,
                                    barWidth: 3,
                                    dotData: const FlDotData(show: false),
                                  ),
                                  LineChartBarData(
                                    spots: _cashFlowData.asMap().entries.map((e) {
                                      return FlSpot(e.key.toDouble(), e.value.cumSpend);
                                    }).toList(),
                                    isCurved: false,
                                    color: Colors.red,
                                    barWidth: 3,
                                    dotData: const FlDotData(show: false),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(child: _SectionTitle('Concrete Pour Volumes (m³)')),
                        if (_totalConcreteVolume > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Total: ${_totalConcreteVolume.toStringAsFixed(1)} m³',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 240,
                      child: _concreteVolumeTrend.isEmpty
                          ? const _EmptyState()
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: _concreteVolumeTrend
                                        .map((p) => p.value)
                                        .reduce((a, b) => a > b ? a : b) *
                                    1.2,
                                titlesData: _trendTitles(
                                  _concreteVolumeTrend.map((p) => p.date).toList(),
                                  asBarTitles: true,
                                ),
                                borderData: FlBorderData(show: false),
                                barTouchData: BarTouchData(enabled: true),
                                barGroups: _concreteVolumeTrend.asMap().entries.map((e) {
                                  return BarChartGroupData(x: e.key, barRods: [
                                    BarChartRodData(
                                      toY: e.value.value,
                                      color: Colors.blueGrey.shade600,
                                      width: 14,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(child: _SectionTitle('Diesel Consumption Rate (L/day)')),
                        if (_totalDieselLitres > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Total: ${_totalDieselLitres.toStringAsFixed(0)} L',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 240,
                      child: _dieselTrend.isEmpty
                          ? const _EmptyState()
                          : LineChart(_lineChartFor(
                              spots: _dieselTrend
                                  .asMap()
                                  .entries
                                  .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                                  .toList(),
                              labels: _dieselTrend.map((e) => e.date).toList(),
                              color: Colors.orange.shade700,
                              filled: true,
                            )),
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Worker Attendance Trend'),
                    SizedBox(
                      height: 260,
                      child: _attendanceTrend.isEmpty
                          ? const _EmptyState()
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: _attendanceTrend
                                        .map((p) => (p.present + p.absent + p.halfDay).toDouble())
                                        .reduce((a, b) => a > b ? a : b) *
                                    1.2,
                                titlesData: _trendTitles(
                                  _attendanceTrend.map((p) => p.date).toList(),
                                  asBarTitles: true,
                                ),
                                borderData: FlBorderData(show: false),
                                barTouchData: BarTouchData(enabled: true),
                                barGroups: _attendanceTrend.asMap().entries.map((e) {
                                  final p = e.value;
                                  return BarChartGroupData(x: e.key, barRods: [
                                    BarChartRodData(
                                      toY: (p.present + p.absent + p.halfDay).toDouble(),
                                      width: 14,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                      rodStackItems: [
                                        BarChartRodStackItem(0, p.present.toDouble(), Colors.green),
                                        BarChartRodStackItem(p.present.toDouble(),
                                            (p.present + p.halfDay).toDouble(), Colors.amber),
                                        BarChartRodStackItem(
                                            (p.present + p.halfDay).toDouble(),
                                            (p.present + p.halfDay + p.absent).toDouble(),
                                            Colors.red.shade300),
                                      ],
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildAttendanceLegend(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRangeSelector() {
    final fmt = DateFormat.MMMd();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _rangeChip('7D', _QuickRange.last7),
              _rangeChip('30D', _QuickRange.last30),
              _rangeChip('90D', _QuickRange.last90),
              _rangeChip('This Month', _QuickRange.thisMonth),
              _rangeChip('All Time', _QuickRange.allTime),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(_quickRange == _QuickRange.custom
                    ? '${fmt.format(_range.start)} – ${fmt.format(_range.end)}'
                    : 'Custom'),
                onPressed: _pickCustomRange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rangeChip(String label, _QuickRange r) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _quickRange == r,
        onSelected: (_) => _selectQuickRange(r),
      ),
    );
  }

  Widget _buildKpiRow() {
    final topItemsLabel = _topStockItems.isEmpty
        ? 'No stock logged'
        : _topStockItems
            .map((e) =>
                '${e.key}: ${(e.value['balance'] as double).toStringAsFixed(0)} ${e.value['unit'] ?? ''}')
            .join(' • ');

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: 'Total Expenditure',
                value: CurrencyFormatter.formatCompact(_totalExpenditure),
                subtitle: 'Selected range',
                icon: Icons.account_balance_wallet,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'Cash Float Balance',
                value: _cashFloatBalance == null
                    ? '—'
                    : CurrencyFormatter.formatCompact(_cashFloatBalance!),
                subtitle: _cashFloatBalance != null && _cashFloatBalance! < 0
                    ? 'Deficit — needs top-up'
                    : 'Current balance',
                icon: Icons.savings,
                color: (_cashFloatBalance ?? 0) < 0 ? Colors.orange : Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _KpiCard(
          title: 'Total Material Stock Levels',
          value: '$_stockedItemCount items in stock',
          subtitle: topItemsLabel,
          icon: Icons.inventory_2,
          color: Colors.indigo,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildAttendanceLegend() {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        );
    return Wrap(
      spacing: 16,
      children: [
        dot(Colors.green, 'Present'),
        dot(Colors.amber, 'Half-Day'),
        dot(Colors.red.shade300, 'Absent'),
      ],
    );
  }

  LineChartData _lineChartFor({
    required List<FlSpot> spots,
    required List<String> labels,
    required Color color,
    bool filled = false,
  }) {
    return LineChartData(
      gridData: FlGridData(show: true),
      titlesData: _trendTitles(labels),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          dotData: FlDotData(show: spots.length <= 20),
          belowBarData: filled ? BarAreaData(show: true, color: color.withOpacity(0.15)) : BarAreaData(show: false),
        ),
      ],
    );
  }

  FlTitlesData _trendTitles(List<String> dateLabels, {bool asBarTitles = false}) {
    final interval = (dateLabels.length / 6).ceil().clamp(1, dateLabels.length == 0 ? 1 : dateLabels.length);
    return FlTitlesData(
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= dateLabels.length) return const SizedBox();
            if (i % interval != 0) return const SizedBox();
            final raw = dateLabels[i];
            final label = raw.length >= 10 ? raw.substring(5) : raw;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(label, style: const TextStyle(fontSize: 10)),
            );
          },
        ),
      ),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }
}

Widget _SectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Builder(
      builder: (context) => Text(
        text,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(child: Text('No data for this range'));
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _CashFloatData {
  final String date;
  final double cumFloat;
  final double cumSpend;

  _CashFloatData(this.date, this.cumFloat, this.cumSpend);
}

class _TrendPoint {
  final String date;
  final double value;
  _TrendPoint(this.date, this.value);
}

class _AttendancePoint {
  final String date;
  int present;
  int absent;
  int halfDay;
  _AttendancePoint(this.date, this.present, this.absent, this.halfDay);
}
