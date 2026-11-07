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
}

/// Used by the Shortcuts automation "When Instagram is opened":
/// if this returns false, the automation opens calm_ig instead.
struct IsInstagramPassActiveIntent: AppIntent {
  static let title: LocalizedStringResource = "放行中嗎？"
  static let description = IntentDescription(
    "清醒IG 是否正在暫時放行原生 Instagram。是 → 不用導回清醒IG。")

  func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
    return .result(value: InstagramPass.isActive())
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
