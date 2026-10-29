import RitmCore
import SwiftUI

/// «Настроить карты»: reorder the wallet's cards with the drag handle and pick each card's
/// colour. Both changes reach the wallet behind the sheet at once.
struct FinanceCardSettingsSheet: View {
  /// The wallet in its default order; the layout store applies the owner's order to it.
  let defaultCards: [FinanceCard]
  let layoutStore: FinanceCardLayoutStore
  let format: FinanceFormat
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let cards = layoutStore.ordered(defaultCards)
    let themes = layoutStore.themes(for: defaultCards)
    return ZStack {
      RitmBackground()
      VStack(spacing: 0) {
        header
        List {
          ForEach(cards) { card in
            row(card, cards: cards, theme: themes[card.id] ?? .violet)
          }
          .onMove { source, offset in
            layoutStore.move(fromOffsets: source, toOffset: offset, in: defaultCards)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .animation(reduceMotion ? nil : FinanceMotion.snap, value: cards.map(\.id))
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(22)
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(format.text("Настроить карты", "Customize cards"))
          .ritmFont(22, weight: .semibold, tracking: -0.04)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 12)
        Button(format.text("Готово", "Done")) { dismiss() }
          .buttonStyle(RitmTextButtonStyle(size: 14))
      }
      Text(
        format.text(
          "Перетащите за ручку, чтобы изменить порядок. Цвет меняется сразу.",
          "Drag the handle to reorder. The colour changes right away.")
      )
      .ritmFont(13)
      .foregroundStyle(RitmTheme.muted)
    }
    .padding(.horizontal, 20)
    .padding(.top, 28)
    .padding(.bottom, 10)
  }

  // MARK: Rows

  private func row(_ card: FinanceCard, cards: [FinanceCard], theme: FinanceCardTheme)
    -> some View
  {
    let index = cards.firstIndex(where: { $0.id == card.id }) ?? 0
    return VStack(alignment: .leading, spacing: 10) {
      preview(card, theme: theme)
      swatches(card, selected: theme)
    }
    .padding(14)
    .listRowBackground(
      RitmPanelBackground(radius: 20).padding(.vertical, 5).padding(.horizontal, 16)
    )
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    .accessibilityAction(named: format.text("Поднять выше", "Move up")) {
      layoutStore.move(from: index, to: index - 1, in: defaultCards)
    }
    .accessibilityAction(named: format.text("Опустить ниже", "Move down")) {
      layoutStore.move(from: index, to: index + 1, in: defaultCards)
    }
  }

  private func preview(_ card: FinanceCard, theme: FinanceCardTheme) -> some View {
    let style = FinanceCardStyle.style(theme: theme, kind: card.kind)
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    let ink = Color(rgb: 0xF8F3FF)
    return HStack(spacing: 12) {
      Image(systemName: style.symbol)
        .font(.system(size: 16, weight: .regular))
        .frame(width: 36, height: 36)
        .background(Circle().fill(Color.white.opacity(0.14)))
        .accessibilityHidden(true)
      Text(format.name(card))
        .ritmFont(14, weight: .medium)
        .lineLimit(1)
      Spacer(minLength: 8)
      Text(card.balanceMinor.map { format.money($0, card.currency) } ?? "—")
        .ritmFont(14, weight: .semibold)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 14)
    .frame(height: 60)
    .background {
      shape.fill(style.gradient)
        .overlay { shape.strokeBorder(Color(rgb: 0xDABCFC, opacity: 0.32), lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
          CornerGlow(color: style.glow.opacity(0.28), x: 0.94, y: 0, reach: 0.6).clipShape(shape)
        }
    }
    .accessibilityElement(children: .combine)
  }

  private func swatches(_ card: FinanceCard, selected: FinanceCardTheme) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 0)], alignment: .leading, spacing: 0) {
      ForEach(FinanceCardTheme.allCases, id: \.self) { theme in
        swatch(theme, card: card, isSelected: theme == selected)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(format.text("Цвет карты", "Card colour") + " " + format.name(card))
  }

  private func swatch(_ theme: FinanceCardTheme, card: FinanceCard, isSelected: Bool)
    -> some View
  {
    let style = FinanceCardStyle.style(theme: theme, kind: card.kind)
    return Button {
      layoutStore.setTheme(theme, for: card.id, in: defaultCards)
    } label: {
      Circle()
        .fill(style.gradient)
        .frame(width: 30, height: 30)
        .overlay {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .opacity(isSelected ? 1 : 0)
            .scaleEffect(isSelected ? 1 : 0.5)
        }
        .padding(3)
        .overlay {
          Circle().strokeBorder(RitmTheme.accentColor, lineWidth: 2).opacity(isSelected ? 1 : 0)
        }
        .animation(reduceMotion ? nil : RitmMotion.indicator, value: isSelected)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(name(of: theme))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func name(of theme: FinanceCardTheme) -> String {
    switch theme {
    case .violet: format.text("Фиолетовый", "Violet")
    case .indigo: format.text("Индиго", "Indigo")
    case .plum: format.text("Сливовый", "Plum")
    case .teal: format.text("Бирюзовый", "Teal")
    case .graphite: format.text("Графит", "Graphite")
    case .rose: format.text("Розовый", "Rose")
    case .sand: format.text("Песочный", "Sand")
    case .forest: format.text("Лесной", "Forest")
    }
  }
}
