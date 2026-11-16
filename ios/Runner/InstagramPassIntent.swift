import AppIntents
import Foundation

/// Reads the pass end time that the Flutter side saves with
/// shared_preferences (key `pass_until_ms`, stored as `flutter.pass_until_ms`).
enum InstagramPass {
  static let defaultsKey = "flutter.pass_until_ms"

  static func isActive(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
    guard let value = defaults.object(forKey: defaultsKey) as? NSNumber else {
      return false
    }
    return value.doubleValue / 1000 > now.timeIntervalSince1970
  }

  /// `2026-11-16` in the local time zone — the same key format as Dart's
  /// `dayKey()` (lib/stats/day_key.dart).
  static func dayKey(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  /// Counts one more "native Instagram opened and sent back" for today.
  /// Read in Dart as shared_preferences key `bounces_<day>`.
  static func recordBounce(now: Date = Date(), defaults: UserDefaults = .standard) {
    let key = "flutter.bounces_\(dayKey(now))"
    defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
  }
}

/// Used by the Shortcuts automation "When Instagram is opened":
/// if this returns false, the automation opens calm_ig instead.
struct IsInstagramPassActiveIntent: AppIntent {
  static let title: LocalizedStringResource = "放行中嗎？"
  static let description = IntentDescription(
    "清醒IG 是否正在暫時放行原生 Instagram。是 → 不用導回清醒IG。")

  func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    let active = InstagramPass.isActive()
    // No pass: the automation is about to send you back to calm_ig.
    if !active { InstagramPass.recordBounce() }
    return .result(value: active)
  }
}

struct CalmIgShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: IsInstagramPassActiveIntent(),
      phrases: ["\(.applicationName) 放行中嗎"],
      shortTitle: "放行中嗎？",
      systemImageName: "hourglass"
    )
  }
}
