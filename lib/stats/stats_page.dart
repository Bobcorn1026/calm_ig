import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'charts/daily_bar_chart.dart';
import 'daily_stats.dart';
import 'day_key.dart';
import 'usage_tracker.dart';

/// 今日紀錄: today's numbers, trend charts, and the settings for the pass
/// quota and the "這次要做什麼？" options. Opened by tapping the clock.
class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.stats,
    required this.tracker,
    required this.settings,
    required this.onEditIntentOptions,
    this.clock = DateTime.now,
  });

  final StatsStore stats;
  final UsageTracker tracker;
  final AppSettings settings;

  /// Opens the "這次要做什麼？" option editor.
  final VoidCallback onEditIntentOptions;
  final DateTime Function() clock;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

const _minuteSteps = <double>[5, 10, 15, 30, 60, 120, 180, 240, 360, 480, 720];
const _countSteps = <double>[1, 2, 5, 10, 20, 50, 100];

/// `1 小時 23 分`, or `不到 1 分` for a few seconds.
String _duration(Duration d) =>
    d > Duration.zero && d < const Duration(minutes: 1)
    ? '不到 1 分'
    : formatMinutes(d);

double _minutes(Duration d) => d.inSeconds / 60;

/// Average per day, counted from the first day in [days] with any time, so
/// days before calm_ig was installed don't pull it down.
Duration _average(List<Duration> days) {
  final first = days.indexWhere((d) => d > Duration.zero);
  if (first < 0) return Duration.zero;
  final counted = days.sublist(first);
  return counted.fold(Duration.zero, (a, b) => a + b) ~/ counted.length;
}

class _StatsPageState extends State<StatsPage> with WidgetsBindingObserver {
  late final Timer _ticker;
  late final ValueNotifier<Duration> _usageToday;
  late String _day;
  int _range = 7;

  @override
  void initState() {
    super.initState();
    _usageToday = ValueNotifier(widget.tracker.today);
    _day = dayKey(widget.clock());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    widget.settings.addListener(_redraw);
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  /// Back from another app: the App Intent may have counted bounces.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_redraw);
      widget.settings.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_redraw);
    _usageToday.dispose();
    super.dispose();
  }

  /// Picks up bounce counts the iOS App Intent wrote since launch.
  Future<void> _reload() async {
    await widget.stats.reload();
    _redraw();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// The big number ticks every second; the charts only redraw when the
  /// minute (or the day) changes.
  void _tick() {
    final usage = widget.tracker.today;
    final day = dayKey(widget.clock());
    final redraw =
        day != _day || usage.inMinutes != _usageToday.value.inMinutes;
    _day = day;
    _usageToday.value = usage;
    if (redraw) _redraw();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.clock();
    final today = widget.stats.today(now);
    final quota = widget.settings.passQuota;
    final recent = widget.stats.recent(now, _range);
    final dates = lastDays(now, _range);
    final colors = ChartColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('今日紀錄')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TodayCard(
              date: now,
              usage: _usageToday,
              today: today,
              quota: quota,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('趨勢', style: theme.textTheme.titleMedium)),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 天')),
                    ButtonSegment(value: 30, label: Text('30 天')),
                  ],
                  selected: {_range},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _range = selection.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _usageChart(dates, recent, colors),
            const SizedBox(height: 12),
            _passChart(dates, recent, quota, colors),
            const SizedBox(height: 12),
            _bounceChart(dates, recent, colors),
            const SizedBox(height: 24),
            Text('設定', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('每日放行額度'),
                    subtitle: const Text('用完要打一句話才放行'),
                    trailing: _QuotaStepper(
                      value: quota,
                      onChanged: widget.settings.setPassQuota,
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text('開場選項'),
                    subtitle: const Text('「這次要做什麼？」的選項'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onEditIntentOptions,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usageChart(
    List<DateTime> dates,
    List<DayStats> recent,
    ChartColors colors,
  ) {
    // The stored total misses the stretch on screen right now.
    final usage = [
      for (final d in recent.take(recent.length - 1)) d.usage,
      widget.tracker.today,
    ];
    final minutes = [for (final d in usage) _minutes(d)];
    final peak = minutes.fold(30.0, (a, b) => a > b ? a : b);
    final scale = ChartScale.fit(peak, _minuteSteps);
    final average = _average(usage);
    final total = usage.fold(Duration.zero, (a, b) => a + b);
    return _ChartCard(
      title: '使用時間趨勢',
      subtitle: '近 $_range 天共 ${_duration(total)}',
      chart: DailyBarChart(
        key: ValueKey('usage$_range'),
        days: dates,
        values: [
          for (final m in minutes) [m],
        ],
        colors: [colors.series],
        earlierColor: colors.earlier,
        scale: scale,
        yLabel: (v) => v == 0
            ? '0'
            : scale.interval < 60
            ? '${v.round()}分'
            : '${(v / 60).round()}小時',
        describe: (i) => _duration(usage[i]),
        reference: average > Duration.zero
            ? ReferenceLine(_minutes(average), '平均 ${_duration(average)}')
            : null,
      ),
    );
  }

  Widget _passChart(
    List<DateTime> dates,
    List<DayStats> recent,
    int quota,
    ChartColors colors,
  ) {
    final peak = recent.fold(
      quota < 3 ? 3 : quota,
      (a, d) => d.passes > a ? d.passes : a,
    );
    final passes = recent.fold(0, (a, d) => a + d.passes);
    final over = recent.fold(0, (a, d) => a + d.overQuotaPasses);
    final theme = Theme.of(context);
    return _ChartCard(
      title: '放行',
      subtitle: over > 0
          ? '近 $_range 天放行 $passes 次，其中超額 $over 次'
          : '近 $_range 天放行 $passes 次',
      legend: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _LegendKey(color: colors.series, label: '額度內'),
          _LegendKey(color: colors.over, label: '超額'),
          _LegendKey(
            color: theme.colorScheme.onSurfaceVariant,
            label: '每日額度',
            dashed: true,
          ),
        ],
      ),
      chart: DailyBarChart(
        key: ValueKey('passes$_range'),
        days: dates,
        values: [
          for (final d in recent)
            [
              (d.passes - d.overQuotaPasses).clamp(0, d.passes).toDouble(),
              d.overQuotaPasses.clamp(0, d.passes).toDouble(),
            ],
        ],
        colors: [colors.series, colors.over],
        scale: ChartScale.fit(peak.toDouble(), _countSteps),
        yLabel: (v) => '${v.round()}',
        describe: (i) {
          final d = recent[i];
          final over = d.overQuotaPasses > 0
              ? '超額 ${d.overQuotaPasses} 次'
              : '沒有超額';
          final overtime = d.overtime > Duration.zero
              ? '超時 ${_duration(d.overtime)}'
              : '沒有超時';
          return '放行 ${d.passes} 次（$over）\n$overtime';
        },
        reference: ReferenceLine(quota.toDouble(), '額度 $quota 次'),
      ),
    );
  }

  Widget _bounceChart(
    List<DateTime> dates,
    List<DayStats> recent,
    ChartColors colors,
  ) {
    final peak = recent.fold(3, (a, d) => d.bounces > a ? d.bounces : a);
    final total = recent.fold(0, (a, d) => a + d.bounces);
    return _ChartCard(
      title: '被擋回',
      subtitle: '近 $_range 天共擋回 $total 次',
      chart: DailyBarChart(
        key: ValueKey('bounces$_range'),
        days: dates,
        values: [
          for (final d in recent) [d.bounces.toDouble()],
        ],
        colors: [colors.series],
        earlierColor: colors.earlier,
        scale: ChartScale.fit(peak.toDouble(), _countSteps),
        yLabel: (v) => '${v.round()}',
        describe: (i) => '擋回 ${recent[i].bounces} 次',
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.date,
    required this.usage,
    required this.today,
    required this.quota,
  });

  final DateTime date;
  final ValueListenable<Duration> usage;
  final DayStats today;
  final int quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final over = today.overQuotaPasses;
    final intents = today.intents.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今天 ${dayLabel(date)}',
              style: theme.textTheme.labelLarge?.copyWith(color: muted),
            ),
            ValueListenableBuilder<Duration>(
              valueListenable: usage,
              builder: (context, value, _) => Text(
                formatStopwatch(value),
                semanticsLabel: '今天已使用 ${_duration(value)}',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'Instagram 使用時間 · 每天午夜自動歸零',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const Divider(height: 24),
            _StatRow(
              icon: Icons.near_me_outlined,
              label: '放行',
              value:
                  '已放行 ${today.passes} / 額度 $quota 次'
                  '${over > 0 ? '（超額 $over 次）' : ''}',
            ),
            _StatRow(
              icon: Icons.hourglass_bottom,
              label: '超時',
              value: today.overtime > Duration.zero
                  ? _duration(today.overtime)
                  : '沒有超時',
            ),
            _StatRow(
              icon: Icons.undo,
              label: '被擋回',
              value: '${today.bounces} 次',
              caption: '打開原生 IG 被帶回來的次數',
            ),
            if (intents.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('這次要做什麼？', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in intents)
                    Chip(
                      label: Text('${e.key} ×${e.value}'),
                      labelStyle: theme.textTheme.labelMedium,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Icon, label and value on one line; an optional caption below.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: muted),
              const SizedBox(width: 12),
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Text(
                caption!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.chart,
    this.legend,
  });

  final String title;
  final String subtitle;
  final Widget chart;
  final Widget? legend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (legend != null) ...[const SizedBox(height: 8), legend!],
            const SizedBox(height: 8),
            chart,
          ],
        ),
      ),
    );
  }
}

/// A swatch (or a dashed line) and its name.
class _LegendKey extends StatelessWidget {
  const _LegendKey({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          for (var i = 0; i < 3; i++)
            Container(
              width: 4,
              height: 1.5,
              margin: const EdgeInsets.only(right: 2),
              color: color,
            )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// − n 次 +, from 0 to [AppSettings.maxPassQuota].
class _QuotaStepper extends StatelessWidget {
  const _QuotaStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '減少額度',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$value 次',
            key: const ValueKey('quota-value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: '增加額度',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < AppSettings.maxPassQuota
              ? () => onChanged(value + 1)
              : null,
        ),
      ],
    );
  }
}
