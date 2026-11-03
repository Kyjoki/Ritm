import RitmCore
import SwiftUI

// Shared building blocks of the finance page: the `.panel` surface, its `.p-head`, the muted
// `.chart-note` lines, the period control with its date window and a few formatting helpers.

extension FinanceFormat {
  private static let monthsRu = [
    "янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек",
  ]

  /// «29 окт» as the prototype writes it (a no-break space, a three-letter month, no dot).
  func day(_ key: String, year: Bool = false) -> String {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard language == .ru, parts.count == 3, (1...12).contains(parts[1]) else {
      return date(key, template: year ? "d MMM yyyy" : "d MMM")
    }
    return "\(parts[2])\u{00A0}\(Self.monthsRu[parts[1] - 1])"
      + (year ? "\u{00A0}\(parts[0])" : "")
  }

  /// «1 окт – 3 ноя»; the year is added for the yearly window.
  func window(_ interval: (start: String, end: String), year: Bool) -> String {
    day(interval.start, year: year) + " – " + day(interval.end, year: year)
  }

  /// «за неделю».
  func periodLabel(_ period: FinancePeriod) -> String {
    switch period {
    case .week: text("за неделю", "for the week")
    case .month: text("за месяц", "for the month")
    case .year: text("за год", "for the year")
    }
  }

  /// «В тенге», «В долларах»: the heading of one currency group.
  func currencyIn(_ currency: FinanceCurrency) -> String {
    switch currency {
    case .KZT: text("В тенге", "In tenge")
    case .USD: text("В долларах", "In dollars")
    case .EUR: text("В евро", "In euro")
    case .RUB: text("В рублях", "In roubles")
    }
  }
}

func financeSymbol(_ currency: FinanceCurrency) -> String {
  switch currency {
  case .KZT: "₸"
  case .USD: "$"
  case .EUR: "€"
  case .RUB: "₽"
  }
}

/// Said only when the first data day really falls inside the period.
func financeShortWindow(
  asOf: String?, period: FinancePeriod, today: String, format: FinanceFormat
) -> String? {
  guard let asOf, asOf > FinanceWallet.interval(period, today: today).start else { return nil }
  let day = format.day(asOf, year: true)
  return format.text("Данные есть с \(day).", "Data starts on \(day).")
}

/// `.panel`: 16 pt padding, radius 23, the panel fill with its sheen, contour and soft shadow.
struct FinancePanel<Content: View>: View {
  private let content: Content
  private let reveal: Int?

  init(reveal: Int? = nil, @ViewBuilder content: () -> Content) {
    self.content = content()
    self.reveal = reveal
  }

  var body: some View {
    let panel = VStack(alignment: .leading, spacing: 0) { content }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background { RitmPanelBackground(radius: 23) }
    if let reveal {
      panel.ritmPageReveal(index: reveal)
    } else {
      panel
    }
  }
}

/// `.p-head`: a 15 pt title, an optional 11.5 pt muted line under it, an optional trailing view.
struct FinancePanelHead<Trailing: View>: View {
  let title: String
  var sub: String?
  private let trailing: Trailing

  init(title: String, sub: String? = nil, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.sub = sub
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .ritmFont(15, weight: .semibold, tracking: -0.03)
          .foregroundStyle(RitmTheme.text)
          .accessibilityAddTraits(.isHeader)
        if let sub { Text(sub).ritmFont(11.5).foregroundStyle(RitmTheme.muted) }
      }
      Spacer(minLength: 0)
      trailing
    }
    .padding(.bottom, 12)
  }
}

extension FinancePanelHead where Trailing == EmptyView {
  init(title: String, sub: String? = nil) {
    self.init(title: title, sub: sub) { EmptyView() }
  }
}

/// `.chart-note`: 11 pt muted lines, one per entry.
struct FinanceNotes: View {
  let lines: [String]
  var top: CGFloat = 8

  var body: some View {
    if !lines.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line)
            .ritmFont(11, lineSpacing: 2.5)
            .foregroundStyle(RitmTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, top)
    }
  }
}

/// `.empty`: a centred muted line inside a block.
struct FinanceEmptyText: View {
  let text: String

  var body: some View {
    Text(text)
      .ritmFont(12.5)
      .foregroundStyle(RitmTheme.muted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 8)
      .padding(.vertical, 18)
  }
}

/// The «Неделя / Месяц / Год» control and, 8 pt under it, the date window it covers.
struct FinancePeriodBar: View {
  let format: FinanceFormat
  let today: String
  @Binding var period: FinancePeriod

  var body: some View {
    let range = FinanceWallet.interval(period, today: today)
    VStack(alignment: .leading, spacing: 0) {
      RitmSegmentedControl(
        label: format.text("Период", "Period"), values: FinancePeriod.allCases,
        title: { format.periodTitle($0) }, selection: $period)
      Text(format.window(range, year: period == .year) + " · " + format.periodLabel(period))
        .ritmFont(11.5)
        .monospacedDigit()
        .foregroundStyle(RitmTheme.muted)
        .padding(.top, 8)
        .padding(.horizontal, 2)
    }
  }
}

/// A one-line section divider between rows of a panel (`border-top: 1px solid var(--line)`).
func financeDivider() -> some View {
  Rectangle().fill(RitmTheme.line).frame(height: 1)
}
