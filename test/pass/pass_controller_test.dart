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
  DateTime? scheduled;
  int cancels = 0;

  @override
  Future<void> scheduleEnd(DateTime at) async => scheduled = at;

  @override
  Future<void> cancelEnd() async {
    cancels++;
    scheduled = null;
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
    expect(notifier.scheduled, end);
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
    expect(notifier.cancels, 1);
  });

  test('no Instagram installed → pass is rolled back', () async {
    launcher.installed = false;
    expect(await pass.start(const Duration(minutes: 5)), isFalse);
    expect(pass.isActive, isFalse);
    expect(notifier.scheduled, isNull);
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
