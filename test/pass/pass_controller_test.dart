import 'package:calm_ig/pass/pass_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStore implements PassStore {
  int? value;
  final log = <String>[];

  @override
  int? readUntilMs() => value;

  @override
  Future<void> writeUntilMs(int? ms) async {
    log.add('write:$ms');
    value = ms;
  }
}

class FakeNotifier implements PassNotifier {
  bool allowed = true;
  List<PassReminder> scheduled = [];
  int cancels = 0;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> schedule(List<PassReminder> reminders) async =>
      scheduled = [...scheduled, ...reminders];

  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled = [];
  }
}

class FakeLauncher implements InstagramLauncher {
  FakeLauncher(this.store, {this.installed = true});

  final FakeStore store;
  bool installed;
  int? storeValueWhenOpened;

  @override
  Future<bool> openInstagram() async {
    storeValueWhenOpened = store.value;
    return installed;
  }
}

void main() {
  late DateTime now;
  late FakeStore store;
  late FakeNotifier notifier;
  late FakeLauncher launcher;
  late PassController pass;

  setUp(() {
    now = DateTime(2026, 11, 7, 12);
    store = FakeStore();
    notifier = FakeNotifier();
    launcher = FakeLauncher(store);
    pass = PassController(
      store: store,
      notifier: notifier,
      launcher: launcher,
      clock: () => now,
    );
  });

  test('no pass by default', () {
    expect(pass.isActive, isFalse);
    expect(pass.remaining, Duration.zero);
  });

  test('start saves the end time before opening Instagram', () async {
    expect(await pass.start(const Duration(minutes: 5)), isTrue);
    final end = now.add(const Duration(minutes: 5));
    expect(launcher.storeValueWhenOpened, end.millisecondsSinceEpoch);
    expect(notifier.scheduled.first.at, end);
    expect(pass.isActive, isTrue);
    expect(pass.remaining, const Duration(minutes: 5));
  });

  test('pass expires on its own', () async {
    await pass.start(const Duration(minutes: 5));
    now = now.add(const Duration(minutes: 4, seconds: 30));
    expect(pass.isActive, isTrue);
    expect(pass.remaining, const Duration(seconds: 30));
    now = now.add(const Duration(seconds: 30));
    expect(pass.isActive, isFalse);
  });

  test('end clears the pass and the reminder', () async {
    await pass.start(const Duration(minutes: 10));
    await pass.end();
    expect(pass.isActive, isFalse);
    expect(store.value, isNull);
    expect(notifier.scheduled, isEmpty);
  });

  test('no Instagram installed → pass is rolled back', () async {
    launcher.installed = false;
    expect(await pass.start(const Duration(minutes: 5)), isFalse);
    expect(pass.isActive, isFalse);
    expect(notifier.scheduled, isEmpty);
  });

  test('a pass schedules 5 reminders, one per minute from the end', () async {
    await pass.start(const Duration(minutes: 5));
    final end = now.add(const Duration(minutes: 5));
    expect(notifier.scheduled.map((r) => r.at), [
      for (var i = 0; i < 5; i++) end.add(Duration(minutes: i)),
    ]);
    expect(notifier.scheduled.first.title, '放行時間到了');
    expect(notifier.scheduled[1].body, contains('超過 1 分鐘'));
    expect(notifier.scheduled[4].body, contains('超過 4 分鐘'));
  });

  test('starting a new pass replaces the old reminders', () async {
    await pass.start(const Duration(minutes: 5));
    await pass.start(const Duration(minutes: 10));
    expect(notifier.scheduled, hasLength(reminderCount));
    expect(notifier.scheduled.first.at, now.add(const Duration(minutes: 10)));
  });

  test('coming back after the pass ended stops the reminders', () async {
    await pass.start(const Duration(minutes: 5));
    now = now.add(const Duration(minutes: 6));
    await pass.onResumed();
    expect(notifier.scheduled, isEmpty);
    expect(store.value, isNull);
  });

  test('coming back while the pass still runs keeps it', () async {
    await pass.start(const Duration(minutes: 5));
    now = now.add(const Duration(minutes: 2));
    await pass.onResumed();
    expect(pass.isActive, isTrue);
    expect(notifier.scheduled, hasLength(reminderCount));
  });

  test('onResumed with no pass does nothing', () async {
    await pass.onResumed();
    expect(notifier.cancels, 0);
  });

  test('canRemind reflects notification permission', () async {
    expect(await pass.canRemind(), isTrue);
    notifier.allowed = false;
    expect(await pass.canRemind(), isFalse);
  });

  test('listeners hear about start and end', () async {
    var calls = 0;
    pass.addListener(() => calls++);
    await pass.start(const Duration(minutes: 5));
    await pass.end();
    expect(calls, greaterThanOrEqualTo(2));
  });

  test('formatRemaining', () {
    expect(formatRemaining(const Duration(minutes: 4, seconds: 7)), '4:07');
    expect(formatRemaining(const Duration(seconds: 59)), '0:59');
    expect(formatRemaining(const Duration(minutes: 10)), '10:00');
    expect(formatRemaining(const Duration(seconds: -3)), '0:00');
  });
}
