import 'dart:async';

import 'package:flutter/material.dart';

import 'pass_controller.dart';

/// The slim bar above the web view: app name, "post a story" pass button,
/// help; or the countdown while a pass is running.
class PassBar extends StatefulWidget {
  const PassBar({super.key, required this.pass, required this.onHelp});

  final PassController pass;
  final VoidCallback onHelp;

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
    // Coming back from Instagram: redraw with the real remaining time.
    if (state == AppLifecycleState.resumed) widget.pass.tick();
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
    final opened = await widget.pass.start(length);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('找不到 Instagram app')));
    }
  }

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
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: _choosePass,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('發限動'),
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
