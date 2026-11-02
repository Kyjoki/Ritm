import SwiftUI
import WidgetKit

/// Entry point of the Ritm widget extension. It contains only the workout Live Activity.
@main
struct RitmWidgetBundle: WidgetBundle {
  var body: some Widget {
    RitmWorkoutLiveActivity()
  }
}
