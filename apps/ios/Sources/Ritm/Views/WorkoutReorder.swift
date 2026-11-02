import SwiftUI
import UIKit

// Reordering by a handle: hold the ⠿ grip, then drag. The card follows the finger, a dashed slot
// marks where it will land, the neighbours slide aside, and the list scrolls itself near the
// edges. Scrolling anywhere else stays native, and text fields and buttons never start a drag
// because only the handle listens. The order is saved on release; a cancelled drag restores it.

@MainActor @Observable
final class WorkoutReorderModel {
  struct Active: Equatable {
    let id: String
    let from: Int
    var to: Int
    /// How far the dragged card is from its place, in the list's own coordinates (finger plus scroll).
    var dy: CGFloat
    let height: CGFloat
    /// Where the dashed slot sits (top edge) in the list's coordinates.
    var slotY: CGFloat
  }

  private(set) var active: Active?
  @ObservationIgnored var frames: [String: CGRect] = [:]
  @ObservationIgnored private var ids: [String] = []
  @ObservationIgnored private var spacing: CGFloat = 0
  @ObservationIgnored private var commit: (Int, Int) -> Void = { _, _ in }
  @ObservationIgnored private var animation: Animation?
  @ObservationIgnored private weak var scrollView: UIScrollView?
  @ObservationIgnored private var scrollWasEnabled = true
  @ObservationIgnored private var startFingerY: CGFloat = 0
  @ObservationIgnored private var startOffset: CGFloat = 0
  @ObservationIgnored private var fingerY: CGFloat = 0
  @ObservationIgnored private var link: CADisplayLink?
  @ObservationIgnored private var linkProxy: WorkoutDisplayLinkProxy?
  @ObservationIgnored private var lastTick: CFTimeInterval = 0

  private static let edgeZone: CGFloat = 64
  private static let maxScrollSpeed: CGFloat = 900

  func offset(of id: String, at index: Int) -> CGFloat {
    guard let active else { return 0 }
    if id == active.id { return active.dy }
    let shift = active.height + spacing
    if active.from < active.to, index > active.from, index <= active.to { return -shift }
    if active.to < active.from, index >= active.to, index < active.from { return shift }
    return 0
  }

  func begin(
    id: String, ids: [String], spacing: CGFloat, animation: Animation?, fingerY: CGFloat,
    view: UIView, commit: @escaping (Int, Int) -> Void
  ) {
    guard active == nil, let from = ids.firstIndex(of: id), let frame = frames[id] else { return }
    self.ids = ids
    self.spacing = spacing
    self.commit = commit
    self.animation = animation
    startFingerY = fingerY
    self.fingerY = fingerY
    scrollView = Self.enclosingScrollView(of: view)
    startOffset = scrollView?.contentOffset.y ?? 0
    scrollWasEnabled = scrollView?.isScrollEnabled ?? true
    scrollView?.isScrollEnabled = false  // the finger belongs to the drag now
    active = Active(id: id, from: from, to: from, dy: 0, height: frame.height, slotY: frame.minY)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let proxy = WorkoutDisplayLinkProxy { [weak self] in self?.tick() }
    linkProxy = proxy
    lastTick = CACurrentMediaTime()
    let link = CADisplayLink(target: proxy, selector: #selector(WorkoutDisplayLinkProxy.fire))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  func move(fingerY: CGFloat) {
    guard active != nil else { return }
    self.fingerY = fingerY
    refresh()
  }

  func end(cancelled: Bool) {
    guard let current = active else { return }
    link?.invalidate()
    link = nil
    linkProxy = nil
    scrollView?.isScrollEnabled = scrollWasEnabled
    let commit = commit
    withAnimation(animation) {
      if !cancelled, current.to != current.from { commit(current.from, current.to) }
      active = nil
    }
    scrollView = nil
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func refresh() {
    guard let current = active, let frame = frames[current.id] else { return }
    let scrolled = (scrollView?.contentOffset.y ?? startOffset) - startOffset
    let dy = (fingerY - startFingerY) + scrolled
    let centre = frame.midY + dy
    let others = ids.enumerated().filter { $0.offset != current.from }
    let to = others.filter { (frames[$0.element]?.midY ?? 0) < centre }.count
    var y = ids.compactMap { frames[$0]?.minY }.min() ?? frame.minY
    var order = others.map(\.element)
    order.insert(current.id, at: min(to, order.count))
    for id in order {
      if id == current.id { break }
      y += (frames[id]?.height ?? 0) + spacing
    }
    var next = current
    next.dy = dy
    if next.to != to {
      next.to = to
      UISelectionFeedbackGenerator().selectionChanged()
    }
    next.slotY = y
    active = next
  }

  /// Scrolls the list while the finger is near the top or the bottom edge of the visible area.
  private func tick() {
    let now = CACurrentMediaTime()
    let dt = CGFloat(min(now - lastTick, 0.05))
    lastTick = now
    guard let scrollView, active != nil else { return }
    let inset = scrollView.adjustedContentInset
    let area = scrollView.convert(scrollView.bounds, to: nil)
    let top = area.minY + inset.top
    let bottom = area.maxY - inset.bottom
    var speed: CGFloat = 0
    if fingerY > bottom - Self.edgeZone {
      speed = min(1, (fingerY - (bottom - Self.edgeZone)) / Self.edgeZone)
    } else if fingerY < top + Self.edgeZone {
      speed = -min(1, (top + Self.edgeZone - fingerY) / Self.edgeZone)
    }
    if speed != 0 {
      let low = -inset.top
      let high = max(low, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
      let target = scrollView.contentOffset.y + speed * Self.maxScrollSpeed * dt
      scrollView.contentOffset.y = min(max(target, low), high)
    }
    refresh()
  }

  private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
    var current: UIView? = view.superview
    while let candidate = current {
      if let scroll = candidate as? UIScrollView { return scroll }
      current = candidate.superview
    }
    return nil
  }
}

@MainActor private final class WorkoutDisplayLinkProxy: NSObject {
  private let handler: @MainActor () -> Void

  init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }

  @objc func fire() { handler() }
}

// MARK: - Handle

/// The ⠿ grip. A long press of 0.18 s starts the drag; a quicker swipe scrolls the page.
struct WorkoutDragHandle: View {
  let began: @MainActor (CGFloat, UIView) -> Void
  let moved: @MainActor (CGFloat) -> Void
  let ended: @MainActor (Bool) -> Void

  var body: some View {
    Image(systemName: "circle.grid.2x3.fill")
      .font(.system(size: 18))
      .foregroundStyle(RitmTheme.muted)
      .frame(width: 44, height: 44)
      .overlay { WorkoutHandleGesture(began: began, moved: moved, ended: ended) }
      .accessibilityHidden(true)
  }
}

private struct WorkoutHandleGesture: UIViewRepresentable {
  let began: @MainActor (CGFloat, UIView) -> Void
  let moved: @MainActor (CGFloat) -> Void
  let ended: @MainActor (Bool) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    let press = UILongPressGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handle(_:)))
    press.minimumPressDuration = 0.18
    press.allowableMovement = 12
    view.addGestureRecognizer(press)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  @MainActor final class Coordinator: NSObject {
    var parent: WorkoutHandleGesture
    init(_ parent: WorkoutHandleGesture) { self.parent = parent }

    @objc func handle(_ gesture: UILongPressGestureRecognizer) {
      let y = gesture.location(in: nil).y
      switch gesture.state {
      case .began: if let view = gesture.view { parent.began(y, view) }
      case .changed: parent.moved(y)
      case .ended: parent.ended(false)
      case .cancelled, .failed: parent.ended(true)
      default: break
      }
    }
  }
}

// MARK: - List

private struct WorkoutFramesKey: PreferenceKey {
  static var defaultValue: [String: CGRect] { [:] }
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

/// A column of reorderable cards. `row` receives the item and the handle to place inside it.
struct WorkoutReorderList<Item: Identifiable, Row: View>: View where Item.ID == String {
  let items: [Item]
  var spacing: CGFloat = 10
  var cornerRadius: CGFloat = 22
  let onMove: (Int, Int) -> Void
  @ViewBuilder let row: (Item, WorkoutDragHandle) -> Row

  @State private var model = WorkoutReorderModel()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static var space: String { "workoutReorder" }

  private var slide: Animation? { reduceMotion ? nil : RitmMotion.easeOut(0.22) }

  var body: some View {
    let ids = items.map(\.id)
    VStack(spacing: spacing) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        let dragged = model.active?.id == item.id
        row(item, handle(for: item.id, ids: ids))
          .background {
            GeometryReader { proxy in
              Color.clear.preference(
                key: WorkoutFramesKey.self,
                value: [item.id: proxy.frame(in: .named(Self.space))])
            }
          }
          .scaleEffect(dragged && !reduceMotion ? 1.015 : 1)
          .shadow(color: .black.opacity(dragged ? 0.22 : 0), radius: dragged ? 16 : 0, y: dragged ? 8 : 0)
          .offset(y: model.offset(of: item.id, at: index))
          .animation(dragged ? nil : slide, value: model.offset(of: item.id, at: index))
          .zIndex(dragged ? 1 : 0)
      }
    }
    .coordinateSpace(name: Self.space)
    .onPreferenceChange(WorkoutFramesKey.self) { frames in
      if model.active == nil { model.frames = frames }
    }
    .background(alignment: .topLeading) { slot }
  }

  @ViewBuilder private var slot: some View {
    if let active = model.active {
      let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
      shape
        .fill(RitmTheme.accentColor.opacity(0.08))
        .overlay { shape.strokeBorder(RitmTheme.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 5])) }
        .frame(height: active.height)
        .offset(y: active.slotY)
        .animation(slide, value: active.slotY)
        .accessibilityHidden(true)
    }
  }

  private func handle(for id: String, ids: [String]) -> WorkoutDragHandle {
    WorkoutDragHandle(
      began: { fingerY, view in
        model.begin(
          id: id, ids: ids, spacing: spacing, animation: slide, fingerY: fingerY, view: view,
          commit: onMove)
      },
      moved: { model.move(fingerY: $0) },
      ended: { model.end(cancelled: $0) })
  }
}
