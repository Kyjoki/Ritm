import Foundation
import RitmCore
import SwiftUI

/// Finance colours: `--income`, `--expense` and the chart palette `--c0…--c5` of the prototype
/// (the chart palette is the same in both themes there).
enum FinanceTone {
  static var income: Color { Color(light: 0x2A7F66, dark: 0x86D4B6) }
  static var expense: Color { Color(light: 0xA4506C, dark: 0xEDA2B9) }
  static var incomeSoft: Color {
    Color(light: 0x74BD9E, dark: 0x74BD9E, lightOpacity: 0.16, darkOpacity: 0.16)
  }
  static var expenseSoft: Color {
    Color(light: 0xD991A5, dark: 0xD991A5, lightOpacity: 0.18, darkOpacity: 0.16)
  }
  /// `--chart-grid`.
  static var grid: Color {
    Color(light: 0x706577, dark: 0xAAA0BA, lightOpacity: 0.22, darkOpacity: 0.22)
  }
  private static let palette: [UInt32] = [0x9C77DB, 0xD798BC, 0x77A6D4, 0x79B8A7, 0xD7AD76, 0xB79CB6]

  static func chart(_ index: Int) -> Color {
    let count = palette.count
    return Color(rgb: palette[((index % count) + count) % count])
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

/// Scale of one balance series: «nice» axis ticks (finance.js `niceTicks`, 3 steps, 10 % padding)
/// and normalised point positions.
private struct FinanceScale {
  let ticks: [Int]
  let xs: [CGFloat]
  let ys: [CGFloat]

  init?(points: [FinancePoint]) {
    guard points.count >= 2 else { return nil }
    let values = points.map(\.valueMinor)
    let low = Double(values.min() ?? 0)
    let high = Double(values.max() ?? 0)
    var pad = (high - low) * 0.1
    if pad == 0 { pad = abs(high) * 0.05 }
    if pad == 0 { pad = 100 }
    let step = Self.niceStep((high + pad - (low - pad)) / 3)
    let first = ((low - pad) / step).rounded(.down) * step
    let last = ((high + pad) / step).rounded(.up) * step
    var ticks: [Int] = []
    var tick = first
    while tick <= last + step * 0.001 && ticks.count < 10 {
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

  /// `700K`, `1,2M`: axis labels for amounts in minor units (finance.js `abbr`).
  static func compact(_ minor: Int) -> String {
    let value = Double(minor) / 100
    let magnitude = abs(value)
    if magnitude >= 1_000_000 {
      let text = String((value / 1_000_000 * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",")
      return (text.hasSuffix(",0") ? String(text.dropLast(2)) : text) + "M"
    }
    if magnitude >= 1_000 { return String(Int((value / 1_000).rounded())) + "K" }
    return String(Int(value.rounded()))
  }
}

/// A monotone cubic curve through `points` (finance.js `monotone`), optionally closed down to
/// `floor` for the area fill.
private struct FinanceCurve: Shape {
  let points: [CGPoint]
  let floor: CGFloat?

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let n = points.count
    guard n > 1 else { return path }
    var dx = [CGFloat](repeating: 0, count: n - 1)
    var m = [CGFloat](repeating: 0, count: n - 1)
    for i in 0..<(n - 1) {
      dx[i] = points[i + 1].x - points[i].x
      m[i] = dx[i] > 0.0001 ? (points[i + 1].y - points[i].y) / dx[i] : 0
    }
    var t = [CGFloat](repeating: 0, count: n)
    t[0] = m[0]
    t[n - 1] = m[n - 2]
    if n > 2 {
      for i in 1..<(n - 1) { t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2 }
    }
    for i in 0..<(n - 1) {
      if m[i] == 0 {
        t[i] = 0
        t[i + 1] = 0
        continue
      }
      let a = t[i] / m[i]
      let b = t[i + 1] / m[i]
      let s = a * a + b * b
      if s > 9 {
        let k = 3 / s.squareRoot()
        t[i] = k * a * m[i]
        t[i + 1] = k * b * m[i]
      }
    }
    path.move(to: points[0])
    for i in 0..<(n - 1) {
      let h = dx[i] / 3
      path.addCurve(
        to: points[i + 1], control1: CGPoint(x: points[i].x + h, y: points[i].y + t[i] * h),
        control2: CGPoint(x: points[i + 1].x - h, y: points[i + 1].y - t[i + 1] * h))
    }
    if let floor {
      path.addLine(to: CGPoint(x: points[n - 1].x, y: floor))
      path.addLine(to: CGPoint(x: points[0].x, y: floor))
      path.closeSubpath()
    }
    return path
  }
}

private struct FinanceGridShape: Shape {
  let ys: [CGFloat]
  let left: CGFloat
  let right: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for y in ys {
      path.move(to: CGPoint(x: left, y: y))
      path.addLine(to: CGPoint(x: right, y: y))
    }
    return path
  }
}

/// The balance chart of the prototype, drawn in its 318 x 164 box (scaled to the panel):
/// dashed grid, 3 axis labels, a monotone 2.2 pt line with a soft fill, one end dot and the end
/// value. The line draws in once per `drawKey` (MOTION.md §4): the stroke in 780 ms, the area
/// fading in once the line passes 40 %, the end dot and label popping at the end.
struct FinanceAreaChart: View {
  let points: [FinancePoint]
  let period: FinancePeriod
  let currency: FinanceCurrency
  let format: FinanceFormat
  let drawKey: String
  let log: FinanceDrawLog
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let boxWidth: CGFloat = 318
  private static let boxHeight: CGFloat = 164
  private static let left: CGFloat = 40
  private static let right: CGFloat = 12
  private static let top: CGFloat = 14
  private static let bottom: CGFloat = 24

  var body: some View {
    if let scale = FinanceScale(points: points) {
      RitmDrawGate(key: drawKey) { drawn in chart(scale, drawn: drawn) }
        .aspectRatio(Self.boxWidth / Self.boxHeight, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary())
    } else {
      Text(format.text("Пока недостаточно данных для графика.", "Not enough data for a chart yet."))
        .ritmFont(11)
        .foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
  }

  private func summary() -> String {
    let values = points.map(\.valueMinor)
    let first = format.money(values.first ?? 0, currency)
    let last = format.money(values.last ?? 0, currency)
    return format.text(
      "Баланс за период: с \(first) до \(last)", "Balance over the period: from \(first) to \(last)")
  }

  /// Five evenly spaced axis labels (fewer when the series is short).
  private func labelIndices() -> [Int] {
    let last = points.count - 1
    var seen = Set<Int>()
    return (0...4).map { Int((Double($0) * Double(last) / 4).rounded()) }.filter { seen.insert($0).inserted }
  }

  private func chart(_ scale: FinanceScale, drawn: Bool) -> some View {
    GeometryReader { proxy in
      let k = proxy.size.width / Self.boxWidth
      let left = Self.left * k
      let right = proxy.size.width - Self.right * k
      let top = Self.top * k
      let plotHeight = proxy.size.height - (Self.top + Self.bottom) * k
      let floor = top + plotHeight
      let curve = zip(scale.xs, scale.ys).map {
        CGPoint(x: left + $0 * (right - left), y: floor - $1 * plotHeight)
      }
      let end = curve[curve.count - 1]
      let labels = labelIndices()
      ZStack(alignment: .topLeading) {
        FinanceGridShape(ys: scale.ticks.map { floor - scale.unit($0) * plotHeight }, left: left, right: right)
          .stroke(FinanceTone.grid, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        FinanceCurve(points: curve, floor: floor)
          .fill(
            LinearGradient(
              colors: [RitmTheme.accentColor.opacity(0.34), RitmTheme.accentColor.opacity(0)],
              startPoint: .top, endPoint: .bottom)
          )
          .opacity(drawn ? 1 : 0)
          .animation(reduceMotion ? nil : RitmMotion.areaFade, value: drawn)
        FinanceCurve(points: curve, floor: nil)
          .trim(from: 0, to: drawn ? 1 : 0)
          .stroke(
            RitmTheme.accentColor,
            style: StrokeStyle(lineWidth: 2.2 * k, lineCap: .round, lineJoin: .round)
          )
          .animation(reduceMotion ? nil : RitmMotion.lineDraw, value: drawn)
        Circle()
          .fill(RitmTheme.panel)
          .overlay { Circle().strokeBorder(RitmTheme.accentColor, lineWidth: 2) }
          .frame(width: 9.6 * k, height: 9.6 * k)
          .scaleEffect(drawn ? 1 : 0.6)
          .position(end)
          .opacity(drawn ? 1 : 0)
          .animation(reduceMotion ? nil : RitmMotion.dotPop, value: drawn)
        ForEach(Array(scale.ticks.enumerated()), id: \.offset) { _, tick in
          Text(FinanceScale.compact(tick))
            .ritmFont(9.5)
            .monospacedDigit()
            .foregroundStyle(RitmTheme.muted)
            .fixedSize()
            .frame(width: left - 6 * k, alignment: .trailing)
            .position(x: (left - 6 * k) / 2, y: floor - scale.unit(tick) * plotHeight)
        }
        ForEach(labels, id: \.self) { index in
          xLabel(index, x: curve[index].x, last: labels.last ?? 0, y: proxy.size.height - 10 * k)
        }
        RitmCountText(points.last?.valueMinor ?? 0) { format.money($0, currency) }
          .ritmFont(10, weight: .semibold)
          .foregroundStyle(RitmTheme.text)
          .fixedSize()
          .frame(width: 100, alignment: .trailing)
          .position(
            x: end.x - 50, y: end.y < top + 16 * k ? end.y + 16 * k - 3 : end.y - 9 * k - 3
          )
          .opacity(drawn ? 1 : 0)
          .animation(reduceMotion ? nil : RitmMotion.dotPop, value: drawn)
      }
    }
  }

  /// A date under the plot: the first label starts at its x, the last one ends there.
  private func xLabel(_ index: Int, x: CGFloat, last: Int, y: CGFloat) -> some View {
    let text = Text(format.day(points[index].date))
      .ritmFont(9.5)
      .foregroundStyle(RitmTheme.muted)
      .fixedSize()
    return Group {
      if index == 0 {
        text.frame(width: 80, alignment: .leading).position(x: x + 40, y: y)
      } else if index == last {
        text.frame(width: 80, alignment: .trailing).position(x: x - 40, y: y)
      } else {
        text.position(x: x, y: y)
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

/// Expense categories: a 136 pt ring that sweeps in over 700 ms once per `drawKey`, with the
/// legend below it (icon, name, amount, share) whose rows fade in one after another.
struct FinanceDonut: View {
  let slices: [FinanceCategoryShare]
  let currency: FinanceCurrency
  let format: FinanceFormat
  let drawKey: String
  let log: FinanceDrawLog
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var total: Int { slices.reduce(0) { $0 + $1.amountMinor } }

  private func name(_ slice: FinanceCategoryShare) -> String {
    guard let name = slice.name else { return format.text("Другое", "Other") }
    return format.text(name, FinanceCategories.englishName(for: name))
  }

  /// Start/end fractions of each slice around the ring.
  private var spans: [(Double, Double)] {
    let sum = max(0.0001, slices.reduce(0) { $0 + $1.share })
    let gap = slices.count > 1 ? 2.5 / 276.5 : 0
    var cursor = 0.0
    return slices.map { slice in
      let begin = cursor
      cursor += slice.share / sum
      return (begin, max(begin + 0.002, cursor - gap))
    }
  }

  var body: some View {
    RitmDrawGate(key: drawKey) { drawn in
      VStack(spacing: 0) {
        ring(drawn: drawn)
          .frame(maxWidth: .infinity)
          .padding(.top, 4)
          .padding(.bottom, 10)
        legend(drawn: drawn)
      }
    }
  }

  private func ring(drawn: Bool) -> some View {
    let spans = self.spans
    return ZStack {
      ForEach(Array(slices.enumerated()), id: \.offset) { index, _ in
        FinanceDonutSlice(start: spans[index].0, end: spans[index].1, progress: drawn ? 1 : 0)
          .stroke(FinanceTone.chart(index), style: StrokeStyle(lineWidth: 15.9))
      }
    }
    .animation(reduceMotion ? nil : RitmMotion.sweep, value: drawn)
    .padding(18.1)
    .rotationEffect(.degrees(-90))
    .frame(width: 136, height: 136)
    .overlay {
      VStack(spacing: 0) {
        RitmCountText(total) { format.money($0, currency) }
          .ritmFont(13.5, weight: .bold, tracking: -0.03)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(format.text("Всего", "Total")).ritmFont(10.5).foregroundStyle(RitmTheme.muted)
      }
      .frame(width: 84)
    }
    .accessibilityHidden(true)
  }

  private func legend(drawn: Bool) -> some View {
    VStack(spacing: 2) {
      ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
        HStack(spacing: 10) {
          RitmSymbol(FinanceCategories.symbol(for: slice.name))
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(FinanceTone.chart(index))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
          Text(name(slice)).ritmFont(12.5).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          RitmCountText(slice.amountMinor) { format.money($0, currency) }
            .ritmFont(12.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          RitmCountText(Int((slice.share * 100).rounded())) { "\($0)%" }
            .ritmFont(11.5)
            .foregroundStyle(RitmTheme.muted)
            .frame(width: 40, alignment: .trailing)
        }
        .foregroundStyle(RitmTheme.text)
        .frame(minHeight: 36)
        .opacity(drawn ? 1 : 0)
        .animation(reduceMotion ? nil : RitmMotion.legendFade(index: index), value: drawn)
        .accessibilityElement(children: .combine)
      }
    }
  }
}

// MARK: - Distribution bar

/// One 12 pt capsule split by share, one colour per account, 2 pt gaps, growing in from the left
/// once per key.
struct FinanceDistributionBar: View {
  let shares: [Double]
  let drawKey: String
  let log: FinanceDrawLog
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    RitmDrawGate(key: drawKey) { drawn in bar(drawn: drawn) }
      .frame(height: 12)
      .accessibilityHidden(true)
  }

  private func bar(drawn: Bool) -> some View {
    GeometryReader { proxy in
      let gaps = 2 * CGFloat(max(0, shares.count - 1))
      let usable = max(0, proxy.size.width - gaps)
      HStack(spacing: 2) {
        ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
          Rectangle()
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
    .clipShape(Capsule())
  }
}

// MARK: - Shared controls

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

/// `.tiles`: three separate small tiles under a chart panel (label, then the figure).
struct FinanceStatTiles: View {
  let stats: [FinanceStat]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(stats) { stat in
        VStack(alignment: .leading, spacing: 3) {
          Text(stat.title).ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(1)
          figure(stat)
            .ritmFont(13, weight: .bold, tracking: -0.025)
            .foregroundStyle(stat.tone)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: 16, style: .circular)
            .fill(RitmTheme.panel)
            .overlay {
              RoundedRectangle(cornerRadius: 16, style: .circular)
                .strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
            }
        }
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
