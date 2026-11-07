import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Step-by-step guide for the Shortcuts automation that sends the native
/// Instagram app back to calm_ig unless a pass is running.
class ShortcutSetupPage extends StatelessWidget {
  const ShortcutSetupPage({
    super.key,
    required this.onDone,
    this.openShortcuts = _openShortcutsApp,
  });

  final VoidCallback onDone;
  final Future<void> Function() openShortcuts;

  static Future<void> _openShortcutsApp() async {
    await launchUrl(Uri.parse('shortcuts://'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('設定捷徑自動化')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '打開原生 IG 時，自動跳到清醒IG',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '設定一次就好。之後點 IG 圖示或 IG 的通知，都會先被帶到清醒IG；'
            '想發限動時，按清醒IG 上方的「發限動」就能暫時用原生 IG。',
          ),
          const SizedBox(height: 16),
          for (final (i, step) in setupSteps.indexed)
            _StepCard(number: i + 1, step: step),
          const SizedBox(height: 4),
          Text(
            legacySetupNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: openShortcuts,
            icon: const Icon(Icons.open_in_new),
            label: const Text('打開捷徑 app'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onDone, child: const Text('我設定好了')),
        ],
      ),
    );
  }
}

class SetupStep {
  const SetupStep(this.title, this.detail);

  final String title;
  final String detail;
}

// Matches the iOS 27 Shortcuts app ("Unified Automations": triggers are
// added like actions). Checked on the iOS 27.2 simulator, English UI.
const setupSteps = [
  SetupStep('打開「捷徑」→ 下方「＋」→ 右上「編輯」', '跳過「描述捷徑」，直接手動編輯。'),
  SetupStep(
    '加入觸發條件「App」',
    '在下方搜尋列點「自動化」分類，往下找到「App」並加入。'
        '最上面會出現「當 App 已打開」，點「App」選 Instagram。',
  ),
  SetupStep('加入「放行中嗎？」', '在搜尋列輸入「IG」→ 點「清醒IG」→ 加入「放行中嗎？」。'),
  SetupStep('加入「如果」', '搜尋「如果」並加入，條件設成「放行中嗎？」「為」「否」。'),
  SetupStep('在「如果」裡加入「打開 App」', '把「打開 App」放進「如果」和「否則」中間，App 選「清醒IG」。完成！'),
];

/// Shown under the steps for older iOS versions.
const legacySetupNote =
    'iOS 26 以前：改從「捷徑」下方的「自動化」分頁按「＋」→「App」→ 選 Instagram、'
    '勾「已打開」、選「立即執行」→「新增空白自動化」，再做第 3–5 步。';

class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.step});

  final int number;
  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text('$number'),
        ),
        title: Text(step.title),
        subtitle: Text(step.detail),
      ),
    );
  }
}
