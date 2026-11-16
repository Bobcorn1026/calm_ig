import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../stats/daily_stats.dart';
import '../stats/usage_tracker.dart';
import 'pass_controller.dart';
import 'pass_services.dart' show openAppSettings;

/// Typing this exactly is the way past the daily pass quota.
const overQuotaPhrase = '我真的需要發限動';

/// Everything the "發限動" flow needs. Shared by the top bar and the
/// "這次要做什麼？" menu.
class PassFlow {
  const PassFlow({
    required this.pass,
    required this.stats,
    required this.settings,
    required this.tracker,
    this.onOpenSettings = openAppSettings,
    this.clock = DateTime.now,
  });

  final PassController pass;
  final StatsStore stats;
  final AppSettings settings;
  final UsageTracker tracker;

  /// Opens iOS Settings (to turn notifications on); replaced in tests.
  final Future<void> Function() onOpenSettings;
  final DateTime Function() clock;

  /// Pick a length, get past the quota and notification checks, then open
  /// the native app. Records the pass if Instagram opened.
  Future<void> run(BuildContext context) async {
    final today = stats.today(clock());
    final quota = settings.passQuota;
    final overQuota = today.passes >= quota;

    final length = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (context) => _PassLengthSheet(today: today, quota: quota),
    );
    if (length == null || !context.mounted) return;

    if (overQuota) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) =>
            _OverQuotaDialog(used: today.passes, quota: quota),
      );
      if (confirmed != true || !context.mounted) return;
    }

    if (!await pass.canRemind()) {
      if (!context.mounted) return;
      final goAnyway = await showDialog<bool>(
        context: context,
        builder: (context) =>
            _NoRemindersDialog(onOpenSettings: onOpenSettings),
      );
      if (goAnyway != true) return;
    }

    final startedAt = clock();
    final opened = await pass.start(length);
    final until = pass.until;
    if (opened && until != null) {
      await tracker.startPass(until);
      await stats.recordPass(startedAt, overQuota: overQuota);
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('找不到 Instagram app')));
    }
  }

  /// 結束 in the top bar: the pass is over, and you are back.
  Future<void> end() async {
    await pass.end();
    await tracker.endPass();
  }
}

class _PassLengthSheet extends StatelessWidget {
  const _PassLengthSheet({required this.today, required this.quota});

  final DayStats today;
  final int quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = today.passes;
    final over = used >= quota;
    final status = StringBuffer('今天已放行 $used 次 · 額度 $quota 次');
    if (today.overtime > Duration.zero) {
      status.write(' · 超時共 ${formatMinutes(today.overtime)}');
    }
    return SafeArea(
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
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('這段時間打開原生 IG 不會被導回來，時間到會通知你。'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              over ? '$status · 額度已用完' : status.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: over
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
    );
  }
}

/// Past the quota: type [overQuotaPhrase] to go anyway.
class _OverQuotaDialog extends StatefulWidget {
  const _OverQuotaDialog({required this.used, required this.quota});

  final int used;
  final int quota;

  @override
  State<_OverQuotaDialog> createState() => _OverQuotaDialogState();
}

class _OverQuotaDialogState extends State<_OverQuotaDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _matches => _text.text.trim() == overQuotaPhrase;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('今天的放行額度用完了（${widget.used}/${widget.quota}）'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('真的需要的話，請輸入：'),
          const SizedBox(height: 4),
          const SelectableText(
            '「$overQuotaPhrase」',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: overQuotaPhrase,
            ),
          ),
          const SizedBox(height: 8),
          Text('這次會記成「超額放行」。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('算了'),
        ),
        FilledButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: const Text('放行'),
        ),
      ],
    );
  }
}

class _NoRemindersDialog extends StatelessWidget {
  const _NoRemindersDialog({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
            onOpenSettings();
          },
          child: const Text('去設定'),
        ),
      ],
    );
  }
}
