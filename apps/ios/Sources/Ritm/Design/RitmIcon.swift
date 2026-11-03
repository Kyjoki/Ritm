import Foundation
import SwiftUI

// The prototype's icon set (Lucide-style stroke icons on a 24 × 24 grid, round caps and joins),
// drawn natively from their SVG geometry. `RitmIconName` and the geometry live in the generated
// RitmIconData.swift; this file has the SVG reader, the cache and the views.
//
//   RitmIcon(.bell).font(.system(size: 20)).foregroundStyle(RitmTheme.muted)
//   RitmSymbol("clock")        // an SF Symbol name; the prototype glyph when there is one
//
// An icon takes its size from `.font` exactly like an SF Symbol (the 24-unit grid fills the
// symbol's box, so `.font(.system(size: 20))` is the prototype's 20 px icon) and its colour from
// `foregroundStyle`. Geometry is parsed once per icon and cached; a render only draws paths.

// MARK: - Views

struct RitmIcon: View {
  let name: RitmIconName

  init(_ name: RitmIconName) { self.name = name }

  var body: some View {
    let drawing = RitmIconCatalog.drawing(name)
    // An invisible symbol gives the icon the metrics of the current font; the glyph is drawn over it.
    Image(systemName: "square")
      .hidden()
      .overlay { RitmIconCanvas(drawing: drawing) }
      .accessibilityHidden(true)
  }
}

/// A glyph chosen by SF Symbol name: the prototype icon when one matches, else the symbol itself.
struct RitmSymbol: View {
  let name: String

  init(_ name: String) { self.name = name }

  var body: some View {
    if let icon = RitmIconName(symbol: name) {
      RitmIcon(icon)
    } else {
      Image(systemName: name)
    }
  }
}

private struct RitmIconCanvas: View {
  let drawing: RitmIconDrawing

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / RitmIconDrawing.grid
      context.translateBy(
        x: (size.width - RitmIconDrawing.grid * scale) / 2,
        y: (size.height - RitmIconDrawing.grid * scale) / 2)
      context.scaleBy(x: scale, y: scale)
      let style = StrokeStyle(lineWidth: drawing.stroke, lineCap: .round, lineJoin: .round)
      for layer in drawing.layers {
        if layer.fill { context.fill(layer.path, with: .foreground) }
        if layer.stroke && drawing.stroke > 0 {
          var layerStyle = style
          layerStyle.dash = layer.dash
          context.stroke(
            layer.path, with: layer.ink ? .color(RitmTheme.accentInk) : .foreground,
            style: layerStyle)
        }
      }
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Drawing and cache

/// One icon, parsed: a few merged paths in grid units.
struct RitmIconDrawing: Sendable {
  static let grid: CGFloat = 24

  struct Layer: Sendable {
    var path: Path
    var fill: Bool
    var stroke: Bool
    /// Stroked in the on-accent ink instead of the foreground (a tick cut out of a filled box).
    var ink: Bool
    var dash: [CGFloat]
  }

  let stroke: CGFloat
  let layers: [Layer]
}

enum RitmIconCatalog {
  private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var drawings: [RitmIconName: RitmIconDrawing] = [:]

    func drawing(_ name: RitmIconName) -> RitmIconDrawing {
      lock.lock()
      defer { lock.unlock() }
      if let cached = drawings[name] { return cached }
      let parsed = RitmSVG.parse(RitmIconData.source(name))
      drawings[name] = parsed
      return parsed
    }
  }

  private static let cache = Cache()

  static func drawing(_ name: RitmIconName) -> RitmIconDrawing { cache.drawing(name) }
}

// MARK: - SVG reader

/// Just enough SVG for the icon set: `path` (M L H V C S Q T A Z, absolute and relative),
/// `circle`, `ellipse`, `rect`, `line`, `polyline`, `polygon`; `fill="currentColor"`,
/// `stroke="var(--accent-ink)"` and `stroke-dasharray`.
enum RitmSVG {
  static func parse(_ source: RitmIconSource) -> RitmIconDrawing {
    var layers: [RitmIconDrawing.Layer] = []
    for element in elements(in: source.body) {
      guard var path = shape(element) else { continue }
      let filled = element.attributes["fill"] == "currentColor"
      let hidden = element.attributes["stroke"] == "none"
      let ink = element.attributes["stroke"]?.contains("accent-ink") == true
      let dash = (element.attributes["stroke-dasharray"] ?? "")
        .split(whereSeparator: { $0 == " " || $0 == "," })
        .compactMap { Double($0).map { CGFloat($0) } }
      let layer = RitmIconDrawing.Layer(
        path: path, fill: filled, stroke: !hidden, ink: ink, dash: dash)
      // Neighbours with the same look share one path, so a glyph is one or two draw calls.
      if let last = layers.last, last.fill == layer.fill, last.stroke == layer.stroke,
        last.ink == layer.ink, last.dash == layer.dash
      {
        path.addPath(last.path)
        layers[layers.count - 1].path = path
      } else {
        layers.append(layer)
      }
    }
    return RitmIconDrawing(stroke: CGFloat(source.stroke), layers: layers)
  }

  // MARK: Elements

  private struct Element {
    let tag: String
    let attributes: [String: String]
  }

  private static func elements(in body: String) -> [Element] {
    var result: [Element] = []
    var rest = Substring(body)
    while let open = rest.firstIndex(of: "<") {
      guard let close = rest[open...].firstIndex(of: ">") else { break }
      var inner = rest[rest.index(after: open)..<close]
      rest = rest[rest.index(after: close)...]
      if inner.hasPrefix("/") { continue }
      if inner.hasSuffix("/") { inner = inner.dropLast() }
      let tag = inner.prefix { !$0.isWhitespace }
      result.append(Element(tag: String(tag), attributes: attributes(of: inner.dropFirst(tag.count))))
    }
    return result
  }

  private static func attributes(of text: Substring) -> [String: String] {
    var result: [String: String] = [:]
    var rest = text
    while let equals = rest.firstIndex(of: "=") {
      let name = rest[..<equals].trimmingCharacters(in: .whitespaces)
      let afterEquals = rest.index(after: equals)
      guard afterEquals < rest.endIndex, let openQuote = rest[afterEquals...].first(where: { $0 == "\"" || $0 == "'" }),
        let quoteIndex = rest[afterEquals...].firstIndex(of: openQuote)
      else { break }
      let valueStart = rest.index(after: quoteIndex)
      guard let closeQuote = rest[valueStart...].firstIndex(of: openQuote) else { break }
      result[name] = String(rest[valueStart..<closeQuote])
      rest = rest[rest.index(after: closeQuote)...]
    }
    return result
  }

  private static func shape(_ element: Element) -> Path? {
    let a = element.attributes
    func number(_ key: String, _ fallback: CGFloat = 0) -> CGFloat {
      a[key].flatMap { Double($0) }.map { CGFloat($0) } ?? fallback
    }
    switch element.tag {
    case "path":
      return a["d"].map { pathData($0) }
    case "circle":
      let r = number("r")
      return Path(
        ellipseIn: CGRect(x: number("cx") - r, y: number("cy") - r, width: 2 * r, height: 2 * r))
    case "ellipse":
      let rx = number("rx"), ry = number("ry")
      return Path(
        ellipseIn: CGRect(
          x: number("cx") - rx, y: number("cy") - ry, width: 2 * rx, height: 2 * ry))
    case "rect":
      let rect = CGRect(
        x: number("x"), y: number("y"), width: number("width"), height: number("height"))
      let rx = number("rx", number("ry"))
      return rx > 0
        ? Path(roundedRect: rect, cornerRadius: rx, style: .circular) : Path(rect)
    case "line":
      var path = Path()
      path.move(to: CGPoint(x: number("x1"), y: number("y1")))
      path.addLine(to: CGPoint(x: number("x2"), y: number("y2")))
      return path
    case "polyline", "polygon":
      let values = PathScanner.numbers(a["points"] ?? "")
      guard values.count >= 4 else { return nil }
      var path = Path()
      path.move(to: CGPoint(x: values[0], y: values[1]))
      var i = 2
      while i + 1 < values.count {
        path.addLine(to: CGPoint(x: values[i], y: values[i + 1]))
        i += 2
      }
      if element.tag == "polygon" { path.closeSubpath() }
      return path
    default:
      return nil
    }
  }

  // MARK: Path data

  static func pathData(_ data: String) -> Path {
    var scanner = PathScanner(data)
    var path = Path()
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastCubic: CGPoint?
    var lastQuad: CGPoint?
    var command: Character = " "

    while true {
      scanner.skipSeparators()
      guard let next = scanner.peek() else { break }
      if next.isLetter {
        command = scanner.take()
        if command == "z" || command == "Z" {
          path.closeSubpath()
          current = start
          lastCubic = nil
          lastQuad = nil
          continue
        }
      } else if command == " " {
        break
      }
      let relative = command.isLowercase
      let ox = relative ? current.x : 0
      let oy = relative ? current.y : 0
      switch Character(command.lowercased()) {
      case "m":
        guard let x = scanner.number(), let y = scanner.number() else { return path }
        current = CGPoint(x: x + ox, y: y + oy)
        start = current
        path.move(to: current)
        // Further pairs after a moveto are implicit lineto commands.
        command = relative ? "l" : "L"
        lastCubic = nil
        lastQuad = nil
      case "l":
        guard let x = scanner.number(), let y = scanner.number() else { return path }
        current = CGPoint(x: x + ox, y: y + oy)
        path.addLine(to: current)
        lastCubic = nil
        lastQuad = nil
      case "h":
        guard let x = scanner.number() else { return path }
        current = CGPoint(x: x + ox, y: current.y)
        path.addLine(to: current)
        lastCubic = nil
        lastQuad = nil
      case "v":
        guard let y = scanner.number() else { return path }
        current = CGPoint(x: current.x, y: y + oy)
        path.addLine(to: current)
        lastCubic = nil
        lastQuad = nil
      case "c":
        guard let x1 = scanner.number(), let y1 = scanner.number(), let x2 = scanner.number(),
          let y2 = scanner.number(), let x = scanner.number(), let y = scanner.number()
        else { return path }
        let c1 = CGPoint(x: x1 + ox, y: y1 + oy)
        let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
        current = CGPoint(x: x + ox, y: y + oy)
        path.addCurve(to: current, control1: c1, control2: c2)
        lastCubic = c2
        lastQuad = nil
      case "s":
        guard let x2 = scanner.number(), let y2 = scanner.number(), let x = scanner.number(),
          let y = scanner.number()
        else { return path }
        let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
        current = CGPoint(x: x + ox, y: y + oy)
        path.addCurve(to: current, control1: c1, control2: c2)
        lastCubic = c2
        lastQuad = nil
      case "q":
        guard let x1 = scanner.number(), let y1 = scanner.number(), let x = scanner.number(),
          let y = scanner.number()
        else { return path }
        let control = CGPoint(x: x1 + ox, y: y1 + oy)
        current = CGPoint(x: x + ox, y: y + oy)
        path.addQuadCurve(to: current, control: control)
        lastQuad = control
        lastCubic = nil
      case "t":
        guard let x = scanner.number(), let y = scanner.number() else { return path }
        let control = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        current = CGPoint(x: x + ox, y: y + oy)
        path.addQuadCurve(to: current, control: control)
        lastQuad = control
        lastCubic = nil
      case "a":
        guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
          let large = scanner.flag(), let sweep = scanner.flag(), let x = scanner.number(),
          let y = scanner.number()
        else { return path }
        let end = CGPoint(x: x + ox, y: y + oy)
        addArc(
          to: &path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large,
          sweep: sweep)
        current = end
        lastCubic = nil
        lastQuad = nil
      default:
        return path
      }
    }
    return path
  }

  /// SVG endpoint arc to cubic curves (SVG 1.1 implementation notes, F.6).
  private static func addArc(
    to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
    rotation: CGFloat, large: Bool, sweep: Bool
  ) {
    var rx = abs(rx0), ry = abs(ry0)
    guard p0 != p1 else { return }
    guard rx > 0, ry > 0 else {
      path.addLine(to: p1)
      return
    }
    let phi = rotation * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
      let scale = lambda.squareRoot()
      rx *= scale
      ry *= scale
    }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var factor = denominator == 0 ? 0 : (max(0, numerator / denominator)).squareRoot()
    if large == sweep { factor = -factor }
    let cxp = factor * rx * y1 / ry
    let cyp = -factor * ry * x1 / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
      let dot = ux * vx + uy * vy
      let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
      var value = acos(min(1, max(-1, dot / length)))
      if ux * vy - uy * vx < 0 { value = -value }
      return value
    }
    let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
    var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
    if !sweep && delta > 0 { delta -= 2 * .pi }
    if sweep && delta < 0 { delta += 2 * .pi }
    let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / CGFloat(segments)
    let k = 4 / 3 * tan(step / 4)
    var t = theta1
    for _ in 0..<segments {
      let cosT = cos(t), sinT = sin(t)
      let cosU = cos(t + step), sinU = sin(t + step)
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
          x: cosPhi * rx * x - sinPhi * ry * y + cx, y: sinPhi * rx * x + cosPhi * ry * y + cy)
      }
      path.addCurve(
        to: point(cosU, sinU),
        control1: point(cosT - k * sinT, sinT + k * cosT),
        control2: point(cosU + k * sinU, sinU - k * cosU))
      t += step
    }
  }

  /// A cursor over path data: numbers without separators (`1.5-3.5`, `.5.5`), arc flags.
  private struct PathScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) { characters = Array(text) }

    func peek() -> Character? { index < characters.count ? characters[index] : nil }

    mutating func take() -> Character {
      defer { index += 1 }
      return characters[index]
    }

    mutating func skipSeparators() {
      while let c = peek(), c == " " || c == "," || c == "\n" || c == "\t" { index += 1 }
    }

    mutating func flag() -> Bool? {
      skipSeparators()
      guard let c = peek(), c == "0" || c == "1" else { return nil }
      index += 1
      return c == "1"
    }

    mutating func number() -> CGFloat? {
      skipSeparators()
      let begin = index
      if let c = peek(), c == "-" || c == "+" { index += 1 }
      var digits = false
      while let c = peek(), c.isNumber { index += 1; digits = true }
      if peek() == "." {
        index += 1
        while let c = peek(), c.isNumber { index += 1; digits = true }
      }
      if digits, let c = peek(), c == "e" || c == "E" {
        index += 1
        if let s = peek(), s == "-" || s == "+" { index += 1 }
        while let d = peek(), d.isNumber { index += 1 }
      }
      guard digits, let value = Double(String(characters[begin..<index])) else {
        index = begin
        return nil
      }
      return CGFloat(value)
    }

    /// All numbers of a `points` list.
    static func numbers(_ text: String) -> [CGFloat] {
      var scanner = PathScanner(text)
      var result: [CGFloat] = []
      while let value = scanner.number() { result.append(value) }
      return result
    }
  }
}

// MARK: - SF Symbol bridge

extension RitmIconName {
  /// The prototype glyph that stands for an SF Symbol the native screens used before, or nil.
  init?(symbol: String) {
    guard let name = Self.symbolMap[symbol] else { return nil }
    self = name
  }

  private static let symbolMap: [String: RitmIconName] = [
    // navigation and chrome
    "square.grid.2x2": .grid, "calendar": .cal, "calendar.badge.clock": .cal,
    "checkmark.circle": .ok, "wallet.pass": .wallet, "wallet.bifold": .wallet,
    "sparkles": .sparkles, "ellipsis": .dots, "slider.horizontal.3": .sliders,
    "dumbbell": .dumbbell, "bell": .bell, "sun.max": .sun, "moon": .moon, "lock": .lock,
    "info.circle": .info, "heart": .heart, "heart.text.square": .heart, "folder": .folder,
    "network": .network, "globe": .globe, "person": .user, "person.crop.circle": .user,
    "paintpalette": .palette, "paperplane": .plane,
    "rectangle.portrait.and.arrow.right": .logout,
    // actions
    "plus": .plus, "plus.circle": .plusCircle, "minus": .minus, "checkmark": .check,
    "xmark": .close, "pencil": .pencil, "trash": .trash, "archivebox": .archive,
    "arrow.counterclockwise": .undo, "arrow.uturn.backward": .undoAssistant,
    "arrow.clockwise": .refresh, "arrow.triangle.2.circlepath": .refresh,
    "doc.on.doc": .copy, "play.fill": .play, "pause.fill": .pause,
    "arrow.left.arrow.right": .swap, "circle.grid.2x3.fill": .grip,
    // arrows and chevrons
    "chevron.right": .chev, "chevron.left": .chevL, "chevron.down": .chevAssistant,
    "chevron.up.chevron.down": .chevSettings, "arrow.right": .arrow, "arrow.up": .up,
    "arrow.down": .down, "arrow.up.right": .arrowUR, "arrow.down.left": .down,
    // status
    "exclamationmark.circle": .alert, "checkmark.shield": .shield,
    "checkmark.square.fill": .checksq, "square": .square, "clock": .clock,
    "clock.arrow.circlepath": .hist, "checklist": .checklist, "flame": .flame,
    "lightbulb": .bulb, "bubble.left": .bubble,
    // finance
    "cart": .cart, "cup.and.saucer": .cup, "bus": .bus, "house": .home, "bag": .bag,
    "ticket": .ticket, "gift": .gift, "briefcase": .briefcase, "percent": .percent,
    "dollarsign": .dollar, "dollarsign.circle": .coins, "chart.line.uptrend.xyaxis": .chart,
    "building.columns": .coins, "cross.case": .catHealth, "suitcase": .catTravel,
    "graduationcap": .catEdu, "iphone": .catTelecom, "tshirt": .catClothes,
    "face.smiling": .catKids, "pawprint": .catPets, "creditcard": .catBills,
    "banknote": .catSalary, "tag": .catSale, "ellipsis.circle": .catOther,
    // habits
    "square.stack": .stack, "book": .book, "waveform.path.ecg": .activity, "drop": .droplet, "target": .target,
  ]
}
