import Foundation
import Observation

/// The owner's switches for what a running workout shows outside the app. Stored on this iPhone
/// only (UserDefaults); nothing here leaves the device.
@MainActor @Observable
final class WorkoutAlertSettings {
  private static let liveActivityKey = "ritm.workout.liveActivity"
  private static let hideWeightsKey = "ritm.workout.hideWeightsOnLockScreen"
  private static let restNotificationKey = "ritm.workout.restNotification"

  /// «Показывать тренировку на экране блокировки». Off until the owner turns it on.
  var showsLiveActivity: Bool { didSet { save(showsLiveActivity, Self.liveActivityKey) } }
  /// «Скрывать веса на экране блокировки». On by default: a lock screen is visible to others.
  var hidesWeights: Bool { didSet { save(hidesWeights, Self.hideWeightsKey) } }
  /// «Уведомление об окончании отдыха». Off until the owner turns it on (that asks permission).
  var notifiesRestEnd: Bool { didSet { save(notifiesRestEnd, Self.restNotificationKey) } }

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    showsLiveActivity = defaults.object(forKey: Self.liveActivityKey) as? Bool ?? false
    hidesWeights = defaults.object(forKey: Self.hideWeightsKey) as? Bool ?? true
    notifiesRestEnd = defaults.object(forKey: Self.restNotificationKey) as? Bool ?? false
  }

  private func save(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
}
