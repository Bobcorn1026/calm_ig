import 'dart:async';

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'intent_option.dart';

/// "這次要做什麼？" — drawn over the web view while [visible] is true.
///
/// Covers the page (taps don't reach it) with one button per saved option.
/// 隨便看看 first makes you wait [browseDelay] on a "先深呼吸一下" screen.
/// With no options saved, it hides itself straight away.
class IntentPrompt extends StatefulWidget {
  const IntentPrompt({
    super.key,
    required this.visible,
    required this.settings,
    required this.onChoose,
    required this.onEditOptions,
    this.browseDelay = const Duration(seconds: 5),
  });

  /// The tracker's `askIntent`; the prompt sets it back to false when done.
  final ValueNotifier<bool> visible;
  final AppSettings settings;

  /// Records the choice and carries it out (navigate / start a pass).
  final Future<void> Function(IntentOption option) onChoose;

  /// Opens the option editor.
  final VoidCallback onEditOptions;

  /// How long 隨便看看 makes you wait before the page shows.
  final Duration browseDelay;

  @override
  State<IntentPrompt> createState() => _IntentPromptState();
}

class _IntentPromptState extends State<IntentPrompt> {
  /// Seconds left on the 隨便看看 pause; null when it isn't running.
  int? _remaining;
  Timer? _ticker;
  Timer? _pauseEnd;
  bool _hideScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_onVisibleChanged);
    widget.settings.addListener(_onSettingsChanged);
    _hideIfNoOptions();
  }

  @override
  void didUpdateWidget(IntentPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      oldWidget.visible.removeListener(_onVisibleChanged);
      widget.visible.addListener(_onVisibleChanged);
    }
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettingsChanged);
      widget.settings.addListener(_onSettingsChanged);
    }
    _hideIfNoOptions();
  }

  @override
  void dispose() {
    _stopPause();
    widget.visible.removeListener(_onVisibleChanged);
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onVisibleChanged() {
    if (!widget.visible.value) _stopPause();
    _hideIfNoOptions();
    setState(() {});
  }

  void _onSettingsChanged() {
    _hideIfNoOptions();
    setState(() {});
  }

  /// Nothing to ask: give the page back. After the frame, since this can
  /// run while the tree is building.
  void _hideIfNoOptions() {
    if (_hideScheduled) return;
    if (!widget.visible.value || _remaining != null) return;
    if (widget.settings.intentOptions.isNotEmpty) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hideScheduled = false;
      if (!mounted || _remaining != null) return;
      if (widget.settings.intentOptions.isEmpty) widget.visible.value = false;
    });
  }

  void _choose(IntentOption option) {
    if (!widget.visible.value || _remaining != null) return;
    if (option.action == IntentAction.browse) {
      unawaited(widget.onChoose(option));
      _startPause();
    } else {
      // Hide first, so the 發限動 sheet isn't drawn under the menu.
      widget.visible.value = false;
      unawaited(widget.onChoose(option));
    }
  }

  void _startPause() {
    final delay = widget.browseDelay;
    if (delay <= Duration.zero) {
      widget.visible.value = false;
      return;
    }
    setState(() => _remaining = (delay.inMilliseconds / 1000).ceil());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _remaining;
      // [_pauseEnd] hides it; never show 0.
      if (left != null && left > 1) setState(() => _remaining = left - 1);
    });
    _pauseEnd = Timer(delay, () {
      _stopPause();
      widget.visible.value = false;
      if (mounted) setState(() {});
    });
  }

  void _stopPause() {
    _ticker?.cancel();
    _pauseEnd?.cancel();
    _ticker = null;
    _pauseEnd = null;
    _remaining = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible.value) return const SizedBox.shrink();
    final remaining = _remaining;
    final options = widget.settings.intentOptions;
    if (remaining == null && options.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      // Opaque: taps on the dimmed area don't reach the web view.
      child: ColoredBox(
        color: scheme.surfaceDim.withValues(alpha: 0.96),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: remaining == null
                          ? _Menu(
                              key: const ValueKey('menu'),
                              options: options,
                              onChoose: _choose,
                              onEditOptions: widget.onEditOptions,
                            )
                          : _Pause(
                              key: const ValueKey('pause'),
                              remaining: remaining,
                              total: widget.browseDelay,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon for an option, from what it does and where it goes.
IconData intentOptionIcon(IntentOption option) => switch (option.action) {
  IntentAction.pass => Icons.photo_camera_outlined,
  IntentAction.browse => Icons.visibility_outlined,
  IntentAction.open => _openIcon(option.path),
};

IconData _openIcon(String path) {
  if (path.startsWith('/direct')) return Icons.chat_bubble_outline;
  if (path == '/') return Icons.web_stories_outlined;
  if (path.startsWith('/?')) return Icons.dynamic_feed_outlined;
  if (path.startsWith('/explore/search')) return Icons.search;
  if (path.startsWith('/notifications')) return Icons.notifications_none;
  if (RegExp(r'^/[A-Za-z0-9._]{1,30}/?$').hasMatch(path)) {
    return Icons.person_outline;
  }
  return Icons.north_east;
}

class _Menu extends StatelessWidget {
  const _Menu({
    super.key,
    required this.options,
    required this.onChoose,
    required this.onEditOptions,
  });

  final List<IntentOption> options;
  final ValueChanged<IntentOption> onChoose;
  final VoidCallback onEditOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '這次要做什麼？',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '想清楚再打開 IG',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OptionButton(
                        option: option,
                        onTap: () => onChoose(option),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: onEditOptions,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('編輯選項'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.option, required this.onTap});

  final IntentOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Semantics(
      button: true,
      label: option.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(intentOptionIcon(option), color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      option.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: color.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 隨便看看: a short, unskippable breather before the page shows.
class _Pause extends StatelessWidget {
  const _Pause({super.key, required this.remaining, required this.total});

  final int remaining;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '先深呼吸一下',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            label: '還有 $remaining 秒',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1, end: 0),
                    duration: total,
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  Center(
                    child: Text(
                      '$remaining',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: scheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '慢慢吸氣，再慢慢吐氣',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
