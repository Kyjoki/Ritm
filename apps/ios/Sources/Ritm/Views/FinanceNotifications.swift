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
  private static let bannerSeconds = 2.0

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
  /// follows it. Own writes raise notices like any other new entry.
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
    // As in the prototype, an operation the owner adds themselves is a notice too: the banner
    // slides in, the bell gets a badge and the list gets a row.
    let arrival = unseen.first
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

/// The header bell (`.icon-btn` + `.badge`): unread count badge, and the anchor of the
/// notification popover.
struct FinanceBellButton: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.ritmPageActive) private var pageActive
  /// The calendar's slim bar draws the bell without its glass disc, like its other icons.
  var plain = false

  var body: some View {
    let center = store.notices
    let unread = center.unreadCount
    Button {
      center.togglePopover()
    } label: {
      let icon = RitmIcon(.bell)
        .font(.system(size: plain ? 21 : 20))
        .foregroundStyle(
          center.isOpen ? RitmTheme.accentColor : plain ? RitmTheme.text : RitmTheme.muted
        )
        .frame(width: 44, height: 44)
      if plain {
        icon.contentShape(Circle())
      } else {
        icon.ritmFloatingGlass(in: Circle(), interactive: true).contentShape(Circle())
      }
    }
    .buttonStyle(RitmGlassButtonStyle())
    .background { frameReader }
    // The badge is an overlay at the corner (`.badge { top: -4px; right: -4px }`): it never
    // changes the bell's or the header's layout, it only scales in when the count changes.
    .overlay(alignment: .topTrailing) {
      ZStack {
        if unread > 0 {
          badge(unread)
            .offset(x: plain ? -8 : 0, y: plain ? 8 : 0)
            .id(unread)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
      }
      .animation(.easeOut(duration: 0.2), value: unread)
      .allowsHitTesting(false)
    }
    .accessibilityLabel(
      unread > 0
        ? store.text("Уведомления, непрочитанных: \(unread)", "Notifications, unread: \(unread)")
        : store.text("Уведомления", "Notifications")
    )
    .accessibilityValue(center.isOpen ? store.text("Открыто", "Open") : "")
  }

  /// `.badge`: 19 pt minimum, 10.5 pt bold, a 2 pt ring in the page colour, 4 pt out of the corner.
  private func badge(_ unread: Int) -> some View {
    Text(unread > 9 ? "9+" : "\(unread)")
      .ritmFont(10.5, weight: .bold)
      .monospacedDigit()
      .foregroundStyle(RitmTheme.accentInk)
      .padding(.horizontal, 5)
      .frame(minWidth: 19, minHeight: 19)
      .background(RitmTheme.accentColor, in: Capsule())
      .overlay { Capsule().strokeBorder(RitmTheme.background, lineWidth: 2) }
      .offset(x: 4, y: -4)
      .accessibilityHidden(true)
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

  /// The top bar's row; the banner sits right under it (`.banner { top: 104px }`).
  private static let headerHeight: CGFloat = 56
  private static let bannerTop: CGFloat = headerHeight + 1

  /// The popover inflates out of the bell in 0.30 s with a tiny overshoot
  /// (cubic-bezier(.34, 1.32, .5, 1), about 3 %) and shrinks back in 0.18 s, plain ease-out.
  private func popoverMotion(opening: Bool) -> Animation {
    if reduceMotion { return .easeOut(duration: 0.12) }
    return opening
      ? .timingCurve(0.34, 1.32, 0.5, 1, duration: 0.30)
      : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
  }

  /// MOTION.md §5: the banner slides down from under the top bar while fading in (0.26 s,
  /// ease-out) and, after 2 s on screen, leaves upward in 0.2 s.
  private func bannerMotion(arriving: Bool) -> Animation {
    if reduceMotion { return .easeOut(duration: 0.12) }
    return arriving ? RitmMotion.easeOut(0.26) : .easeIn(duration: 0.2)
  }

  /// How far the banner travels: from behind the top bar.
  private static let bannerTravel: CGFloat = 56

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

  /// The banner's own layer, placed under the top bar.
  private func bannerLayer(_ center: FinanceNoticeCenter) -> some View {
    let visible: FinanceNotice? = center.isOpen ? nil : center.banner
    return ZStack(alignment: .top) {
      if let banner = visible {
        FinanceBanner(
          notice: banner, open: { openNotice(banner) }, close: { center.dismissBanner() }
        )
        .id(banner.id)
        .transition(
          reduceMotion
            ? .opacity : .offset(y: -Self.bannerTravel).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, Self.bannerTop)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(bannerMotion(arriving: visible != nil), value: visible?.id)
  }

  /// `.pop`: 12 pt from both edges, 11 pt under the bell, at most 520 pt tall and clear of the bar.
  private func popover(_ center: FinanceNoticeCenter, in proxy: GeometryProxy) -> some View {
    let size = proxy.size
    let origin = proxy.frame(in: .global).origin
    let bell =
      center.bellFrame == .zero
      ? CGRect(x: size.width - 94, y: 0, width: 44, height: 44)
      : center.bellFrame.offsetBy(dx: -origin.x, dy: -origin.y)
    let width = size.width - 24
    let top = bell.maxY + 11
    // The bell's centre, as a point of the full-size wrapper the transition scales.
    let anchor = UnitPoint(x: bell.midX / max(size.width, 1), y: bell.midY / max(size.height, 1))
    let maxHeight = min(520, size.height - top - 118)
    return FinancePopover(width: width, maxHeight: maxHeight, openNotice: openNotice, openSettings: openSettings)
      .padding(.leading, 12)
      .padding(.top, top)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // Scaling the full-size wrapper about the bell's centre scales the popover about the bell,
      // so it grows out of the bell and closes back into it.
      .transition(
        reduceMotion ? .opacity : .scale(scale: 0.4, anchor: anchor).combined(with: .opacity))
  }
}

/// The notification panel (`.pop`): glass, radius 22, a header with the count and «Прочитать все»,
/// the list, and the «Настройки уведомлений» row.
private struct FinancePopover: View {
  @Environment(RitmStore.self) private var store
  let width: CGFloat
  let maxHeight: CGFloat
  let openNotice: (FinanceNotice) -> Void
  let openSettings: () -> Void

  var body: some View {
    let center = store.notices
    let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
    VStack(spacing: 0) {
      header(center)
      list(center)
      footer
    }
    .frame(width: width)
    .clipShape(shape)
    // A dense under-layer keeps the rows readable on any content behind the glass.
    .background(RitmTheme.glassDense.opacity(0.6), in: shape)
    .ritmFloatingGlass(in: shape)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityLabel(store.text("Уведомления", "Notifications"))
    .accessibilityAction(.escape) { center.closePopover() }
  }

  private var separator: some View {
    Rectangle().fill(RitmTheme.line).frame(height: 1)
  }

  /// `.pop-h`: 17 pt title, the count badge, and the ghost «Прочитать все» (44 pt) at the end.
  private func header(_ center: FinanceNoticeCenter) -> some View {
    let unread = center.unreadCount
    return HStack(spacing: 8) {
      Text(store.text("Уведомления", "Notifications"))
        .ritmFont(17, weight: .semibold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .lineLimit(1)
        .accessibilityAddTraits(.isHeader)
      if unread > 0 {
        Text("\(unread)")
          .ritmFont(11.5, weight: .bold)
          .foregroundStyle(RitmTheme.accentInk)
          .padding(.horizontal, 7)
          .frame(minWidth: 22, minHeight: 22)
          .background(RitmTheme.accentColor, in: Capsule())
          .accessibilityHidden(true)
      }
      Spacer(minLength: 4)
      Button {
        center.markAllRead()
      } label: {
        HStack(spacing: 6) {
          RitmIcon(.check).font(.system(size: 16))
          Text(store.text("Прочитать все", "Mark all read"))
            .ritmFont(11.5, weight: .semibold)
            .lineLimit(1)
        }
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background {
          Capsule().fill(RitmGlassTokens.buttonFill)
          Capsule().strokeBorder(RitmTheme.line, lineWidth: 1)
        }
        .contentShape(Capsule())
      }
      .buttonStyle(RitmPressStyle())
      .disabled(unread == 0)
      .opacity(unread == 0 ? 0.5 : 1)
    }
    .padding(.leading, 16)
    .padding(.trailing, 14)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }

  @ViewBuilder private func list(_ center: FinanceNoticeCenter) -> some View {
    if center.notices.isEmpty {
      Text(store.text("Новых операций пока нет.", "No new activity yet."))
        .ritmFont(12.5)
        .foregroundStyle(RitmTheme.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 18)
    } else {
      // `.nlist`: the rows scroll when the panel hits its height limit.
      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(center.notices.enumerated()), id: \.element.id) { index, notice in
            FinanceNoticeRow(notice: notice, separated: index > 0) { openNotice(notice) }
          }
        }
        .padding(.horizontal, 8)
      }
      .scrollBounceBehavior(.basedOnSize)
      // The panel is as tall as its rows, up to the limit; header and footer take 117 pt.
      .frame(maxHeight: max(88, maxHeight - 117))
    }
  }

  /// `.pop-foot`: 52 pt, a hairline above, the label, a chevron.
  private var footer: some View {
    VStack(spacing: 0) {
      separator
      Button(action: openSettings) {
        HStack(spacing: 12) {
          RitmIcon(.sliders)
            .font(.system(size: 20))
            .foregroundStyle(RitmTheme.muted)
            .accessibilityHidden(true)
          Text(store.text("Настройки уведомлений", "Notification settings"))
            .ritmFont(13, weight: .semibold)
            .foregroundStyle(RitmTheme.text)
          Spacer(minLength: 8)
          RitmIcon(.chev)
            .font(.system(size: 14, weight: .semibold))
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
}

/// `.ico-tile` / `.b-ico`: a soft rounded tile with the accent glyph; income gets the green one.
private struct FinanceNoticeIcon: View {
  let symbol: String
  let size: CGFloat
  let radius: CGFloat
  var income = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
    RitmSymbol(symbol)
      .font(.system(size: size * 0.5))
      .foregroundStyle(income ? Self.incomeInk : RitmTheme.accentColor)
      .frame(width: size, height: size)
      .background(income ? Self.incomeBackground : RitmTheme.soft, in: shape)
      .accessibilityHidden(true)
  }

  static var incomeInk: Color { Color(light: 0x2A7F66, dark: 0x86D4B6) }
  static var incomeBackground: Color { Color(rgb: 0x74BD9E, opacity: 0.16) }
}

/// `.n-item`: icon 40, title and meta, amount over the unread dot, chevron; 64 pt tall with a
/// hairline between rows.
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
      HStack(spacing: 10) {
        FinanceNoticeIcon(
          symbol: line.symbol, size: 40, radius: 12, income: notice.kind == .income)
        VStack(alignment: .leading, spacing: 1) {
          Text(line.title)
            .ritmFont(13, weight: .bold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text)
            .lineLimit(1)
          Text(line.detail)
            .ritmFont(11)
            .foregroundStyle(RitmTheme.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 5) {
          Text(line.amount)
            .ritmFont(13, weight: .bold, tracking: -0.02)
            .monospacedDigit()
            .foregroundStyle(amountColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .layoutPriority(1)
          Circle()
            .fill(unread ? RitmTheme.accentColor : Color.clear)
            .frame(width: 9, height: 9)
        }
        RitmIcon(.chev)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 16)
      }
      .padding(8)
      .frame(minHeight: 64)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.985))
    .overlay(alignment: .top) {
      if separated { Rectangle().fill(RitmTheme.line).frame(height: 1) }
    }
    .accessibilityLabel(
      [line.title, line.amount, line.detail]
        .filter { !$0.isEmpty }.joined(separator: ", ")
        + (unread ? ", " + store.text("не прочитано", "unread") : ""))
    .accessibilityHint(store.text("Открыть в разделе «Финансы»", "Open in Finance"))
  }

  private var amountColor: Color {
    switch notice.kind {
    case .income: FinanceNoticeIcon.incomeInk
    case .transfer: RitmTheme.muted
    default: RitmTheme.text
    }
  }
}

// MARK: - Banner

/// `.banner`: glass, radius 24, a 48 pt icon tile, «Операция добавлена», the amount at 20 pt,
/// the subtitle; «Сейчас» and a 44 pt close button in the right column.
private struct FinanceBanner: View {
  @Environment(RitmStore.self) private var store
  let notice: FinanceNotice
  let open: () -> Void
  let close: () -> Void

  var body: some View {
    let line = store.notices.line(for: notice, store: store)
    let kicker = store.text("Операция добавлена", "Transaction added")
    let spoken = [kicker, line.amount, line.subtitle].joined(separator: ", ")
    let shape = RoundedRectangle(cornerRadius: 24, style: .circular)
    // The close control has its own column, so the rest of the banner is one tap target.
    HStack(alignment: .top, spacing: 0) {
      Button(action: open) {
        HStack(spacing: 12) {
          FinanceNoticeIcon(
            symbol: line.symbol, size: 48, radius: 14, income: notice.kind == .income)
          VStack(alignment: .leading, spacing: 0) {
            Text(kicker)
              .ritmFont(11.5)
              .foregroundStyle(RitmTheme.muted)
              .lineLimit(1)
            Text(line.amount)
              .ritmFont(20, weight: .bold, tracking: -0.045)
              .monospacedDigit()
              .foregroundStyle(RitmTheme.text)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text(line.subtitle)
              .ritmFont(12)
              .foregroundStyle(RitmTheme.muted)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          RitmIcon(.chev)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(RitmTheme.muted)
            .frame(width: 16)
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.985))
      .accessibilityLabel(spoken)
      .accessibilityHint(store.text("Открыть в разделе «Финансы»", "Open in Finance"))
      VStack(alignment: .trailing, spacing: 0) {
        Text(store.text("Сейчас", "Now"))
          .ritmFont(11)
          .foregroundStyle(RitmTheme.muted)
          .padding(.trailing, 4)
          .accessibilityHidden(true)
        Spacer(minLength: 0)
        Button(action: close) {
          RitmIcon(.close)
            .font(.system(size: 20))
            .foregroundStyle(RitmTheme.muted)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .accessibilityLabel(store.text("Закрыть", "Close"))
      }
      .padding(.vertical, 10)
      .padding(.trailing, 10)
    }
    // As tall as its content: the right column's spacer must not stretch the banner.
    .fixedSize(horizontal: false, vertical: true)
    .background(RitmTheme.glassDense.opacity(0.6), in: shape)
    .ritmFloatingGlass(in: shape)
    .frame(maxWidth: 520)
    .onAppear {
      UIAccessibility.post(notification: .announcement, argument: spoken)
    }
  }
}
