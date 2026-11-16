import 'dart:async';

import 'package:flutter/material.dart';

import 'session_stopwatch.dart';

/// The ⏱ 12:34 readout next to the app name, redrawn every second.
class SessionClock extends StatefulWidget {
  const SessionClock({super.key, required this.stopwatch});

  final SessionStopwatch stopwatch;

  @override
  State<SessionClock> createState() => _SessionClockState();
}

class _SessionClockState extends State<SessionClock> {
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
    final text = formatStopwatch(widget.stopwatch.elapsed);
    return Semantics(
      label: '這次已使用 $text',
      excludeSemantics: true,
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
    );
  }
}
