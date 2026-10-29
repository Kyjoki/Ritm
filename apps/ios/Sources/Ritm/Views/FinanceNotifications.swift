import Observation
import RitmCore
import SwiftUI
import UIKit

// MARK: - Notice centre

/// Finance notifications derived from the finance list. Only the baseline string and the read
/// entry IDs are stored on the device (UserDefaults); no amounts, titles or other finance data.
@MainActor @Observable
final class FinanceNoticeCenter {
  private(set) var notices: [FinanceNotice] = []
  private(set) var banner: FinanceNotice?
  /// Whether the bell's popover is open (drawn by RitmRootView).
  private(set) var isOpen = false
  private var readIDs: Set<String>
  private(set) var cards: [FinanceCard] = []
  /// The bell's frame in global coordinates; the popover anchors to it. Not observed: it moves
  /// with the page while scrolling and only matters at the moment the popover opens.
  @ObservationIgnored var bellFrame: CGRect = .zero

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var seenIDs: Set<String> = []
  @ObservationIgnored private var primed = false
  @ObservationIgnored private var bannerTask: Task<Void, Never>?
  @ObservationIgnored private var ownWriteActive = false

  private static let baselineKey = "ritm.finance.notices.baseline"
  private static let readKey = "ritm.finance.notices.read"
  private static let bannerSeconds = 4.5

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    readIDs = Set(defaults.stringArray(forKey: Self.readKey) ?? [])
  }

  var unreadCount: Int { notices.reduce(0) { readIDs.contains($1.id) ? $0 : $0 + 1 } }
  func isRead(_ id: String) -> Bool { readIDs.contains(id) }

  func markRead(_ id: String) {
    guard !readIDs.contains(id) else { return }
    readIDs.insert(id)
    persistRead()
  }

  func markAllRead() {
    let ids = Set(notices.map(\.id))
    guard !ids.isSubset(of: readIDs) else { return }
    readIDs.formUnion(ids)
    persistRead()
  }

  /// RitmStore.write brackets every confirmed write with these, including the reload that
  /// follows it, so the owner's own saved operation never raises a banner or an unread badge.
  func beginOwnWrite() { ownWriteActive = true }
  func endOwnWrite() { ownWriteActive = false }

  func dismissBanner() {
    bannerTask?.cancel()
    bannerTask = nil
    banner = nil
  }

  func togglePopover() { isOpen ? closePopover() : openPopover() }
  func openPopover() {
    dismissBanner()
    isOpen = true
  }
  func closePopover() { isOpen = false }

  /// Called with the full, fresh finance list after every successful load.
  /// The first load ever fixes the baseline, so old history never becomes notifications. After
  /// the first update of a launch, an entry ID not seen before (and newer than the baseline)
  /// shows the banner for the newest such entry.
  func update(entries: [FinanceEntry], today: String) {
    let cards = FinanceWallet.cards(entries, today: today)
    self.cards = cards
    let ids = Set(entries.map(\.id))
    guard let baseline = defaults.string(forKey: Self.baselineKey) else {
      defaults.set(FinanceNotices.baseline(entries), forKey: Self.baselineKey)
      seenIDs = ids
      primed = true
      notices = []
      return
    }
    let fresh = FinanceNotices.notices(entries, since: baseline, cards: cards)
    let unseen = primed ? fresh.filter { !seenIDs.contains($0.id) } : []
    // Entries that arrive during the app's own write are the owner's own: no banner, no badge.
    if ownWriteActive, !unseen.isEmpty {
      readIDs.formUnion(unseen.map(\.id))
      persistRead()
    }
    let arrival = ownWriteActive ? nil : unseen.first
    seenIDs = ids
    primed = true
    notices = fresh
    let kept = readIDs.intersection(ids)
    if kept != readIDs {
      readIDs = kept
      persistRead()
    }
    if let arrival { show(arrival) }
  }

  /// Sign-out: forget everything so another account never inherits this baseline.
  func reset() {
    dismissBanner()
    isOpen = false
    notices = []
    cards = []
    readIDs = []
    seenIDs = []
    primed = false
    defaults.removeObject(forKey: Self.baselineKey)
    defaults.removeObject(forKey: Self.readKey)
  }

  private func show(_ notice: FinanceNotice) {
    guard !isOpen else { return }
    banner = notice
    bannerTask?.cancel()
    bannerTask = nil
    // VoiceOver users need time to reach the banner: it stays until dismissed or opened.
    guard !UIAccessibility.isVoiceOverRunning else { return }
    bannerTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.bannerSeconds))
      guard !Task.isCancelled else { return }
      self?.dismissBanner()
    }
  }

  private func persistRead() { defaults.set(readIDs.sorted(), forKey: Self.readKey) }
}

// MARK: - Display

struct FinanceNoticeLine {
  let symbol: String
  let title: String
  let amount: String
  /// «Кофейня · Основной счёт»
  let subtitle: String
  /// «Основной счёт · 09:15»
  let detail: String
}

extension FinanceNoticeCenter {
  func line(for notice: FinanceNotice, store: RitmStore) -> FinanceNoticeLine {
    // The title is the category, else the note; only a known category earns its own icon.
    let known =
      (notice.kind == .income || notice.kind == .expense) && FinanceCategories.isKnown(notice.title)
    let title =
      notice.title.isEmpty
      ? FinanceDisplay.title(notice.kind, language: store.language)
      : known ? store.text(notice.title, FinanceCategories.englishName(for: notice.title))
      : notice.title
    let money = FinanceDisplay.money(
      notice.amountMinor, currency: notice.currency, language: store.language)
    let sign = notice.kind == .income ? "+" : notice.kind == .expense ? "\u{2212}" : ""
    let card = cardName(notice, language: store.language)
    let time = FinanceNoticeTime.text(
      createdAt: notice.createdAt, now: store.now, timeZone: store.timeZone,
      language: store.language)
    return FinanceNoticeLine(
      symbol: known
        ? FinanceCategories.symbol(for: notice.title) : FinanceDisplay.symbol(notice.kind),
      title: title, amount: sign + money,
      subtitle: [title, card].compactMap { $0 }.joined(separator: " · "),
      detail: [card, time.isEmpty ? nil : time].compactMap { $0 }.joined(separator: " · "))
  }

  private func cardName(_ notice: FinanceNotice, language: Language) -> String? {
    guard let id = notice.cardID, let card = cards.first(where: { $0.id == id }) else { return nil }
    let ru = language == .ru
    switch card.kind {
    case .account:
      let base = ru ? "Основной счёт" : "Main account"
      return cards.filter { $0.kind == .account }.count > 1
        ? "\(base) · \(card.currency.rawValue)" : base
    case .deposit: return card.name ?? (ru ? "Депозит" : "Deposit")
    case .stocks: return ru ? "Акции" : "Stocks"
    }
  }
}

@MainActor enum FinanceNoticeTime {
  private static let clock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"
    return formatter
  }()
  private static let short = DateFormatter()
  private static var shortLocaleID = ""
  private static let fractionalISO: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static let plainISO = ISO8601DateFormatter()

  /// «Сейчас», today's clock time, «Вчера, 6:24 PM» or a short date. Times use AM/PM.
  /// The formatters are shared; zone and locale are only reassigned when they change.
  static func text(createdAt: String, now: Date, timeZone: String, language: Language) -> String {
    guard let date = parse(createdAt) else { return "" }
    let ru = language == .ru
    let age = now.timeIntervalSince(date)
    if age > -300 && age < 90 { return ru ? "Сейчас" : "Now" }
    let zone = TimeZone(identifier: timeZone) ?? .current
    if clock.timeZone != zone { clock.timeZone = zone }
    let today = HabitSchedule.dateKey(now, timeZone: timeZone)
    let day = HabitSchedule.dateKey(date, timeZone: timeZone)
    if day == today { return clock.string(from: date) }
    if day == HabitSchedule.addDays(to: today, days: -1) {
      return (ru ? "Вчера, " : "Yesterday, ") + clock.string(from: date)
    }
    let localeID = ru ? "ru_RU" : "en_US"
    if shortLocaleID != localeID {
      shortLocaleID = localeID
      short.locale = Locale(identifier: localeID)
      short.setLocalizedDateFormatFromTemplate("d MMM")
    }
    if short.timeZone != zone { short.timeZone = zone }
    return short.string(from: date)
  }

  private static func parse(_ value: String) -> Date? {
    fractionalISO.date(from: value) ?? plainISO.date(from: value)
  }
}

// MARK: - Bell

/// The header bell: unread count badge, and the anchor of the notification popover.
struct FinanceBellButton: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.ritmPageActive) private var pageActive

  var body: some View {
    let center = store.notices
    let unread = center.unreadCount
    Button {
      center.togglePopover()
    } label: {
      Image(systemName: "bell")
        .font(.system(size: 18))
        .foregroundStyle(center.isOpen ? RitmTheme.accentColor : RitmTheme.muted)
        .frame(width: 44, height: 44)
        .background { RitmHeaderIconBackground() }
        .overlay(alignment: .topTrailing) {
          if unread > 0 {
            Text(unread > 9 ? "9+" : "\(unread)")
              .ritmFont(10, weight: .bold)
              .foregroundStyle(RitmTheme.accentInk)
              .padding(.horizontal, 4)
              .frame(minWidth: 17, minHeight: 17)
              .background(RitmTheme.accentColor, in: Capsule())
              .offset(x: 4, y: -4)
              .accessibilityHidden(true)
          }
        }
    }
    .buttonStyle(RitmPressStyle(scale: 0.9))
    .background { frameReader }
    .accessibilityLabel(
      unread > 0
        ? store.text("Уведомления, непрочитанных: \(unread)", "Notifications, unread: \(unread)")
        : store.text("Уведомления", "Notifications")
    )
    .accessibilityValue(center.isOpen ? store.text("Открыто", "Open") : "")
  }

  private var frameReader: some View {
    GeometryReader { proxy in
      let frame = proxy.frame(in: .global)
      Color.clear
        .onAppear { record(frame) }
        .onChange(of: frame) { _, value in record(value) }
        .onChange(of: pageActive) { _, _ in record(frame) }
    }
  }

  /// Pages kept alive behind the active one must not move the anchor.
  private func record(_ frame: CGRect) {
    guard pageActive else { return }
    store.notices.bellFrame = frame
  }
}

// MARK: - Overlay (popover and banner)

/// Drawn by RitmRootView above the page: the anchored popover and the «Операция добавлена» banner.
struct FinanceNotificationOverlay: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let openNotice: (FinanceNotice) -> Void
  let openSettings: () -> Void

  private static let headerHeight: CGFloat = 62
  private static let bannerTop: CGFloat = headerHeight + 6

  /// The popover inflates out of the bell in 0.30 s with a tiny overshoot
  /// (cubic-bezier(.34, 1.32, .5, 1), about 3 %) and shrinks back in 0.18 s, plain ease-out.
  private func popoverMotion(opening: Bool) -> Animation {
    if reduceMotion { return .easeOut(duration: 0.12) }
    return opening
      ? .timingCurve(0.34, 1.32, 0.5, 1, duration: 0.30)
      : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
  }

  /// The banner slides down from under the top bar in 0.26 s and leaves upward in 0.20 s.
  private func bannerMotion(arriving: Bool) -> Animation {
    if reduceMotion { return .easeOut(duration: 0.12) }
    return arriving
      ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)
      : .timingCurve(0.4, 0, 1, 1, duration: 0.20)
  }

  /// Taller than any banner, so at the start of the slide it is wholly behind the top bar.
  private static let bannerLift: CGFloat = 96

  var body: some View {
    let center = store.notices
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        if center.isOpen {
          Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { center.closePopover() }
            .accessibilityHidden(true)
          popover(center, in: proxy)
        }
        bannerLayer(center)
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
      .animation(popoverMotion(opening: center.isOpen), value: center.isOpen)
    }
  }

  /// The banner's own layer. Its top is masked at the bar's lower edge, so the banner appears
  /// from beneath the bar instead of drawing over it.
  private func bannerLayer(_ center: FinanceNoticeCenter) -> some View {
    let visible: FinanceNotice? = center.isOpen ? nil : center.banner
    return ZStack(alignment: .top) {
      if let banner = visible {
        FinanceBanner(
          notice: banner, open: { openNotice(banner) }, close: { center.dismissBanner() }
        )
        .id(banner.id)
        .padding(.horizontal, 16)
        .padding(.top, Self.bannerTop)
        .transition(
          reduceMotion
            ? .opacity
            : .offset(y: -Self.bannerLift).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .mask(alignment: .top) {
      VStack(spacing: 0) {
        Color.clear.frame(height: reduceMotion ? 0 : Self.headerHeight)
        Color.black
      }
    }
    .animation(bannerMotion(arriving: visible != nil), value: visible?.id)
  }

  private func popover(_ center: FinanceNoticeCenter, in proxy: GeometryProxy) -> some View {
    let size = proxy.size
    let origin = proxy.frame(in: .global).origin
    let bell =
      center.bellFrame == .zero
      ? CGRect(x: size.width - 112, y: 9, width: 44, height: 44)
      : center.bellFrame.offsetBy(dx: -origin.x, dy: -origin.y)
    let width = min(340, size.width - 24)
    // The popover's right edge lines up with the header's (bell + gap + theme toggle).
    let left = min(max(bell.maxX + 52 - width, 12), size.width - width - 12)
    let top = bell.maxY + 2
    // The bell's centre, as a point of the full-size wrapper the transition scales.
    let anchor = UnitPoint(x: bell.midX / max(size.width, 1), y: bell.midY / max(size.height, 1))
    let listLimit = max(120, min(380, size.height - top - 112 - 150))
    return FinancePopover(
      width: width, notchX: bell.midX - left, listLimit: listLimit, openNotice: openNotice,
      openSettings: openSettings
    )
    .padding(.leading, left)
    .padding(.top, top)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // Scaling the full-size wrapper about the bell's centre scales the popover about the bell,
    // so it grows out of the bell (the notch with it) and closes back into it.
    .transition(
      reduceMotion ? .opacity : .scale(scale: 0.4, anchor: anchor).combined(with: .opacity))
  }
}

/// A rounded panel whose top edge carries a small notch pointing at the bell.
private struct FinancePopoverShape: Shape {
  static let notchHeight: CGFloat = 7
  let notchX: CGFloat
  var cornerRadius: CGFloat = 22

  func path(in rect: CGRect) -> Path {
    let top = rect.minY + Self.notchHeight
    let radius = cornerRadius
    let half: CGFloat = 8
    let tip = min(max(notchX, rect.minX + radius + half), rect.maxX - radius - half)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + radius, y: top))
    path.addLine(to: CGPoint(x: tip - half, y: top))
    path.addLine(to: CGPoint(x: tip, y: rect.minY))
    path.addLine(to: CGPoint(x: tip + half, y: top))
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: top),
      tangent2End: CGPoint(x: rect.maxX, y: top + radius), radius: radius)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
      tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
    path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: top),
      tangent2End: CGPoint(x: rect.minX + radius, y: top), radius: radius)
    path.closeSubpath()
    return path
  }
}

private struct FinancePopover: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  let width: CGFloat
  let notchX: CGFloat
  let listLimit: CGFloat
  let openNotice: (FinanceNotice) -> Void
  let openSettings: () -> Void

  var body: some View {
    let center = store.notices
    let shape = FinancePopoverShape(notchX: notchX)
    VStack(spacing: 0) {
      header(center)
      separator
      list(center)
      separator
      footer
    }
    .padding(.top, FinancePopoverShape.notchHeight)
    .frame(width: width)
    .clipShape(shape)
    .background {
      shape.fill(RitmTheme.glassDense)
        .overlay { if !reduceTransparency { shape.fill(RitmTheme.panelSheen) } }
        .overlay {
          shape.stroke(contrast == .increased ? RitmTheme.text : RitmTheme.panelBorder, lineWidth: 1)
        }
        .shadow(color: Color(rgb: 0x1A0D2D, opacity: 0.26), radius: 24, y: 16)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityLabel(store.text("Уведомления", "Notifications"))
    .accessibilityAction(.escape) { center.closePopover() }
  }

  private var separator: some View {
    Rectangle().fill(RitmTheme.line).frame(height: 1).padding(.horizontal, 16)
  }

  private func header(_ center: FinanceNoticeCenter) -> some View {
    let unread = center.unreadCount
    let title = HStack(spacing: 8) {
      Text(store.text("Уведомления", "Notifications"))
        .ritmFont(18, weight: .semibold, tracking: -0.02)
        .foregroundStyle(RitmTheme.text)
        .lineLimit(1)
        .accessibilityAddTraits(.isHeader)
      if unread > 0 {
        Text("\(unread)")
          .ritmFont(11, weight: .bold)
          .foregroundStyle(RitmTheme.accentInk)
          .padding(.horizontal, 7)
          .frame(minWidth: 22, minHeight: 20)
          .background(RitmTheme.accentColor, in: Capsule())
          .accessibilityHidden(true)
      }
    }
    let readAll = Button {
      center.markAllRead()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle").font(.system(size: 14))
        Text(store.text("Прочитать все", "Mark all read")).ritmFont(11, weight: .medium).lineLimit(1)
      }
      .foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, 10)
      .frame(minHeight: 44)
      .background {
        Capsule().strokeBorder(RitmTheme.panelBorder, lineWidth: 1)
      }
      .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle())
    .disabled(unread == 0)
    .opacity(unread == 0 ? 0.5 : 1)
    let closeButton = Button {
      center.closePopover()
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(RitmTheme.muted)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(store.text("Закрыть уведомления", "Close notifications"))
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 4) {
        title
        Spacer(minLength: 4)
        readAll
        closeButton
      }
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 4) {
          title
          Spacer(minLength: 4)
          closeButton
        }
        readAll
      }
    }
    .padding(.leading, 16)
    .padding(.trailing, 6)
    .padding(.vertical, 2)
  }

  @ViewBuilder private func list(_ center: FinanceNoticeCenter) -> some View {
    if center.notices.isEmpty {
      Text(store.text("Новых операций пока нет.", "No new activity yet."))
        .ritmText(.body)
        .foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
        .padding(.horizontal, 16)
    } else {
      let rows = VStack(spacing: 0) {
        ForEach(Array(center.notices.enumerated()), id: \.element.id) { index, notice in
          FinanceNoticeRow(notice: notice, separated: index > 0) { openNotice(notice) }
        }
      }
      ViewThatFits(in: .vertical) {
        rows
        ScrollView { rows }.scrollBounceBehavior(.basedOnSize)
      }
      .frame(maxHeight: listLimit)
    }
  }

  private var footer: some View {
    Button(action: openSettings) {
      HStack(spacing: 12) {
        Image(systemName: "gearshape")
          .font(.system(size: 18))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 26)
          .accessibilityHidden(true)
        Text(store.text("Настройки уведомлений", "Notification settings"))
          .ritmFont(13, weight: .medium)
          .foregroundStyle(RitmTheme.text)
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.985))
  }
}

private struct FinanceNoticeIcon: View {
  let symbol: String
  let size: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    Image(systemName: symbol)
      .font(.system(size: size * 0.4, weight: .regular))
      .foregroundStyle(RitmTheme.accentColor)
      .frame(width: size, height: size)
      .background(RitmTheme.soft, in: shape)
      .overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
      .accessibilityHidden(true)
  }
}

private struct FinanceNoticeRow: View {
  @Environment(RitmStore.self) private var store
  let notice: FinanceNotice
  let separated: Bool
  let action: () -> Void

  var body: some View {
    let center = store.notices
    let line = center.line(for: notice, store: store)
    let unread = !center.isRead(notice.id)
    Button(action: action) {
      HStack(spacing: 12) {
        FinanceNoticeIcon(symbol: line.symbol, size: 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(line.title)
            .ritmFont(14, weight: .semibold, tracking: -0.01)
            .foregroundStyle(RitmTheme.text)
            .lineLimit(1)
          Text(line.detail)
            .ritmFont(11)
            .foregroundStyle(RitmTheme.muted)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 6) {
          Text(line.amount)
            .ritmFont(13, weight: .semibold)
            .foregroundStyle(notice.kind == .transfer ? RitmTheme.muted : RitmTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          HStack(spacing: 8) {
            if unread {
              Circle().fill(RitmTheme.accentColor).frame(width: 8, height: 8)
            }
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(RitmTheme.muted)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(minHeight: 64)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.985))
    .overlay(alignment: .top) {
      if separated {
        Rectangle().fill(RitmTheme.line).frame(height: 1).padding(.horizontal, 16)
      }
    }
    .accessibilityLabel(
      [line.title, line.amount, line.detail]
        .filter { !$0.isEmpty }.joined(separator: ", ")
        + (unread ? ", " + store.text("не прочитано", "unread") : ""))
    .accessibilityHint(store.text("Открыть в разделе «Финансы»", "Open in Finance"))
  }
}

// MARK: - Banner

private struct FinanceBanner: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  let notice: FinanceNotice
  let open: () -> Void
  let close: () -> Void

  var body: some View {
    let line = store.notices.line(for: notice, store: store)
    let kicker = store.text("Операция добавлена", "Transaction added")
    let spoken = [kicker, line.amount, line.subtitle].joined(separator: ", ")
    let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
    // The close control has its own column, so the rest of the banner is one tap target.
    HStack(alignment: .top, spacing: 0) {
      Button(action: open) {
        HStack(spacing: 12) {
          FinanceNoticeIcon(symbol: line.symbol, size: 48)
          VStack(alignment: .leading, spacing: 2) {
            Text(kicker)
              .ritmFont(11, weight: .medium)
              .foregroundStyle(RitmTheme.muted)
              .lineLimit(2)
            Text(line.amount)
              .ritmFont(20, weight: .semibold, tracking: -0.02)
              .foregroundStyle(RitmTheme.text)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text(line.subtitle)
              .ritmFont(12)
              .foregroundStyle(RitmTheme.muted)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RitmTheme.muted)
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.985))
      .accessibilityLabel(spoken)
      .accessibilityHint(store.text("Открыть в разделе «Финансы»", "Open in Finance"))
      VStack(alignment: .trailing, spacing: 0) {
        Text(store.text("Сейчас", "Now"))
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
          .padding(.top, 8)
          .padding(.trailing, 10)
          .accessibilityHidden(true)
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RitmTheme.muted)
            .frame(width: 28, height: 28)
            .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 9, style: .circular))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .accessibilityLabel(store.text("Закрыть", "Close"))
      }
      .padding(.trailing, 2)
      .padding(.bottom, 4)
    }
    .background {
      shape.fill(RitmTheme.glassDense)
        .overlay { if !reduceTransparency { shape.fill(RitmTheme.panelSheen) } }
        .overlay { shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
        .shadow(color: Color(rgb: 0x1A0D2D, opacity: 0.24), radius: 22, y: 14)
    }
    .frame(maxWidth: 520)
    .onAppear {
      UIAccessibility.post(notification: .announcement, argument: spoken)
    }
  }
}
