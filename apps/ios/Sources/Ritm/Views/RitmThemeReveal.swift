import QuartzCore
import SwiftUI
import UIKit

/// Theme switch as in the reference video: a snapshot of the window keeps the OLD theme on
/// screen, the theme changes underneath, and a circle centred on the toggle grows until it has
/// cut the whole snapshot away (MOTION.md §1). Reduce Motion: a plain 120 ms crossfade.
@MainActor
enum RitmThemeReveal {
  static let duration: CFTimeInterval = 0.52
  static let reducedDuration: TimeInterval = 0.12
  /// Time for SwiftUI to render the new theme beneath the snapshot before the circle starts.
  private static let settle: Duration = .milliseconds(50)

  private static var overlay: UIView?
  private static var token = 0

  /// `origin` is the toggle's centre in window coordinates. `switchTheme` runs once the snapshot
  /// covers the window. A new call first removes any overlay left by the previous one.
  static func run(origin: CGPoint, reduceMotion: Bool, switchTheme: () -> Void) {
    finishCurrent()
    guard let window = keyWindow(),
      let snapshot = window.snapshotView(afterScreenUpdates: false)
    else {
      switchTheme()
      return
    }
    snapshot.frame = window.bounds
    snapshot.isUserInteractionEnabled = false
    snapshot.accessibilityElementsHidden = true
    window.addSubview(snapshot)
    overlay = snapshot
    token += 1
    let mine = token
    switchTheme()
    Task { @MainActor in
      try? await Task.sleep(for: settle)
      guard mine == token, overlay === snapshot else { return }
      if reduceMotion {
        fade(snapshot, token: mine)
      } else {
        reveal(snapshot, origin: origin, token: mine)
      }
      // Safety net: whatever happens to the animation, the overlay never outlives it by much.
      try? await Task.sleep(for: .seconds(duration + 0.3))
      finish(token: mine)
    }
  }

  // MARK: Overlay lifecycle

  private static func finishCurrent() {
    overlay?.layer.mask?.removeAllAnimations()
    overlay?.layer.removeAllAnimations()
    overlay?.removeFromSuperview()
    overlay = nil
    token += 1
  }

  private static func finish(token finished: Int) {
    guard finished == token else { return }
    overlay?.layer.mask = nil
    overlay?.removeFromSuperview()
    overlay = nil
  }

  private static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
  }

  // MARK: Animations

  private static func fade(_ snapshot: UIView, token mine: Int) {
    UIView.animate(
      withDuration: reducedDuration, delay: 0, options: [.curveEaseOut],
      animations: { snapshot.alpha = 0 },
      completion: { _ in
        MainActor.assumeIsolated { finish(token: mine) }
      })
  }

  private static func reveal(_ snapshot: UIView, origin: CGPoint, token mine: Int) {
    let bounds = snapshot.bounds
    let farthest = [
      CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
      CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
    ].map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? max(bounds.width, bounds.height)
    let radius = farthest + 2

    // Even-odd: the outer rectangle keeps the old theme, the circle is a hole onto the new one.
    func path(_ r: CGFloat) -> CGPath {
      let path = UIBezierPath(rect: bounds.insetBy(dx: -2, dy: -2))
      path.append(
        UIBezierPath(
          arcCenter: origin, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true))
      return path.cgPath
    }

    let mask = CAShapeLayer()
    mask.frame = bounds
    mask.fillRule = .evenOdd
    mask.fillColor = UIColor.black.cgColor
    snapshot.layer.mask = mask

    let grow = CABasicAnimation(keyPath: "path")
    grow.fromValue = path(0.01)
    grow.toValue = path(radius)
    grow.duration = duration
    grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
    grow.fillMode = .forwards
    grow.isRemovedOnCompletion = false

    CATransaction.begin()
    CATransaction.setCompletionBlock {
      MainActor.assumeIsolated { finish(token: mine) }
    }
    CATransaction.setDisableActions(true)
    mask.path = path(radius)
    mask.add(grow, forKey: "reveal")
    CATransaction.commit()
  }
}
