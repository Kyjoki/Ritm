import Foundation
import RitmCore
import SwiftUI

/// Finance colours that are not web tokens (the finance palette from the design context).
enum FinanceTone {
  static var income: Color { Color(light: 0x348B71, dark: 0x6FCBA6) }
  static var expense: Color { Color(light: 0xB3627E, dark: 0xE59AB3) }
  static var incomeSoft: Color {
    Color(light: 0x74BD9E, dark: 0x74BD9E, lightOpacity: 0.15, darkOpacity: 0.16)
  }
  static var expenseSoft: Color {
    Color(light: 0xD991A5, dark: 0xD991A5, lightOpacity: 0.16, darkOpacity: 0.16)
  }
  private static let lightChart: [UInt32] = [0x9C77DB, 0xD798BC, 0x77A6D4, 0x79B8A7, 0xD7AD76, 0xB79CB6]
  private static let darkChart: [UInt32] = [0xB596EA, 0xE6AFCB, 0x94BEE6, 0x94CDBD, 0xE6C490, 0xC9B2C8]

  static func chart(_ index: Int) -> Color {
    let count = lightChart.count
    let slot = ((index % count) + count) % count
    return Color(light: lightChart[slot], dark: darkChart[slot])
  }

  /// Green for money in, rose for money out, plain text for zero.
  static func net(_ minor: Int) -> Color {
    minor > 0 ? income : minor < 0 ? expense : RitmTheme.text
  }
}

/// Kept for the page that owns it. The charts now key their draw-in through `RitmDrawGate`
/// (once per page visit and data set), so nothing reads this log any more.
final class FinanceDrawLog {
  var keys = Set<String>()
}

// MARK: - Balance area chart

/// Scale of one balance series: «nice» axis ticks and normalised point positions.
private struct FinanceScale {
  let ticks: [Int]
  let xs: [CGFloat]
  let ys: [CGFloat]

  init?(points: [FinancePoint]) {
    guard points.count >= 2 else { return nil }
    let values = points.map(\.valueMinor)
    var low = Double(values.min() ?? 0)
    var high = Double(values.max() ?? 0)
    if high - low < 1 {
      let pad = max(abs(high) * 0.1, 10_000)
      // A zero or positive series never shows a negative axis: pad upward from 0.
      low = low >= 0 ? max(0, low - pad) : low - pad
      high += pad
    }
    let step = Self.niceStep((high - low) / 3)
    let first = (low / step).rounded(.down) * step
    let last = (high / step).rounded(.up) * step
    var ticks: [Int] = []
    var tick = first
    while tick <= last + step * 0.001 && ticks.count < 8 {
      ticks.append(Int(tick.rounded()))
      tick += step
    }
    let span = max(1, last - first)
    self.ticks = ticks
    self.ys = values.map { CGFloat((Double($0) - first) / span) }
    let days = points.map { Self.dayNumber($0.date) }
    if let start = days.first ?? nil, let end = days.last ?? nil, end > start,
      days.allSatisfy({ $0 != nil })
    {
      self.xs = days.map { CGFloat((($0 ?? start) - start) / (end - start)) }
    } else {
      let count = CGFloat(points.count - 1)
      self.xs = points.indices.map { CGFloat($0) / count }
    }
  }

  func unit(_ value: Int) -> CGFloat {
    guard let first = ticks.first, let last = ticks.last, last > first else { return 0.5 }
    return CGFloat(Double(value - first) / Double(last - first))
  }

  static func niceStep(_ raw: Double) -> Double {
    guard raw > 0 else { return 1 }
    let magnitude = pow(10, log10(raw).rounded(.down))
    let fraction = raw / magnitude
    let nice: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
    return nice * magnitude
  }

  /// Days since 1970-01-01 for a `YYYY-MM-DD` key.
  static func dayNumber(_ key: String) -> Double? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let month = parts[1]
    let day = parts[2]
    let year = parts[0] - (month <= 2 ? 1 : 0)
    let era = (year >= 0 ? year : year - 399) / 400
    let yearOfEra = year - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return Double(era * 146_097 + dayOfEra - 719_468)
  }

  /// `700K`, `1.2M`: axis labels for amounts in minor units.
  static func compact(_ minor: Int) -> String {
    let value = Double(abs(minor)) / 100
    let sign = minor < 0 ? "−" : ""
    func trimmed(_ number: Double, _ suffix: String) -> String {
      let text =
        number >= 100 || number == number.rounded()
        ? String(Int(number.rounded())) : String(format: "%.1f", number)
      return sign + text + suffix
    }
    if value >= 1_000_000 { return trimmed(value / 1_000_000, "M") }
    if value >= 1_000 { return trimmed(value / 1_000, "K") }
    return sign + String(Int(value.rounded()))
  }
}

private struct FinanceLineShape: Shape {
  let xs: [CGFloat]
  let ys: [CGFloat]
  let closed: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard xs.count == ys.count, xs.count > 1 else { return path }
    let points = zip(xs, ys).map { CGPoint(x: $0 * rect.width, y: (1 - $1) * rect.height) }
    if closed {
      path.move(to: CGPoint(x: points[0].x, y: rect.height))
      path.addLine(to: points[0])
    } else {
      path.move(to: points[0])
    }
    for index in 1..<points.count {
      let from = points[index - 1]
      let to = points[index]
      let middle = (from.x + to.x) / 2
      path.addCurve(
        to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
    }
    if closed {
      path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.height))
      path.closeSubpath()
    }
    return path
  }
}

private struct FinanceGridShape: Shape {
  let rows: [CGFloat]
  let columns: [CGFloat]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for row in rows {
      path.move(to: CGPoint(x: 0, y: (1 - row) * rect.height))
      path.addLine(to: CGPoint(x: rect.width, y: (1 - row) * rect.height))
    }
    for column in columns {
      path.move(to: CGPoint(x: column * rect.width, y: 0))
      path.addLine(to: CGPoint(x: column * rect.width, y: rect.height))
    }
    return path
  }
}

/// Hand-drawn balance chart in the style of `DayRhythmChart`: dashed grid, smooth line, soft
/// fill and a value badge. The line draws in once per `drawKey` (MOTION.md §4): the stroke in
/// 780 ms, the area fading in once the line passes 40 %, the end points popping at the end.
struct FinanceAreaChart: View {
  let points: [FinancePoint]
  let period: FinancePeriod
  let currency: FinanceCurrency
  let format: FinanceFormat
  let drawKey: String
  let log: FinanceDrawLog
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let left: CGFloat = 44
  private static let right: CGFloat = 8
  private static let top: CGFloat = 12
  private static let bottom: CGFloat = 26

  var body: some View {
    if let scale = FinanceScale(points: points) {
      RitmDrawGate(key: drawKey) { drawn in chart(scale, drawn: drawn) }
        .frame(height: 196)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(scale))
    } else {
      Text(format.text("Пока недостаточно данных для графика.", "Not enough data for a chart yet."))
        .ritmFont(11)
        .foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
  }

  private func summary(_ scale: FinanceScale) -> String {
    let values = points.map(\.valueMinor)
    let first = format.money(values.first ?? 0, currency)
    let last = format.money(values.last ?? 0, currency)
    return format.text(
      "Баланс за период: с \(first) до \(last)", "Balance over the period: from \(first) to \(last)")
  }

  private func labelIndices() -> [Int] {
    let count = min(points.count, period == .week ? 4 : 5)
    guard count > 1 else { return [0] }
    return (0..<count).map { Int((Double($0) * Double(points.count - 1) / Double(count - 1)).rounded()) }
  }

  private func chart(_ scale: FinanceScale, drawn: Bool) -> some View {
    GeometryReader { proxy in
      let box = CGRect(
        x: Self.left, y: Self.top,
        width: max(10, proxy.size.width - Self.left - Self.right),
        height: max(10, proxy.size.height - Self.top - Self.bottom))
      let labels = labelIndices()
      let lastY = box.minY + (1 - (scale.ys.last ?? 0)) * box.height
      ZStack(alignment: .topLeading) {
        FinanceGridShape(
          rows: scale.ticks.map { scale.unit($0) }, columns: labels.map { scale.xs[$0] }
        )
        .stroke(
          RitmTheme.accentColor.opacity(0.16), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
        )
        .frame(width: box.width, height: box.height)
        .offset(x: box.minX, y: box.minY)
        FinanceLineShape(xs: scale.xs, ys: scale.ys, closed: true)
          .fill(
            LinearGradient(
              colors: [RitmTheme.accentColor.opacity(0.26), RitmTheme.accentColor.opacity(0.02)],
              startPoint: .top, endPoint: .bottom)
          )
          .opacity(drawn ? 1 : 0)
          .animation(reduceMotion ? nil : RitmMotion.areaFade, value: drawn)
          .frame(width: box.width, height: box.height)
          .offset(x: box.minX, y: box.minY)
        FinanceLineShape(xs: scale.xs, ys: scale.ys, closed: false)
          .trim(from: 0, to: drawn ? 1 : 0)
          .stroke(
            RitmTheme.accentColor,
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
          )
          .animation(reduceMotion ? nil : RitmMotion.lineDraw, value: drawn)
          .frame(width: box.width, height: box.height)
          .offset(x: box.minX, y: box.minY)
        ForEach(labels, id: \.self) { index in
          Circle()
            .fill(RitmTheme.panel)
            .overlay { Circle().strokeBorder(RitmTheme.accentColor, lineWidth: 2) }
            .frame(width: 8, height: 8)
            .scaleEffect(drawn ? 1 : 0.6)
            .position(
              x: box.minX + scale.xs[index] * box.width,
              y: box.minY + (1 - scale.ys[index]) * box.height
            )
            .opacity(drawn ? 1 : 0)
            .animation(reduceMotion ? nil : RitmMotion.dotPop, value: drawn)
        }
        ForEach(Array(scale.ticks.enumerated()), id: \.offset) { _, tick in
          Text(FinanceScale.compact(tick))
            .ritmFont(10)
            .foregroundStyle(RitmTheme.muted)
            .frame(width: Self.left - 6, alignment: .trailing)
            .position(x: (Self.left - 6) / 2, y: box.minY + (1 - scale.unit(tick)) * box.height)
        }
        ForEach(labels, id: \.self) { index in
          Text(format.date(points[index].date, template: period == .year ? "MMM" : "d MMM"))
            .ritmFont(10)
            .foregroundStyle(RitmTheme.muted)
            .lineLimit(1)
            .fixedSize()
            .position(
              x: min(max(box.minX + scale.xs[index] * box.width, 24), proxy.size.width - 24),
              y: proxy.size.height - 7)
        }
        RitmCountText(points.last?.valueMinor ?? 0) { format.money($0, currency) }
          .ritmFont(10, weight: .medium)
          .foregroundStyle(RitmTheme.text)
          .frame(width: 120, alignment: .trailing)
          .position(x: proxy.size.width - Self.right - 60, y: max(6, lastY - 14))
          .opacity(drawn ? 1 : 0)
          .animation(reduceMotion ? nil : RitmMotion.dotPop, value: drawn)
      }
    }
  }
}

// MARK: - Expense donut

private struct FinanceDonutSlice: Shape {
  let start: Double
  let end: Double
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let visibleEnd = min(end, max(start, progress))
    guard visibleEnd - start > 0.0005 else { return Path() }
    return Circle().trim(from: start, to: visibleEnd).path(in: rect)
  }
}

/// Expense categories: a ring that sweeps in over 700 ms once per `drawKey`, with a legend
/// beside it whose rows fade in one after another.
struct FinanceDonut: View {
  let slices: [FinanceCategoryShare]
  let currency: FinanceCurrency
  let format: FinanceFormat
  let drawKey: String
  let log: FinanceDrawLog
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let ringWidth: CGFloat = 20

  private var total: Int { slices.reduce(0) { $0 + $1.amountMinor } }

  private func name(_ slice: FinanceCategoryShare) -> String {
    guard let name = slice.name else { return format.text("Другое", "Other") }
    return format.text(name, FinanceCategories.englishName(for: name))
  }

  /// Start/end fractions of each slice around the ring.
  private var spans: [(Double, Double)] {
    let sum = max(0.0001, slices.reduce(0) { $0 + $1.share })
    let gap = slices.count > 1 ? 0.008 : 0
    var cursor = 0.0
    return slices.map { slice in
      let begin = cursor
      cursor += slice.share / sum
      return (begin + gap / 2, max(begin + gap / 2, cursor - gap / 2))
    }
  }

  var body: some View {
    RitmDrawGate(key: drawKey) { drawn in
      HStack(alignment: .center, spacing: 18) {
        ring(drawn: drawn)
        legend(drawn: drawn)
      }
    }
  }

  private func ring(drawn: Bool) -> some View {
    let spans = self.spans
    return ZStack {
      Circle().stroke(RitmTheme.ringTrack, lineWidth: Self.ringWidth)
      ForEach(Array(slices.enumerated()), id: \.offset) { index, _ in
        FinanceDonutSlice(start: spans[index].0, end: spans[index].1, progress: drawn ? 1 : 0)
          .stroke(FinanceTone.chart(index), style: StrokeStyle(lineWidth: Self.ringWidth))
      }
    }
    .animation(reduceMotion ? nil : RitmMotion.sweep, value: drawn)
    .padding(Self.ringWidth / 2)
    .rotationEffect(.degrees(-90))
    .frame(width: 128, height: 128)
    .overlay {
      VStack(spacing: 2) {
        RitmCountText(total) { format.money($0, currency) }
          .ritmFont(12, weight: .semibold)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(format.text("Всего", "Total")).ritmFont(10).foregroundStyle(RitmTheme.muted)
      }
      .frame(width: 80)
    }
    .accessibilityHidden(true)
  }

  private func legend(drawn: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
        HStack(spacing: 8) {
          Circle().fill(FinanceTone.chart(index)).frame(width: 9, height: 9)
          Image(systemName: FinanceCategories.symbol(for: slice.name))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(RitmTheme.muted)
            .frame(width: 16)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 1) {
            Text(name(slice)).ritmFont(11, weight: .semibold).lineLimit(1)
            RitmCountText(slice.amountMinor) { format.money($0, currency) }
              .ritmFont(10)
              .foregroundStyle(RitmTheme.muted)
              .lineLimit(1)
          }
          Spacer(minLength: 4)
          RitmCountText(Int((slice.share * 100).rounded())) { "\($0)%" }
            .ritmFont(11, weight: .semibold)
            .foregroundStyle(RitmTheme.muted)
        }
        .opacity(drawn ? 1 : 0)
        .animation(reduceMotion ? nil : RitmMotion.legendFade(index: index), value: drawn)
        .accessibilityElement(children: .combine)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Distribution bar

/// One capsule split by share, one colour per card, growing in from the left once per key.
struct FinanceDistributionBar: View {
  let shares: [Double]
  let drawKey: String
  let log: FinanceDrawLog
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    RitmDrawGate(key: drawKey) { drawn in bar(drawn: drawn) }
      .frame(height: 14)
      .accessibilityHidden(true)
  }

  private func bar(drawn: Bool) -> some View {
    GeometryReader { proxy in
      let gaps = 3 * CGFloat(max(0, shares.count - 1))
      let usable = max(0, proxy.size.width - gaps)
      HStack(spacing: 3) {
        ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(FinanceTone.chart(index))
            .frame(width: max(4, usable * CGFloat(share)))
        }
      }
      .frame(width: proxy.size.width, alignment: .leading)
      .mask(alignment: .leading) {
        Rectangle()
          .frame(width: drawn ? proxy.size.width : 0)
          .animation(reduceMotion ? nil : RitmMotion.sweep, value: drawn)
      }
    }
  }
}

// MARK: - Shared controls

/// The custom segmented control of the calendar, with a sliding active pill.
struct FinanceSegment<Value: Hashable>: View {
  let label: String
  let values: [Value]
  let title: (Value) -> String
  @Binding var selection: Value
  @Namespace private var indicator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 3) {
      ForEach(values, id: \.self) { value in
        let active = value == selection
        Button {
          withAnimation(reduceMotion ? nil : RitmMotion.indicator) { selection = value }
        } label: {
          Text(title(value))
            .ritmFont(13, weight: .medium)
            .lineLimit(1)
            .foregroundStyle(active ? RitmTheme.accentColor : RitmTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
              if active {
                RoundedRectangle(cornerRadius: 9, style: .circular)
                  .fill(RitmTheme.panel)
                  .shadow(color: Color(rgb: 0x3F235F, opacity: 0.07), radius: 5, y: 3)
                  .matchedGeometryEffect(id: "active", in: indicator)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle(scale: 0.97))
        .accessibilityAddTraits(active ? .isSelected : [])
      }
    }
    .padding(2)
    .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }
}

struct FinanceStat: Identifiable {
  let title: String
  let value: String
  let tone: Color
  /// When set, the figure counts to `amount` and `render` writes it exactly like `value`.
  var amount: Int?
  var render: ((Int) -> String)?
  var id: String { title }

  /// A figure that counts up; `value` is its settled text.
  static func counted(
    title: String, amount: Int, tone: Color, render: @escaping (Int) -> String
  ) -> FinanceStat {
    FinanceStat(title: title, value: render(amount), tone: tone, amount: amount, render: render)
  }
}

/// Three figures in a row with hairline dividers (Доходы / Расходы / Разница).
struct FinanceStatTiles: View {
  let stats: [FinanceStat]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
        if index > 0 { Rectangle().fill(RitmTheme.line).frame(width: 1, height: 38) }
        VStack(spacing: 5) {
          Text(stat.title).ritmFont(10).foregroundStyle(RitmTheme.muted).lineLimit(1)
          figure(stat)
            .ritmFont(15, weight: .semibold, tracking: -0.03)
            .foregroundStyle(stat.tone)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
    }
  }

  @ViewBuilder private func figure(_ stat: FinanceStat) -> some View {
    if let amount = stat.amount, let render = stat.render {
      RitmCountText(amount, format: render)
    } else {
      Text(stat.value).monospacedDigit()
    }
  }
}
