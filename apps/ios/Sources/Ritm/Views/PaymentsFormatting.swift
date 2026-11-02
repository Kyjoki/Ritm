import RitmCore
import SwiftUI

/// Words and dates of the recurring payments, in the language of the account.
extension FinanceFormat {
  /// «5 нояб.»; the year is added when it is not the current one.
  func paymentDate(_ key: String, today: String) -> String {
    let sameYear = key.prefix(4) == today.prefix(4)
    return date(key, template: sameYear ? "d MMM" : "d MMM yyyy")
  }

  func statusName(_ status: PaymentStatus) -> String {
    switch status {
    case .planned: text("запланирован", "scheduled")
    case .today: text("сегодня", "today")
    case .overdue: text("просрочен", "overdue")
    case .paused: text("на паузе", "paused")
    }
  }

  func periodName(_ period: PaymentPeriod) -> String {
    switch period {
    case .week: text("еженедельно", "weekly")
    case .month: text("ежемесячно", "monthly")
    case .year: text("ежегодно", "yearly")
    }
  }

  func periodTitle(_ period: PaymentPeriod) -> String {
    switch period {
    case .week: text("Неделя", "Week")
    case .month: text("Месяц", "Month")
    case .year: text("Год", "Year")
    }
  }

  func reminderName(_ days: Int) -> String {
    switch days {
    case 0: text("В день платежа", "On the day")
    case 1: text("За 1 день", "1 day before")
    default: text("За \(days) дня", "\(days) days before")
    }
  }

  /// «через 3 дн.» / «завтра» / «просрочен на 2 дн.»
  func relative(_ key: String, today: String) -> String {
    guard let days = PaymentDates.daysBetween(today, key) else { return "" }
    if days < 0 { return text("просрочен на \(-days) дн.", "\(-days) d overdue") }
    if days == 0 { return text("сегодня", "today") }
    if days == 1 { return text("завтра", "tomorrow") }
    return text("через \(days) дн.", "in \(days) d")
  }

  func accountName(_ id: String) -> String? {
    guard let card = cards.first(where: { $0.id == id && $0.kind == .account }) else { return nil }
    return name(card)
  }
}

extension PaymentStatus {
  var tint: Color {
    switch self {
    case .overdue: RitmTheme.danger
    case .today: RitmTheme.ctaInk
    case .planned: RitmTheme.accentColor
    case .paused: RitmTheme.muted
    }
  }

  var fill: Color {
    switch self {
    case .overdue: RitmTheme.dangerSoft
    case .today: RitmTheme.accentColor
    case .planned: RitmTheme.soft
    case .paused: RitmTheme.field
    }
  }
}
