import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/database_helper.dart';
import '../models/expense.dart';
import '../utils/currency_formatter.dart';

/// Visual analytics for a single site: category breakdown, burn rate,
/// and cumulative cash-flow trends.
class AnalyticsScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const AnalyticsScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, double> _categoryTotals = {};
  List<Map<String, dynamic>> _dailyBurn = [];
  List<_CashFloatData> _cashFlowData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final rawCats = await _db.getExpenseTotalsByCategory(widget.siteId);
    final cats = <String, double>{
      for (final entry in rawCats.entries)
        ExpenseCategoryX.fromLabelOrName(entry.key).label: entry.value,
    };
    final allExp = await _db.getExpensesForSite(widget.siteId);
    final cashFloats = await _db.getCashFloatsForSite(widget.siteId);

    final dailyMap = <String, double>{};
    for (final e in allExp) {
      final key = e.date.toIso8601String().split('T').first;
      dailyMap[key] = (dailyMap[key] ?? 0.0) + e.amount;
    }
    final sortedDates = dailyMap.keys.toList()..sort();
    final burnData = sortedDates
        .map((d) => {'date': d, 'amount': dailyMap[d]!})
        .toList();

    double cumFloat = 0;
    double cumSpend = 0;
    final cfData = <_CashFloatData>[];
    for (final c in cashFloats.reversed) {
      cumFloat += c.floatReceived;
      cumSpend += c.totalExpenses;
      cfData.add(_CashFloatData(
        c.date.toIso8601String().split('T').first,
        cumFloat,
        cumSpend,
      ));
    }

    setState(() {
      _categoryTotals = cats;
      _dailyBurn = burnData;
      _cashFlowData = cfData.reversed.toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalSpend =
        _categoryTotals.values.fold<double>(0.0, (s, v) => s + v);
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
        title: Text(
          'Analytics — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle('Expenditure by Category'),
                  SizedBox(
                    height: 280,
                    child: _categoryTotals.isEmpty
                        ? const Center(child: Text('No data'))
                        : BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (_categoryTotals.values.reduce(
                                    (a, b) => a > b ? a : b,
                                  )) *
                                  1.2,
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 60,
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final keys =
                                          _categoryTotals.keys.toList();
                                      if (value.toInt() >= 0 &&
                                          value.toInt() < keys.length) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            keys[value.toInt()]
                                                .split(' ')
                                                .first,
                                            style:
                                                const TextStyle(fontSize: 10),
                                          ),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: _categoryTotals.values
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) {
                                return BarChartGroupData(
                                  x: e.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: e.value,
                                      color: colors[e.key % colors.length],
                                      width: 18,
                                      borderRadius:
                                          const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
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
                        ? const Center(child: Text('No data'))
                        : PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: _categoryTotals.entries
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) {
                                final entry = e.value;
                                final pct = totalSpend > 0
                                    ? entry.value / totalSpend * 100
                                    : 0;
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
                        ? const Center(child: Text('No data'))
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(show: true),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 60,
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      if (value.toInt() >= 0 &&
                                          value.toInt() < _dailyBurn.length) {
                                        final date = _dailyBurn[value.toInt()]
                                            ['date'] as String;
                                        return Text(
                                          date.substring(5),
                                          style:
                                              const TextStyle(fontSize: 10),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _dailyBurn.asMap().entries.map((e) {
                                    return FlSpot(
                                      e.key.toDouble(),
                                      e.value['amount'] as double,
                                    );
                                  }).toList(),
                                  isCurved: true,
                                  color: Colors.red.shade400,
                                  barWidth: 3,
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.red.shade100,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle('Cumulative Float vs Spend'),
                  SizedBox(
                    height: 240,
                    child: _cashFlowData.isEmpty
                        ? const Center(child: Text('No data'))
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(show: true),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 60,
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      if (value.toInt() >= 0 &&
                                          value.toInt() <
                                              _cashFlowData.length) {
                                        return Text(
                                          _cashFlowData[value.toInt()]
                                              .date
                                              .substring(5),
                                          style:
                                              const TextStyle(fontSize: 10),
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  ),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _cashFlowData
                                      .asMap()
                                      .entries
                                      .map((e) {
                                    return FlSpot(
                                      e.key.toDouble(),
                                      e.value.cumFloat,
                                    );
                                  }).toList(),
                                  isCurved: false,
                                  color: Colors.green,
                                  barWidth: 3,
                                ),
                                LineChartBarData(
                                  spots: _cashFlowData
                                      .asMap()
                                      .entries
                                      .map((e) {
                                    return FlSpot(
                                      e.key.toDouble(),
                                      e.value.cumSpend,
                                    );
                                  }).toList(),
                                  isCurved: false,
                                  color: Colors.red,
                                  barWidth: 3,
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _SectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
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
