import RitmCore
import SwiftUI

/// The category tiles of the finance editor, shared with the Wallet inbox: a 4-column grid of
/// the main categories and a «Ещё» tile that opens the rest. `stored` is a category saved
/// elsewhere that is not in the lists; it stays selectable so editing a record does not lose it.
struct FinanceCategoryPicker: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let income: Bool
  @Binding var selection: String
  var stored: String?
  @State private var showAll: Bool

  init(income: Bool, selection: Binding<String>, stored: String? = nil) {
    self.income = income
    _selection = selection
    self.stored = stored
    // A selected category behind «Ещё» (or one kept from elsewhere) starts open, unanimated.
    _showAll = State(
      initialValue: FinanceCategories.needsMore(stored ?? selection.wrappedValue, income: income))
  }

  private var mainTiles: [FinanceCategory] {
    income ? FinanceCategories.incomeMain : FinanceCategories.expenseMain
  }

  private var moreTiles: [FinanceCategory] {
    let more = income ? FinanceCategories.incomeMore : FinanceCategories.expenseMore
    let kept = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !kept.isEmpty, !(mainTiles + more).contains(where: { $0.label == kept }) else {
      return more
    }
    return more + [
      FinanceCategory(label: kept, english: kept, symbol: FinanceCategories.symbol(for: kept))
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(store.text("Категория", "Category"))
        .ritmFont(12, weight: .semibold)
        .foregroundStyle(RitmTheme.muted)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8
      ) {
        ForEach(mainTiles, id: \.label) { tile($0) }
        FinanceCategoryMoreTile(
          expanded: showAll, reduceMotion: reduceMotion,
          title: store.text("Ещё", "More"), collapseTitle: store.text("Свернуть", "Collapse"),
          hint: showAll ? store.text("Развёрнуто", "Expanded") : store.text("Свёрнуто", "Collapsed"),
          action: toggle)
        if showAll {
          ForEach(Array(moreTiles.enumerated()), id: \.element.label) { index, item in
            tile(item).transition(extraTransition(index))
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func tile(_ item: FinanceCategory) -> FinanceCategoryTile {
    FinanceCategoryTile(
      symbol: item.symbol, title: store.text(item.label, item.english),
      selected: selection == item.label
    ) { selection = item.label }
  }

  private func toggle() {
    let opening = !showAll
    let animation: Animation =
      reduceMotion
      ? .easeInOut(duration: 0.2)
      : .timingCurve(0.2, 0.8, 0.2, 1, duration: opening ? 0.42 : 0.3)
    withAnimation(animation) { showAll = opening }
  }

  /// Extra tiles fade and scale in from 0.85 with a 35 ms stagger; Reduce Motion is a plain fade.
  private func extraTransition(_ index: Int) -> AnyTransition {
    if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.2)) }
    let curve = { (duration: Double) in Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: duration) }
    return .asymmetric(
      insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.85))
        .animation(curve(0.42).delay(0.035 * Double(index))),
      removal: AnyTransition.opacity.combined(with: .scale(scale: 0.85)).animation(curve(0.3)))
  }
}

private extension View {
  /// The shared 56 pt picker tile: a rounded outline, accent-tinted and heavier when selected.
  func categoryTileChrome(selected: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
    return self
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
      .frame(maxWidth: .infinity, minHeight: 56)
      .padding(.horizontal, 2)
      .background(selected ? RitmTheme.soft : Color.clear, in: shape)
      .overlay {
        shape.strokeBorder(
          selected ? RitmTheme.accentColor : RitmTheme.line, lineWidth: selected ? 1.5 : 1)
      }
      .contentShape(shape)
  }
}

private struct FinanceCategoryTile: View {
  let symbol: String
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 19, weight: .regular)).frame(height: 22)
        Text(title).ritmFont(10, weight: .medium).lineLimit(1).minimumScaleFactor(0.7)
      }
      .categoryTileChrome(selected: selected)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// «Ещё» / «Свернуть»: the chevron turns 180 degrees and the label crossfades.
private struct FinanceCategoryMoreTile: View {
  let expanded: Bool
  let reduceMotion: Bool
  let title: String
  let collapseTitle: String
  let hint: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: "chevron.down")
          .font(.system(size: 19, weight: .regular))
          .rotationEffect(.degrees(expanded && !reduceMotion ? 180 : 0))
          .opacity(reduceMotion && expanded ? 0.7 : 1)
          .frame(height: 22)
        ZStack {
          Text(title).opacity(expanded ? 0 : 1)
          Text(collapseTitle).opacity(expanded ? 1 : 0)
        }
        .ritmFont(10, weight: .medium).lineLimit(1).minimumScaleFactor(0.7)
      }
      .categoryTileChrome(selected: false)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(expanded ? collapseTitle : title)
    .accessibilityHint(hint)
  }
}
