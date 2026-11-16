import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Colors for the daily charts: Material teal and deep orange swatches,
/// checked with the dataviz palette validator for contrast on the card
/// surface and color-blind separation, separately for each theme.
class ChartColors {
  const ChartColors._({
    required this.series,
    required this.earlier,
    required this.over,
  });

  static const _light = ChartColors._(
    series: Color(0xFF00897B), // teal 600
    earlier: Color(0xFF4DB6AC), // teal 300
    over: Color(0xFFE64A19), // deep orange 700
  );

  static const _dark = ChartColors._(
    series: Color(0xFF26A69A), // teal 400
    earlier: Color(0xFF00796B), // teal 700
    over: Color(0xFFE64A19), // deep orange 700
  );

  static ChartColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// Today's bar, and passes within the quota.
  final Color series;

  /// Days before today: a quieter step of the same teal.
  final Color earlier;

  /// Passes over the daily quota.
  final Color over;
}

/// The y axis: 0 to [maxY], a tick every [interval].
class ChartScale {
  const ChartScale(this.maxY, this.interval);

  /// The first of [steps] (ascending) that fits [peak] in at most four
  /// ticks above zero, with the top tick above [peak].
  factory ChartScale.fit(double peak, List<double> steps) {
    bool fits(double step) => (peak / step).floor() + 1 <= 4;
    var step = steps.firstWhere(fits, orElse: () => steps.last);
    while (!fits(step)) {
      step *= 2;
    }
    return ChartScale(((peak / step).floor() + 1) * step, step);
  }

  final double maxY;
  final double interval;
}

/// A dashed line across the plot, such as the average or the quota.
class ReferenceLine {
  const ReferenceLine(this.y, this.label);

  final double y;
  final String label;
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// `一` … `日`.
String weekdayShort(DateTime day) => _weekdays[day.weekday - 1];

/// `11/16 週一`.
String dayLabel(DateTime day) =>
    '${day.month}/${day.day} 週${weekdayShort(day)}';

const _xAxisHeight = 22.0;
const _yAxisWidth = 40.0;

/// Room above the plot for the top tick label.
const _topRoom = 8.0;

/// Surface gap between stacked parts, in pixels.
const _partGap = 2.0;

/// One bar per day, oldest first and today last. Tapping a bar shows its
/// numbers in a tooltip. When every bar is zero the axes stay, with
/// "還沒有紀錄" on the plot.
class DailyBarChart extends StatefulWidget {
  const DailyBarChart({
    super.key,
    required this.days,
    required this.values,
    required this.colors,
    required this.scale,
    required this.yLabel,
    required this.describe,
    this.earlierColor,
    this.reference,
  });

  /// The days shown, oldest first; the last one is today.
  final List<DateTime> days;

  /// Per day, the parts of its bar from the bottom up.
  final List<List<double>> values;

  /// The color of each part.
  final List<Color> colors;

  /// For one-part bars: the color of the days before today, so today
  /// stands out. Null paints every day in [colors].
  final Color? earlierColor;

  final ChartScale scale;

  /// Tick label for a y value.
  final String Function(double value) yLabel;

  /// The numbers for day `i`: shown after its date in the tooltip and read
  /// out by screen readers.
  final String Function(int day) describe;

  final ReferenceLine? reference;

  /// Plot plus x axis.
  static const height = 168.0;

  @override
  State<DailyBarChart> createState() => _DailyBarChartState();
}

class _DailyBarChartState extends State<DailyBarChart> {
  int? _selected;

  bool get _empty => widget.values.every((parts) => parts.every((v) => v <= 0));

  void _onTouch(FlTouchEvent event, BarTouchResponse? response) {
    final index = response?.spot?.touchedBarGroupIndex;
    if (event is FlTapUpEvent) {
      // Tapping the open bar (or beside the bars) closes the tooltip.
      setState(() => _selected = index == _selected ? null : index);
    } else if (index != null &&
        index != _selected &&
        (event is FlPanUpdateEvent ||
            event is FlLongPressStart ||
            event is FlLongPressMoveUpdate)) {
      setState(() => _selected = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = _empty;
    final days = widget.days;
    return Semantics(
      container: true,
      label: empty
          ? '還沒有紀錄'
          : [
              for (var i = 0; i < days.length; i++)
                '${dayLabel(days[i])} ${widget.describe(i)}',
            ].join('；'),
      excludeSemantics: true,
      child: SizedBox(
        height: DailyBarChart.height + _topRoom,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = (constraints.maxWidth - _yAxisWidth) / days.length;
            final barWidth = (slot * 0.55).clamp(2.0, 20.0);
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: _topRoom),
                  child: BarChart(_data(theme, slot, barWidth)),
                ),
                if (empty)
                  Positioned(
                    left: _yAxisWidth,
                    right: 0,
                    top: _topRoom,
                    bottom: _xAxisHeight,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          '還沒有紀錄',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  BarChartData _data(ThemeData theme, double slot, double barWidth) {
    final scheme = theme.colorScheme;
    final scale = widget.scale;
    final axisStyle = TextStyle(
      fontSize: 10,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final reference = widget.reference;
    final plotHeight = DailyBarChart.height - _xAxisHeight - 1; // baseline
    final gap = _partGap * scale.maxY / plotHeight;
    final radius = Radius.circular(math.min(4, barWidth / 3));

    return BarChartData(
      minY: 0,
      maxY: scale.maxY,
      alignment: BarChartAlignment.spaceAround,
      barGroups: [
        for (var i = 0; i < widget.days.length; i++)
          BarChartGroupData(
            x: i,
            showingTooltipIndicators: i == _selected ? const [0] : const [],
            barRods: [_rod(i, barWidth, radius, gap, scheme)],
          ),
      ],
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: scale.interval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _yAxisWidth,
            interval: scale.interval,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              space: 6,
              child: Text(widget.yLabel(value), style: axisStyle),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _xAxisHeight,
            getTitlesWidget: (value, meta) =>
                _dayTitle(value.toInt(), meta, axisStyle, scheme),
          ),
        ),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (reference != null)
            HorizontalLine(
              y: reference.y,
              color: scheme.onSurfaceVariant,
              strokeWidth: 1,
              dashArray: const [4, 3],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface,
                  // Stays readable where it crosses a bar.
                  backgroundColor:
                      theme.cardTheme.color ?? scheme.surfaceContainerLow,
                ),
                labelResolver: (_) => reference.label,
              ),
            ),
        ],
      ),
      barTouchData: BarTouchData(
        handleBuiltInTouches: false,
        allowTouchBarBackDraw: true,
        touchExtraThreshold: EdgeInsets.symmetric(
          horizontal: math.max(0, (slot - barWidth) / 2),
        ),
        touchCallback: _onTouch,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => scheme.inverseSurface,
          tooltipBorderRadius: BorderRadius.circular(8),
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          tooltipMargin: 8,
          maxContentWidth: 240,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
              _tooltip(groupIndex, theme),
        ),
      ),
    );
  }

  BarChartRodData _rod(
    int i,
    double width,
    Radius radius,
    double gap,
    ColorScheme scheme,
  ) {
    final parts = widget.values[i];
    final total = parts.fold(0.0, (a, b) => a + b);
    final isToday = i == widget.days.length - 1;
    final earlier = widget.earlierColor;
    final single = parts.length == 1;
    return BarChartRodData(
      toY: total,
      width: width,
      borderRadius: BorderRadius.vertical(top: radius),
      color: !single
          ? Colors.transparent
          : (earlier != null && !isToday ? earlier : widget.colors.first),
      rodStackItems: single ? null : _stack(parts, gap),
      // Full height, so the whole column is tappable; tinted when selected.
      backDrawRodData: BackgroundBarChartRodData(
        show: true,
        toY: widget.scale.maxY,
        color: i == _selected
            ? scheme.onSurface.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
    );
  }

  /// The non-empty parts, with a [_partGap] between neighbours.
  List<BarChartRodStackItem> _stack(List<double> parts, double gap) {
    final shown = [
      for (var k = 0; k < parts.length; k++)
        if (parts[k] > 0) k,
    ];
    final items = <BarChartRodStackItem>[];
    var from = 0.0;
    for (var k = 0; k < parts.length; k++) {
      final to = from + parts[k];
      if (parts[k] > 0) {
        items.add(
          BarChartRodStackItem(
            k == shown.first ? from : from + gap / 2,
            k == shown.last ? to : to - gap / 2,
            widget.colors[k],
          ),
        );
      }
      from = to;
    }
    return items;
  }

  /// Weekdays for a week; for longer ranges the day of the month every
  /// five days, counted back from today so today always has one.
  Widget _dayTitle(int i, TitleMeta meta, TextStyle style, ColorScheme scheme) {
    final days = widget.days;
    final fromEnd = days.length - 1 - i;
    final day = days[i];
    final text = days.length <= 7
        ? weekdayShort(day)
        : (fromEnd % 5 == 0 ? '${day.day}' : null);
    if (text == null) return const SizedBox.shrink();
    final isToday = fromEnd == 0;
    return SideTitleWidget(
      meta: meta,
      space: 4,
      child: Text(
        text,
        style: isToday
            ? style.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              )
            : style,
      ),
    );
  }

  BarTooltipItem _tooltip(int i, ThemeData theme) {
    final style = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onInverseSurface,
      height: 1.4,
    );
    return BarTooltipItem(
      '${dayLabel(widget.days[i])} · ',
      style,
      children: [
        TextSpan(
          text: widget.describe(i),
          style: style.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
