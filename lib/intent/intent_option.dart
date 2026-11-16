import 'dart:convert';

/// What picking a "這次要做什麼？" option does.
enum IntentAction {
  /// Go to [IntentOption.path] on instagram.com.
  open,

  /// Start the "發限動" pass flow.
  pass,

  /// Stay where you are after a short pause (隨便看看).
  browse,
}

/// One answer in the "這次要做什麼？" menu. Users can add their own.
class IntentOption {
  const IntentOption({
    required this.id,
    required this.label,
    required this.action,
    this.path = '/',
  });

  final String id;
  final String label;
  final IntentAction action;

  /// Instagram path for [IntentAction.open], e.g. `/direct/inbox/`.
  final String path;

  IntentOption copyWith({String? label, IntentAction? action, String? path}) =>
      IntentOption(
        id: id,
        label: label ?? this.label,
        action: action ?? this.action,
        path: path ?? this.path,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'action': action.name,
    'path': path,
  };

  static IntentOption? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final label = json['label'];
    final action = IntentAction.values.asNameMap()[json['action']];
    if (id is! String || label is! String || action == null) return null;
    final path = json['path'];
    return IntentOption(
      id: id,
      label: label,
      action: action,
      path: path is String && isValidIgPath(path) ? path : '/',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IntentOption &&
      other.id == id &&
      other.label == label &&
      other.action == action &&
      other.path == path;

  @override
  int get hashCode => Object.hash(id, label, action, path);
}

const defaultIntentOptions = [
  IntentOption(
    id: 'dm',
    label: '回私訊',
    action: IntentAction.open,
    path: '/direct/inbox/',
  ),
  IntentOption(
    id: 'stories',
    label: '看限動',
    action: IntentAction.open,
    path: '/',
  ),
  IntentOption(id: 'post', label: '發限動', action: IntentAction.pass),
  IntentOption(id: 'browse', label: '隨便看看', action: IntentAction.browse),
];

/// Places a custom option can open (besides a specific account's profile).
const intentDestinations = <String, String>{
  '私訊': '/direct/inbox/',
  '限動（首頁）': '/',
  '追蹤中的貼文': '/?variant=following',
  '搜尋': '/explore/search/',
  '通知': '/notifications/',
};

/// Path of an account's profile page, or null if [username] isn't one.
String? profilePath(String username) {
  final name = username.trim().replaceFirst(RegExp(r'^@'), '');
  if (!RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(name)) return null;
  return '/$name/';
}

/// A same-site path we are willing to navigate to.
bool isValidIgPath(String path) =>
    path.startsWith('/') && !path.startsWith('//') && !path.contains('..');

String encodeIntentOptions(List<IntentOption> options) =>
    jsonEncode([for (final o in options) o.toJson()]);

/// Decodes saved options; falls back to the defaults if nothing usable.
List<IntentOption> decodeIntentOptions(String? raw) {
  if (raw == null) return defaultIntentOptions;
  try {
    final list = jsonDecode(raw);
    if (list is! List) return defaultIntentOptions;
    final options = list.map(IntentOption.fromJson).whereType<IntentOption>();
    return options.toList();
  } on FormatException {
    return defaultIntentOptions;
  }
}
