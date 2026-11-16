import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../filter/filter_health.dart';
import '../stats/usage_clock.dart';
import 'pass_controller.dart';
import 'pass_flow.dart';

/// The slim bar above the web view: app name, today's time (tap for the
/// daily records), a filter warning when needed, "post a story" pass
/// button, reload, help; or the countdown while a pass is running.
class PassBar extends StatefulWidget {
  const PassBar({
    super.key,
    required this.flow,
    required this.onHelp,
    this.onOpenStats,
    this.onReload,
    this.filterHealth,
  });

  final PassFlow flow;
  final VoidCallback onHelp;

  /// Tapping today's time opens the daily records.
  final VoidCallback? onOpenStats;

  /// Reload button (a backup for pages where pulling down doesn't work).
  final VoidCallback? onReload;

  /// Shows a warning next to the name when the filter stops recognising
  /// Instagram's pages.
  final ValueListenable<FilterHealth?>? filterHealth;

  @override
  State<PassBar> createState() => _PassBarState();
}

class _PassBarState extends State<PassBar> with WidgetsBindingObserver {
  Timer? _ticker;

  PassController get _pass => widget.flow.pass;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pass.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pass.removeListener(_syncTicker);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Instagram: stop leftover reminders if the pass is
    // over, and redraw with the real remaining time.
    if (state == AppLifecycleState.resumed) _pass.onResumed();
  }

  void _syncTicker() {
    if (_pass.isActive) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pass.tick(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pass,
      builder: (context, _) =>
          _pass.isActive ? _active(context) : _idle(context),
    );
  }

  Widget _idle(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 16),
          // Name, time and warning shrink together on narrow screens or
          // with large text instead of overflowing.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '清醒IG',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  UsageClock(
                    tracker: widget.flow.tracker,
                    onTap: widget.onOpenStats,
                  ),
                  if (widget.filterHealth case final health?)
                    _FilterWarning(health: health),
                ],
              ),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => widget.flow.run(context),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('發限動'),
          ),
          if (widget.onReload case final onReload?)
            IconButton(
              tooltip: '重新載入',
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: '捷徑設定教學',
            onPressed: widget.onHelp,
            icon: const Icon(Icons.help_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _active(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          Icon(Icons.lock_open, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '原生 IG 放行中 · 剩 ${formatRemaining(_pass.remaining)}',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(onPressed: widget.flow.end, child: const Text('結束')),
        ],
      ),
    );
  }
}

/// A small amber icon, shown only while the filter reports problems.
class _FilterWarning extends StatelessWidget {
  const _FilterWarning({required this.health});

  final ValueListenable<FilterHealth?> health;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FilterHealth?>(
      valueListenable: health,
      builder: (context, value, _) {
        if (value == null || value.ok) return const SizedBox.shrink();
        return Semantics(
          button: true,
          label: '過濾可能失效',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                icon: const Icon(Icons.warning_amber_rounded),
                title: const Text('過濾可能失效'),
                content: Text(
                  'IG 的網頁好像改版了，清醒IG 認不太出來：\n\n'
                  '${value.descriptions.map((d) => '• $d').join('\n')}\n\n'
                  '跟 Claude 說「清醒IG 過濾失效」，請它更新過濾規則。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Colors.amber.shade700,
              ),
            ),
          ),
        );
      },
    );
  }
}
