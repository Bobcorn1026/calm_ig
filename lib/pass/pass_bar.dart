import 'dart:async';

import 'package:flutter/material.dart';

import '../session/session_clock.dart';
import '../session/session_stopwatch.dart';
import 'pass_controller.dart';
import 'pass_services.dart' show openAppSettings;

/// The slim bar above the web view: app name and session stopwatch, "post a
/// story" pass button, reload, help; or the countdown while a pass is running.
class PassBar extends StatefulWidget {
  const PassBar({
    super.key,
    required this.pass,
    required this.onHelp,
    this.stopwatch,
    this.onReload,
    this.onOpenSettings = openAppSettings,
  });

  final PassController pass;
  final VoidCallback onHelp;

  /// Shown as ⏱ next to the app name when given.
  final SessionStopwatch? stopwatch;

  /// Reload button (a backup for pages where pulling down doesn't work).
  final VoidCallback? onReload;

  /// Opens iOS Settings (to turn notifications on); replaced in tests.
  final Future<void> Function() onOpenSettings;

  @override
  State<PassBar> createState() => _PassBarState();
}

class _PassBarState extends State<PassBar> with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pass.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pass.removeListener(_syncTicker);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Instagram: stop leftover reminders if the pass is
    // over, and redraw with the real remaining time.
    if (state == AppLifecycleState.resumed) widget.pass.onResumed();
  }

  void _syncTicker() {
    if (widget.pass.isActive) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => widget.pass.tick(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _choosePass() async {
    final length = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '暫時放行原生 Instagram',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text('這段時間打開原生 IG 不會被導回來，時間到會通知你。'),
            ),
            for (final length in passLengths)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('${length.inMinutes} 分鐘'),
                onTap: () => Navigator.pop(context, length),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (length == null || !mounted) return;
    if (!await widget.pass.canRemind()) {
      if (!mounted) return;
      final goAnyway = await _askWithoutReminders();
      if (goAnyway != true) return;
    }
    final opened = await widget.pass.start(length);
    // Time in the native app during a pass doesn't end the session: coming
    // back within 5 minutes after the pass continues the stopwatch.
    final until = widget.pass.until;
    if (opened && until != null) widget.stopwatch?.allowBreakUntil(until);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('找不到 Instagram app')));
    }
  }

  /// Notifications are off: reminders can't show. Returns true to open
  /// Instagram anyway.
  Future<bool?> _askWithoutReminders() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('通知被關掉了'),
      content: const Text('這樣放行時間到了，清醒IG 沒辦法提醒你回來。\n要先去設定打開通知嗎？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('照樣放行'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, false);
            widget.onOpenSettings();
          },
          child: const Text('去設定'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.pass,
      builder: (context, _) =>
          widget.pass.isActive ? _active(context) : _idle(context),
    );
  }

  Widget _idle(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Text(
            '清醒IG',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (widget.stopwatch case final stopwatch?) ...[
            const SizedBox(width: 10),
            SessionClock(stopwatch: stopwatch),
          ],
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: _choosePass,
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
              '原生 IG 放行中 · 剩 ${formatRemaining(widget.pass.remaining)}',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(onPressed: widget.pass.end, child: const Text('結束')),
        ],
      ),
    );
  }
}
