import RitmCore
import SwiftUI

/// What the full-history sheet leaves for the page behind it to do once the sheet has closed
/// (two sheets cannot swap in one turn).
enum FinanceHistoryFollowUp {
  case edit(FinanceEntry)
  case delete(FinanceEntry)
}

// MARK: - Dated list

/// Operations grouped by day: a narrow gutter on the left with the date, a faint rail with a
/// short tick at the first row of each day, and the operations as rounded capsule rows. At
/// accessibility text sizes the date stacks above its rows and the rail goes away.
struct FinanceDatedHistory: View {
  let entries: [FinanceEntry]
  let format: FinanceFormat
  let today: String
  let includeAccount: Bool
  /// Shifts the reveal stagger when the list sits below other revealed blocks.
  var revealOffset = 0
  let open: (FinanceEntry) -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .caption) private var gutterWidth: CGFloat = 46

  private static let railWidth: CGFloat = 18
  private static let rowHeight: CGFloat = 56
  private static let rowSpacing: CGFloat = 8
  private static let groupSpacing: CGFloat = 16
  private static let tickDot: CGFloat = 5

  var body: some View {
    let days = FinanceHistoryGrouping.group(entries, today: today, language: format.language)
    let stacked = typeSize.isAccessibilitySize
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
        Group {
          if stacked {
            stackedGroup(day, last: index == days.count - 1)
          } else {
            gutterGroup(day, first: index == 0, last: index == days.count - 1)
          }
        }
        .ritmPageReveal(index: index + revealOffset)
      }
    }
  }

  // MARK: Groups

  private func gutterGroup(_ day: FinanceHistoryDay, first: Bool, last: Bool) -> some View {
    HStack(alignment: .top, spacing: 0) {
      gutter(day)
        .frame(width: gutterWidth, alignment: .leading)
        .frame(minHeight: Self.rowHeight)
      rail(first: first, last: last)
      rows(day).padding(.bottom, last ? 0 : Self.groupSpacing)
    }
  }

  private func stackedGroup(_ day: FinanceHistoryDay, last: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(day.label)
        .ritmFont(15, weight: .semibold)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      rows(day)
    }
    .padding(.bottom, last ? 0 : Self.groupSpacing)
  }

  private func rows(_ day: FinanceHistoryDay) -> some View {
    VStack(spacing: Self.rowSpacing) {
      ForEach(day.entries) { entry in
        FinanceOperationRow(
          entry: entry, format: format, includeAccount: includeAccount, capsule: true,
          action: { open(entry) })
      }
    }
  }

  // MARK: Gutter

  /// Day number, then «Сегодня»/«Вчера» or the month, then the weekday (the month for the
  /// two relative days, which already say which day it is).
  @ViewBuilder private func gutter(_ day: FinanceHistoryDay) -> some View {
    if day.dayNumber.isEmpty {
      Text(day.label)
        .ritmFont(10, weight: .medium)
        .foregroundStyle(RitmTheme.muted)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text(day.dayNumber)
          .ritmFont(18, weight: .semibold, tracking: -0.03)
          .monospacedDigit()
          .foregroundStyle(RitmTheme.text)
        Text(day.relative ?? day.month)
          .ritmFont(10, weight: .medium)
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(day.relative == nil ? day.weekday : day.month + ", " + day.weekday)
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(day.label)
      .accessibilityAddTraits(.isHeader)
    }
  }

  // MARK: Rail

  /// A hairline that runs through every group, with a short tick at the first row's centre.
  /// The first group starts it at its tick and the last ends it there.
  private func rail(first: Bool, last: Bool) -> some View {
    let center = Self.rowHeight / 2
    let topInset = first ? center : 0
    return ZStack(alignment: .topLeading) {
      Group {
        if last {
          Rectangle().frame(height: center + 1 - topInset)
        } else {
          Rectangle().frame(maxHeight: .infinity)
        }
      }
      .frame(width: 1)
      .foregroundStyle(RitmTheme.line)
      .padding(.top, topInset)
      HStack(spacing: 0) {
        Circle().fill(RitmTheme.accentColor.opacity(0.7))
          .frame(width: Self.tickDot, height: Self.tickDot)
          .offset(x: -(Self.tickDot - 1) / 2)
        Rectangle().fill(RitmTheme.accentColor.opacity(0.35))
          .frame(width: Self.railWidth - Self.tickDot / 2, height: 1.5)
      }
      .padding(.top, center - Self.tickDot / 2)
    }
    .frame(width: Self.railWidth)
    .accessibilityHidden(true)
  }
}

// MARK: - Full history sheet

private struct FinanceHistoryRoute: Identifiable {
  let entryID: String
  var id: String { entryID }
}

/// «Вся история»: every income, expense and transfer grouped by day, filtered by type. Rows open
/// the usual details sheet on top; edit and delete are handed to the page once this sheet closes.
struct FinanceAllHistorySheet: View {
  let format: FinanceFormat
  let onFollowUp: (FinanceHistoryFollowUp) -> Void
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var filter: FinanceHistoryFilter = .all
  @State private var detail: FinanceHistoryRoute?
  @State private var pending: FinanceHistoryFollowUp?

  var body: some View {
    let operations = FinanceWallet.recent(store.financeEntries, limit: store.financeEntries.count)
    let shown = filter.apply(operations)
    return ZStack {
      RitmBackground()
      VStack(spacing: 0) {
        header
        filterBar.padding(.horizontal, 20).padding(.bottom, 12)
        ScrollView {
          list(shown, hasOperations: !operations.isEmpty)
            .id(filter)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
      }
    }
    .animation(reduceMotion ? nil : RitmMotion.ease(0.24), value: filter)
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(22)
    .sheet(item: $detail, onDismiss: finishDetail) { route in
      FinanceDetailSheet(
        entryID: route.entryID,
        onEdit: { pending = .edit($0) },
        onDelete: { pending = .delete($0) })
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(format.text("Вся история", "All history"))
        .ritmFont(22, weight: .semibold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 12)
      Button(format.text("Готово", "Done")) { dismiss() }
        .buttonStyle(RitmTextButtonStyle(size: 14))
    }
    .padding(.horizontal, 20)
    .padding(.top, 28)
    .padding(.bottom, 14)
  }

  @ViewBuilder private var filterBar: some View {
    if typeSize.isAccessibilitySize {
      ScrollView(.horizontal) { control(fillsWidth: false) }
        .scrollIndicators(.hidden)
    } else {
      control(fillsWidth: true)
    }
  }

  private func control(fillsWidth: Bool) -> some View {
    RitmSegmentedControl(
      label: format.text("Тип операций", "Operation type"), values: FinanceHistoryFilter.allCases,
      title: title, selection: $filter, fontSize: 12, fillsWidth: fillsWidth)
  }

  @ViewBuilder private func list(_ shown: [FinanceEntry], hasOperations: Bool) -> some View {
    if shown.isEmpty {
      RitmEmptyState(
        symbol: "tray",
        title: hasOperations
          ? format.text("Нет таких операций", "No matching operations")
          : format.text("Операций пока нет", "No operations yet"),
        message: hasOperations
          ? format.text("Выберите другой тип.", "Pick another type.")
          : format.text(
            "Поступления, расходы и переводы появятся здесь.",
            "Income, spending and transfers will appear here.")
      )
      .padding(.top, 40)
      .ritmPageReveal(index: 0)
    } else {
      FinanceDatedHistory(
        entries: shown, format: format, today: store.today, includeAccount: true,
        open: { detail = FinanceHistoryRoute(entryID: $0.id) })
    }
  }

  private func title(_ filter: FinanceHistoryFilter) -> String {
    switch filter {
    case .all: format.text("Все", "All")
    case .expense: format.text("Расходы", "Expenses")
    case .income: format.text("Поступления", "Income")
    case .transfer: format.text("Переводы", "Transfers")
    }
  }

  /// The details sheet has closed: a chosen edit or delete goes to the page, and this sheet
  /// closes so the editor or the confirmation can appear.
  private func finishDetail() {
    guard let next = pending else { return }
    pending = nil
    onFollowUp(next)
    dismiss()
  }
}
