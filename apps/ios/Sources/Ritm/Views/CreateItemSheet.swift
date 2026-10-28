import SwiftUI

/// Compatibility entry point used by the app's create actions.
struct CreateItemSheet: View {
  enum Kind { case task, habit }
  @Environment(RitmStore.self) private var store
  let kind: Kind
  var body: some View {
    switch kind {
    case .task: NativeTaskEditor(initialDate: store.today)
    case .habit: HabitEditor()
    }
  }
}
