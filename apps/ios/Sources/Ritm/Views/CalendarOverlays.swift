import RitmCore
import SwiftUI

/// The page's two overlays, the mini-month under the title and the side menu. Their state lives
/// in `CalendarChrome`, which only this view and the top bar read: opening either redraws them
/// and nothing else, so the hour grid under them does no work. The scrim is a plain fading
/// colour, with no blur or material over the grid.
struct CalendarOverlays: View {
  let chrome: CalendarChrome
  let selected: String
  let today: String
  let onPickDay: (String) -> Void
  let onCloseMini: () -> Void
  let onCloseDrawer: () -> Void
  let closeLabel: String
  /// Builds the side menu with the room it is given above and below; called only while it is open.
  let makeDrawer: (_ top: CGFloat, _ bottom: CGFloat) -> CalendarDrawer
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dragX: CGFloat = 0

  var body: some View {
    ZStack {
      if chrome.miniOpen { miniMonth }
      if chrome.drawerOpen { drawerLayer }
    }
  }

  private var miniMonth: some View {
    ZStack(alignment: .topLeading) {
      Color.clear.contentShape(Rectangle()).onTapGesture(perform: onCloseMini)
      CalendarMiniMonth(selected: selected, today: today, onPick: onPickDay)
        .padding(.top, CalendarTopBar.height + 2)
        .padding(.horizontal, 12)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
    }
  }

  /// A full-height panel from the screen's top to its bottom edge, the tab bar floating over its
  /// lower part, and a dimming scrim that fades in with it. A tap on the scrim or a swipe to the
  /// left closes it.
  private var drawerLayer: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Button(action: onCloseDrawer) {
          RitmTheme.scrim.ignoresSafeArea().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(closeLabel)
        .opacity(max(0, 1 + dragX / CalendarDrawer.width))
        .transition(.opacity)
        makeDrawer(max(56, proxy.safeAreaInsets.top + 6), 24 + proxy.safeAreaInsets.bottom)
          .ignoresSafeArea(.container, edges: .vertical)
          .offset(x: dragX)
          .simultaneousGesture(closeSwipe)
          .transition(reduceMotion ? .opacity : .move(edge: .leading))
      }
    }
    .onAppear { dragX = 0 }
  }

  private var closeSwipe: some Gesture {
    DragGesture(minimumDistance: 14)
      .onChanged { value in
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        dragX = min(0, value.translation.width)
      }
      .onEnded { value in
        if value.translation.width < -70 || value.predictedEndTranslation.width < -180 {
          onCloseDrawer()
        } else {
          withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.25)) { dragX = 0 }
        }
      }
  }
}
