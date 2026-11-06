import SwiftUI
import WidgetKit

/// One extension contains the workout Live Activity and the combined daily widget.
@main
struct RitmWidgetBundle: WidgetBundle {
  var body: some Widget {
    RitmDayHabitsWidget()
    RitmWorkoutLiveActivity()
  }
}
