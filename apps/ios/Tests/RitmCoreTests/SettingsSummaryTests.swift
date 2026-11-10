import Foundation
import XCTest

@testable import RitmCore

final class SettingsSummaryTests: XCTestCase {
  /// 2026-01-15 12:00 UTC: winter, so Europe/Kyiv is UTC+2 and New York UTC-5.
  private let winter = Date(timeIntervalSince1970: 1_768_478_400)
  /// 2026-07-15 12:00 UTC: summer, Kyiv UTC+3, New York UTC-4.
  private let summer = Date(timeIntervalSince1970: 1_784_116_800)

  func testOffsetLabels() {
    XCTAssertEqual(SettingsTimeZones.offsetLabel("Asia/Almaty", at: winter), "UTC+5")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("Europe/Kyiv", at: winter), "UTC+2")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("Europe/Kyiv", at: summer), "UTC+3")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("America/New_York", at: winter), "UTC\u{2212}5")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("America/New_York", at: summer), "UTC\u{2212}4")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("Asia/Kolkata", at: winter), "UTC+5:30")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("UTC", at: winter), "UTC")
    XCTAssertEqual(SettingsTimeZones.offsetLabel("Europe/London", at: winter), "UTC+0")
  }

  func testRowValueUsesTheCityBeforeTheComma() {
    XCTAssertEqual(
      SettingsTimeZones.rowValue("Asia/Almaty", language: .ru, at: winter), "Алматы · UTC+5")
    XCTAssertEqual(
      SettingsTimeZones.rowValue("Asia/Almaty", language: .en, at: winter), "Almaty · UTC+5")
    XCTAssertEqual(SettingsTimeZones.rowValue("UTC", language: .ru, at: winter), "UTC")
  }

  func testAnUnlistedZoneOfTheAccountStaysSelectable() {
    let list = SettingsTimeZones.zones(including: "Asia/Tbilisi")
    XCTAssertEqual(list.first?.id, "Asia/Tbilisi")
    XCTAssertEqual(list.count, SettingsTimeZones.all.count + 1)
    XCTAssertEqual(SettingsTimeZones.zones(including: "UTC").count, SettingsTimeZones.all.count)
    XCTAssertEqual(
      SettingsTimeZones.rowValue("Asia/Tbilisi", language: .ru, at: winter), "Asia/Tbilisi · UTC+4")
  }

  func testPluralsAndSessions() {
    XCTAssertEqual(SettingsSummary.sessions(1, .ru), "1 сеанс")
    XCTAssertEqual(SettingsSummary.sessions(3, .ru), "3 сеанса")
    XCTAssertEqual(SettingsSummary.sessions(5, .ru), "5 сеансов")
    XCTAssertEqual(SettingsSummary.sessions(11, .ru), "11 сеансов")
    XCTAssertEqual(SettingsSummary.sessions(21, .ru), "21 сеанс")
    XCTAssertEqual(SettingsSummary.sessions(2, .en), "2 sessions")
  }

  func testDayRangeAndLeadTimes() {
    XCTAssertEqual(SettingsSummary.dayRange(start: "09:00", end: "21:00"), "09:00\u{2013}21:00")
    XCTAssertEqual(SettingsSummary.leadTime(0, .ru), "в момент начала")
    XCTAssertEqual(SettingsSummary.leadTime(15, .ru), "за 15 мин")
    XCTAssertEqual(SettingsSummary.leadSegment(0, .ru), "Сразу")
    XCTAssertEqual(SettingsSummary.leadSegment(60, .ru), "60")
    XCTAssertEqual(SettingsSummary.leadChoices, [0, 5, 10, 15, 30, 60])
  }

  func testNotificationsCountAndPermission() {
    var settings = AccountSettings()
    XCTAssertEqual(SettingsSummary.notificationsOn(settings), 0)
    settings.notifications = true
    settings.dailyBriefing = true
    XCTAssertEqual(SettingsSummary.notificationsOn(settings), 2)
    XCTAssertEqual(SettingsSummary.phonePermission(granted: true, .ru), SettingsTrailing("Разрешены", .ok))
    XCTAssertEqual(SettingsSummary.phonePermission(granted: false, .ru).tone, .warn)
    XCTAssertEqual(SettingsSummary.phonePermission(granted: nil, .ru).tone, .none)
  }

  func testGoogleSummary() {
    let ok = GoogleCalendarStatus(configured: true, status: .connected)
    XCTAssertEqual(SettingsSummary.google(status: ok, setup: nil, .ru), SettingsTrailing("Подключён", .ok))
    let stale = GoogleCalendarStatus(configured: true, status: .reauthRequired)
    XCTAssertEqual(SettingsSummary.google(status: stale, setup: nil, .ru).tone, .warn)
    let noClient = GoogleCalendarStatus(configured: false, status: .unconfigured)
    XCTAssertEqual(
      SettingsSummary.google(status: noClient, setup: nil, .ru), SettingsTrailing("Нужен клиент", .warn))
    let off = GoogleCalendarStatus(configured: true, status: .disconnected)
    XCTAssertEqual(SettingsSummary.google(status: off, setup: nil, .ru), SettingsTrailing("Не подключён"))
    let setup = GoogleOAuthSetup(
      configured: true, source: "saved", clientId: "x", hasClientSecret: true, redirectUri: nil)
    XCTAssertEqual(SettingsSummary.google(status: noClient, setup: setup, .en).text, "Not connected")
    XCTAssertEqual(SettingsSummary.google(status: nil, setup: nil, .ru).tone, .none)
  }

  func testTelegramProblemCodesAreWordedInBothLanguagesAndUnknownOnesAreNil() {
    XCTAssertEqual(
      SettingsSummary.telegramProblem("chat_unlinked", .ru), "Личный чат Telegram не привязан.")
    XCTAssertEqual(
      SettingsSummary.telegramProblem("scheduler_stale", .en),
      "The scheduler has not run for over five minutes.")
    XCTAssertNil(SettingsSummary.telegramProblem("something_new", .ru))
  }

  func testTelegramOpenAIAndSecuritySummaries() {
    XCTAssertEqual(
      SettingsSummary.telegram(TelegramStatus(configured: true, linked: true), .ru).tone, .ok)
    XCTAssertEqual(
      SettingsSummary.telegram(TelegramStatus(configured: true, linked: false), .ru),
      SettingsTrailing("Чат не привязан", .warn))
    XCTAssertEqual(
      SettingsSummary.telegram(TelegramStatus(configured: false, linked: false), .ru).text,
      "Не подключён")
    XCTAssertEqual(
      SettingsSummary.openAI(AIStatus(configured: true, model: "m", source: "saved"), .ru).text,
      "Ключ задан")
    XCTAssertEqual(
      SettingsSummary.openAI(AIStatus(configured: true, model: "m", source: "environment"), .ru).text,
      "На сервере")
    XCTAssertEqual(SettingsSummary.openAI(AIStatus(), .ru), SettingsTrailing("Нет ключа"))
    XCTAssertNil(SettingsSummary.security(totpEnabled: nil, .ru))
    XCTAssertEqual(SettingsSummary.security(totpEnabled: true, .ru), SettingsTrailing("2FA включена", .ok))
    XCTAssertEqual(SettingsSummary.security(totpEnabled: false, .en)?.tone, .warn)
  }
}
