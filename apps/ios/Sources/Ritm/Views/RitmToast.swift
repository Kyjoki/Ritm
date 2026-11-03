import Observation
import SwiftUI
import UIKit

/// One short status message at a time (prototype `toast()`): a new message replaces the current
/// one, and it hides itself after 3.2 s. Editors call `store.toasts.show("…")`.
@MainActor @Observable
final class RitmToastCenter {
  struct Toast: Equatable, Identifiable {
    let id: Int
    let text: String
  }

  static let lifetime: Duration = .milliseconds(3200)

  private(set) var current: Toast?
  @ObservationIgnored private var serial = 0
  @ObservationIgnored private var hideTask: Task<Void, Never>?

  func show(_ text: String) {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }
    serial += 1
    current = Toast(id: serial, text: message)
    UIAccessibility.post(notification: .announcement, argument: message)
    hideTask?.cancel()
    let mine = serial
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Self.lifetime)
      guard !Task.isCancelled, let self, self.serial == mine else { return }
      self.current = nil
    }
  }

  func dismiss() {
    hideTask?.cancel()
    current = nil
  }
}

/// `.toast`: a glass card above the bottom bar, 16 pt from the edges and 112 pt from the screen
/// bottom, radius 18: an info glyph, the message, and a 44 pt close button. It rises 8 pt while
/// fading in over 0.2 s and leaves with a fade; Reduce Motion: a plain fade.
struct RitmToastOverlay: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Distance of the toast's bottom edge from the screen bottom.
  private static let bottomClearance: CGFloat = 112
  private static let rise: CGFloat = 8
  private static let fade = 0.2

  private var transition: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .opacity.combined(with: .offset(y: Self.rise)), removal: .opacity)
  }

  var body: some View {
    let toast = store.toasts.current
    ZStack(alignment: .bottom) {
      if let toast {
        card(toast.text)
          .id(toast.id)
          .transition(transition)
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, Self.bottomClearance)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    // Measured from the screen edge, over the home indicator's area, like the bar.
    .ignoresSafeArea(.container, edges: .bottom)
    .animation(
      reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(Self.fade), value: toast)
    .allowsHitTesting(toast != nil)
  }

  private func card(_ text: String) -> some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
    return HStack(spacing: 10) {
      RitmIcon(.info)
        .font(.system(size: 20))
        .foregroundStyle(RitmTheme.accentColor)
        .accessibilityHidden(true)
      Text(text)
        .ritmFont(12.5, weight: .medium)
        .foregroundStyle(RitmTheme.text)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        store.toasts.dismiss()
      } label: {
        RitmIcon(.close)
          .font(.system(size: 20))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityLabel(store.text("Закрыть", "Close"))
    }
    .padding(.leading, 14)
    .padding(.trailing, 6)
    .padding(.vertical, 6)
    // A raised under-layer keeps the text readable over any content.
    .background(RitmTheme.glassDense.opacity(0.6), in: shape)
    .ritmFloatingGlass(in: shape)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(text)
  }
}
