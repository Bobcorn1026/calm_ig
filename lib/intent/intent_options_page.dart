import 'dart:async';

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'intent_option.dart';
import 'intent_prompt.dart' show intentOptionIcon;

/// Edit the "這次要做什麼？" options: add, rename, change where they go,
/// reorder, delete.
class IntentOptionsPage extends StatefulWidget {
  const IntentOptionsPage({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<IntentOptionsPage> createState() => _IntentOptionsPageState();
}

/// Longest option name, so it fits on one line in the menu.
const maxIntentLabelLength = 12;

/// What an option does, in words: `打開私訊`, `打開 @abc 的個人頁`, ...
String describeIntentOption(IntentOption option) => switch (option.action) {
  IntentAction.open => _describeOpen(option.path),
  IntentAction.pass => '開始發限動（放行原生 IG）',
  IntentAction.browse => '等 5 秒再看',
};

String _describeOpen(String path) {
  for (final e in intentDestinations.entries) {
    if (e.value == path) return '打開${e.key}';
  }
  final user = _profileUser(path);
  if (user != null) return '打開 @$user 的個人頁';
  return '打開 instagram.com$path';
}

/// `abc` for `/abc/`, or null if [path] isn't a profile page.
String? _profileUser(String path) =>
    RegExp(r'^/([A-Za-z0-9._]{1,30})/$').firstMatch(path)?.group(1);

class _IntentOptionsPageState extends State<IntentOptionsPage> {
  late List<IntentOption> _options = widget.settings.intentOptions;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_sync);
  }

  @override
  void didUpdateWidget(IntentOptionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_sync);
      widget.settings.addListener(_sync);
      _options = widget.settings.intentOptions;
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_sync);
    super.dispose();
  }

  void _sync() => setState(() => _options = widget.settings.intentOptions);

  /// Shows [options] right away (the list mustn't jump back after a drag),
  /// then saves.
  Future<void> _save(List<IntentOption> options) {
    setState(() => _options = options);
    return widget.settings.setIntentOptions(options);
  }

  void _reorder(int from, int to) {
    final list = [..._options];
    list.insert(to, list.removeAt(from));
    unawaited(_save(list));
  }

  Future<void> _edit(IntentOption? option) async {
    final result = await showModalBottomSheet<IntentOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _OptionEditor(option: option, others: _options),
    );
    if (result == null || !mounted) return;
    final list = [..._options];
    final index = list.indexWhere((o) => o.id == result.id);
    if (index >= 0) {
      list[index] = result;
    } else {
      list.add(result);
    }
    await _save(list);
  }

  void _delete(IntentOption option) {
    final index = _options.indexWhere((o) => o.id == option.id);
    if (index < 0) return;
    unawaited(_save([..._options]..removeAt(index)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已刪除「${option.label}」'),
          persist: false,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '復原',
            onPressed: () => _undoDelete(option, index),
          ),
        ),
      );
  }

  void _undoDelete(IntentOption option, int index) {
    final current = widget.settings.intentOptions;
    if (current.any((o) => o.id == option.id)) return;
    final list = [...current]..insert(index.clamp(0, current.length), option);
    // The page may be gone already; the settings still get it back.
    unawaited(mounted ? _save(list) : widget.settings.setIntentOptions(list));
  }

  Future<void> _restoreDefaults() async {
    final names = defaultIntentOptions.map((o) => o.label).join('、');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢復預設選項？'),
        content: Text('會換回「$names」，你自己加的選項會被刪掉。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢復'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _save(defaultIntentOptions);
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return Scaffold(
      appBar: AppBar(
        title: const Text('開場選項'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) => _restoreDefaults(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'restore', child: Text('恢復預設')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('新增選項'),
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        // Room for the button, so it never covers the last row.
        padding: const EdgeInsets.only(bottom: 96),
        header: _Header(empty: options.isEmpty, canReorder: options.length > 1),
        itemCount: options.length,
        onReorderItem: _reorder,
        itemBuilder: (context, index) {
          final option = options[index];
          return ListTile(
            key: ValueKey(option.id),
            contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
            leading: Icon(intentOptionIcon(option)),
            title: Text(option.label),
            subtitle: Text(describeIntentOption(option)),
            onTap: () => _edit(option),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '刪除「${option.label}」',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(option),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle, semanticLabel: '拖曳排序'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.empty, required this.canReorder});

  final bool empty;
  final bool canReorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('打開清醒IG（或離開超過 5 分鐘再回來）時，會先問你這次要做什麼。', style: muted),
          if (canReorder) ...[
            const SizedBox(height: 4),
            Text('按住右邊的 ≡ 拖曳，可以調整順序。', style: muted),
          ],
          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.do_not_disturb_on_outlined,
                    size: 40,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '沒有選項時，打開清醒IG 就不會問。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Add (when [option] is null) or change one option. Pops the result.
class _OptionEditor extends StatefulWidget {
  const _OptionEditor({required this.option, required this.others});

  final IntentOption? option;

  /// The saved options, for unique names and ids.
  final List<IntentOption> others;

  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

/// Chip value for "某個帳號的個人頁" (not one of [intentDestinations]).
const _profile = '@profile';

class _OptionEditorState extends State<_OptionEditor> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.option?.label);
  final _username = TextEditingController();
  late IntentAction _action = widget.option?.action ?? IntentAction.open;

  /// A key of [intentDestinations], or [_profile].
  late String _destination = intentDestinations.keys.first;

  @override
  void initState() {
    super.initState();
    final option = widget.option;
    if (option != null && option.action == IntentAction.open) {
      final known = intentDestinations.entries
          .where((e) => e.value == option.path)
          .map((e) => e.key)
          .firstOrNull;
      if (known != null) {
        _destination = known;
      } else {
        _destination = _profile;
        _username.text =
            _profileUser(option.path) ?? option.path.replaceAll('/', '');
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _username.dispose();
    super.dispose();
  }

  String? _validateLabel(String? value) {
    final label = value?.trim() ?? '';
    if (label.isEmpty) return '請輸入名稱';
    if (label.characters.length > maxIntentLabelLength) {
      return '最多 $maxIntentLabelLength 個字';
    }
    final taken = widget.others.any(
      (o) => o.id != widget.option?.id && o.label == label,
    );
    if (taken) return '已經有叫「$label」的選項了';
    return null;
  }

  String? _validateUsername(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty || name == '@') return '請輸入帳號';
    if (profilePath(name) == null) return '帳號只能有英文字母、數字、. 和 _';
    return null;
  }

  String _newId() {
    final taken = {for (final o in widget.others) o.id};
    var micros = DateTime.now().microsecondsSinceEpoch;
    while (taken.contains('custom-$micros')) {
      micros++;
    }
    return 'custom-$micros';
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final label = _label.text.trim();
    final path = switch (_action) {
      IntentAction.open =>
        _destination == _profile
            ? profilePath(_username.text)!
            : intentDestinations[_destination]!,
      IntentAction.pass || IntentAction.browse => '/',
    };
    final option = widget.option;
    Navigator.pop(
      context,
      option == null
          ? IntentOption(
              id: _newId(),
              label: label,
              action: _action,
              path: path,
            )
          : option.copyWith(label: label, action: _action, path: path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.option == null ? '新增選項' : '編輯選項',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _label,
              autofocus: widget.option == null,
              maxLength: maxIntentLabelLength,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '名稱',
                hintText: '例如：看朋友的限動',
                border: OutlineInputBorder(),
              ),
              validator: _validateLabel,
            ),
            const SizedBox(height: 8),
            Text('動作', style: heading),
            const SizedBox(height: 8),
            SegmentedButton<IntentAction>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: IntentAction.open, label: Text('打開頁面')),
                ButtonSegment(value: IntentAction.pass, label: Text('發限動')),
                ButtonSegment(value: IntentAction.browse, label: Text('隨便看看')),
              ],
              selected: {_action},
              onSelectionChanged: (selected) =>
                  setState(() => _action = selected.first),
            ),
            const SizedBox(height: 16),
            switch (_action) {
              IntentAction.open => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('打開哪裡', style: heading),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in [...intentDestinations.keys, _profile])
                        ChoiceChip(
                          label: Text(name == _profile ? '某個帳號的個人頁' : name),
                          selected: _destination == name,
                          onSelected: (_) =>
                              setState(() => _destination = name),
                        ),
                    ],
                  ),
                  if (_destination == _profile) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _username,
                      autofocus: widget.option == null,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '帳號',
                        prefixText: '@',
                        hintText: 'username',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateUsername,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                ],
              ),
              IntentAction.pass => Text(
                '選了會直接開始「發限動」：選放行幾分鐘，再打開原生 IG。',
                style: hint,
              ),
              IntentAction.browse => Text(
                '會先停 5 秒讓你深呼吸，再回到 IG 網頁。',
                style: hint,
              ),
            },
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('儲存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
