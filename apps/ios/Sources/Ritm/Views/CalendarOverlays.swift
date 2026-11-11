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
  /// 0 = the menu is off the left edge, 1 = fully in. The panel and the scrim are driven by this one
  /// number, so the menu always slides in from the left (a `.transition` on children of a layer
  /// that is itself being inserted does not run, which left only a fade).
  @State private var progress: CGFloat = 0
  /// The layer stays in the tree while it slides out, then goes away (nothing is built when closed).
  @State private var rendered = false

  var body: some View {
    ZStack {
      if chrome.miniOpen { miniMonth }
      if rendered { drawerLayer }
    }
    .onChange(of: chrome.drawerOpen) { _, open in slide(open) }
  }

  private func slide(_ open: Bool) {
    if open {
      dragX = 0
      progress = 0
      rendered = true
      // One run-loop turn later, so the layer is first drawn off screen and then slides in.
      Task { @MainActor in
        withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.34)) { progress = 1 }
      }
    } else {
      // Carry on from where a swipe left the panel: fold the drag into `progress` first.
      let travel = CalendarDrawer.width + 24
      let travelled = (progress - 1) * travel + dragX
      progress = max(0, min(1, 1 + travelled / travel))
      dragX = 0
      withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.26)) {
        progress = 0
      } completion: {
        if !chrome.drawerOpen { rendered = false }
      }
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
        .opacity(progress * max(0, 1 + dragX / CalendarDrawer.width))
        makeDrawer(max(56, proxy.safeAreaInsets.top + 6), 24 + proxy.safeAreaInsets.bottom)
          .ignoresSafeArea(.container, edges: .vertical)
          .offset(x: reduceMotion ? dragX : (progress - 1) * (CalendarDrawer.width + 24) + dragX)
          .opacity(reduceMotion ? progress : 1)
          .simultaneousGesture(closeSwipe)
      }
    }
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
