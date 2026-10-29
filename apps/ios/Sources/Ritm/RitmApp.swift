import SwiftUI

@main
struct RitmApp: App {
  @State private var store = RitmStore()
  @Environment(\.scenePhase) private var scenePhase

  init() { RitmFonts.register() }

  var body: some Scene {
    WindowGroup {
      RitmRootView()
        .environment(store)
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in
          store.setActive(phase == .active)
        }
        .privacySensitive()
        .overlay {
          if scenePhase != .active {
            ZStack {
              RitmBackground()
              Text("Ritm").font(.largeTitle.bold()).foregroundStyle(RitmTheme.lavender)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
          }
        }
    }
  }
}
