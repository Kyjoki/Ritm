import Observation
import SwiftUI
import UIKit

/// One short status message at a time (prototype `toast()`): a new message replaces the current
/// one, and it hides itself after about 2.2 s. Editors call `store.toasts.show("…")`.
@MainActor @Observable
final class RitmToastCenter {
  struct Toast: Equatable, Identifiable {
    let id: Int
    let text: String
  }

  static let lifetime: Duration = .milliseconds(2200)

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

/// A compact Liquid Glass capsule above the bottom bar. It rises 8 pt while fading in over 0.2 s and
/// leaves with a 0.2 s fade; Reduce Motion: a plain fade.
struct RitmToastOverlay: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Clears the bottom bar (about 70 pt) plus a gap.
  private static let bottomClearance: CGFloat = 88
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
        capsule(toast.text)
          .id(toast.id)
          .transition(transition)
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, Self.bottomClearance)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .animation(
      reduceMotion ? RitmMotion.reducedFade : .easeOut(duration: Self.fade), value: toast)
    .allowsHitTesting(toast != nil)
  }

  private func capsule(_ text: String) -> some View {
    Button {
      store.toasts.dismiss()
    } label: {
      Text(text)
        .ritmFont(13, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        // A raised under-layer keeps the text readable over any content.
        .background(RitmTheme.glassRaised.opacity(0.5), in: Capsule())
        .ritmGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
    .accessibilityAddTraits(.isStaticText)
  }
}
