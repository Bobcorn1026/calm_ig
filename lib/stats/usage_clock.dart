import 'dart:async';

import 'package:flutter/material.dart';

import 'usage_tracker.dart';

/// The ⏱ 12:34 readout next to the app name: today's Instagram time,
/// redrawn every second. Tapping it opens the daily records.
class UsageClock extends StatefulWidget {
  const UsageClock({super.key, required this.tracker, this.onTap});

  final UsageTracker tracker;
  final VoidCallback? onTap;

  @override
  State<UsageClock> createState() => _UsageClockState();
}

class _UsageClockState extends State<UsageClock> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final text = formatStopwatch(widget.tracker.today);
    return Semantics(
      button: widget.onTap != null,
      label: '今天已使用 $text，查看紀錄',
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined, size: 16, color: color),
              const SizedBox(width: 3),
              Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  // Same width for every digit, so the bar doesn't jiggle.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
