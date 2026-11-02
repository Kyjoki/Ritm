#if canImport(ActivityKit)
import ActivityKit
import Foundation
import RitmCore

/// The Live Activity of an active workout. THIS FILE IS SHARED: the app compiles it, and the
/// widget extension in `apps/ios/LiveActivity/` must compile the very same file (see
/// LIVE_ACTIVITY.md: symlink it into the extension target). The dynamic part is RitmCore's
/// `LiveActivityContent`, so the app and the card can never disagree about its shape.
struct RitmWorkoutAttributes: ActivityAttributes {
  typealias ContentState = LiveActivityContent

  let workoutID: String
  let startedAt: Date
}
#endif
