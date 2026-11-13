import XCTest

@testable import RitmCore

final class WalletShortcutIntakeTests: XCTestCase {
  private let today = "2026-03-15"
  private let received = "2026-03-15T09:30:00Z"
  private let epoch = "11111111-1111-1111-1111-111111111111"
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func values(
    amount: String = "1 234,50 ₸", merchant: String = "Zeta Market", card: String = "Visa 4321",
    date: String = "14.03.2026, 18:20", at: String = "2026-03-14 18:20:09"
  ) -> WalletShortcutValues {
    .init(amount: amount, merchant: merchant, card: card, date: date, at: at)
  }

  private func gate(
    epoch: String? = nil, enabled: Bool = true, expires: Date? = nil, language: Language = .ru
  ) -> WalletAlertGate {
    .init(
      epoch: epoch ?? self.epoch, notificationsEnabled: enabled,
      expires: expires ?? now.addingTimeInterval(3600), language: language,
      timeZone: "Asia/Almaty")
  }

  private func purchase(_ values: WalletShortcutValues) throws -> WalletPurchase {
    try XCTUnwrap(
      WalletShortcutIntake.purchase(values, today: today, receivedAt: received))
  }

  // MARK: - Parsing

  func testParsesTheShortcutsTextsLikeTheFileLine() throws {
    let result = try purchase(values())
    XCTAssertEqual(result.merchant, "Zeta Market")
    XCTAssertEqual(result.amountMinor, 123_450)
    XCTAssertEqual(result.currency, .KZT)
    XCTAssertEqual(result.card, "•••• 4321")
    XCTAssertEqual(result.date, "2026-03-14")
    XCTAssertEqual(result.receivedAt, received)
  }

  func testIdEqualsTheIdOfTheSameLineFromPurchasesTxt() throws {
    let line =
      "ritm://add?amount=1 234,50 ₸&merchant=Zeta Market&card=Visa 4321"
      + "&date=14.03.2026, 18:20&at=2026-03-14 18:20:09"
    let fromFile = try XCTUnwrap(
      WalletFileImport.parse(text: line, today: today, receivedAt: received).purchases.first)
    XCTAssertEqual(try purchase(values()).id, fromFile.id)
  }

  func testIdEqualsTheFileIdWhenThereIsNoTime() throws {
    let line = "ritm://add?amount=900&merchant=Кофейня «Люмен»&card=Orbit Gold&date=2026-03-13&at="
    let fromFile = try XCTUnwrap(
      WalletFileImport.parse(text: line, today: today, receivedAt: received).purchases.first)
    let direct = try purchase(
      values(amount: "900", merchant: "Кофейня «Люмен»", card: "Orbit Gold", date: "2026-03-13", at: ""))
    XCTAssertEqual(direct.id, fromFile.id)
  }

  func testTheFileImportAfterTheIntentIsAllDuplicates() throws {
    let recorded = try purchase(values())
    let state = WalletState().receiving(recorded)
    XCTAssertTrue(state.added)
    let line =
      "ritm://add?amount=1 234,50 ₸&merchant=Zeta Market&card=Visa 4321"
      + "&date=14.03.2026, 18:20&at=2026-03-14 18:20:09"
    let file = WalletFileImport.parse(text: line, today: today, receivedAt: received)
    let imported = state.state.receiving(file: file.purchases)
    XCTAssertEqual(imported.receipt.added, 0)
    XCTAssertEqual(imported.receipt.duplicates, 1)
    XCTAssertEqual(imported.state.pending.count, 1)
  }

  func testTheSameValuesTwiceAreOnePurchase() throws {
    let state = WalletState().receiving(try purchase(values())).state
    XCTAssertFalse(state.receiving(try purchase(values())).added)
  }

  func testDifferentTimesAreDifferentPurchases() throws {
    XCTAssertNotEqual(
      try purchase(values(at: "2026-03-14 18:20:09")).id,
      try purchase(values(at: "2026-03-14 19:00:00")).id)
  }

  func testStructuralCharactersStayInsideTheValue() throws {
    let result = try purchase(values(merchant: "AT&T = A+B #1 100%"))
    XCTAssertEqual(result.merchant, "AT&T = A+B #1 100%")
    XCTAssertEqual(result.amountMinor, 123_450)
  }

  func testLineBreaksInAValueDoNotMakeAnotherPurchase() throws {
    let result = try purchase(values(merchant: "Zeta\nMarket"))
    XCTAssertEqual(result.merchant, "Zeta Market")
    XCTAssertEqual(result.amountMinor, 123_450)
  }

  func testMissingAmountOrMerchantIsNotAPurchase() {
    XCTAssertNil(WalletShortcutIntake.purchase(values(amount: ""), today: today, receivedAt: received))
    XCTAssertNil(WalletShortcutIntake.purchase(values(amount: "abc"), today: today, receivedAt: received))
    XCTAssertNil(WalletShortcutIntake.purchase(values(merchant: "  "), today: today, receivedAt: received))
  }

  func testEmptyOptionalTextsFallBackToToday() throws {
    let result = try purchase(values(card: "", date: "", at: ""))
    XCTAssertNil(result.card)
    XCTAssertEqual(result.date, today)
  }

  // MARK: - Gate and notification

  func testNoticeIsPlannedForAnOptedInAccount() throws {
    let recorded = try purchase(values())
    let plan = try XCTUnwrap(
      WalletShortcutPolicy.notice(for: recorded, gate: gate(), epoch: epoch, now: now))
    XCTAssertNil(plan.fireDate)
    XCTAssertEqual(plan.destination, .wallet(id: recorded.id))
    XCTAssertEqual(plan.title, "Новая покупка")
    XCTAssertTrue(plan.body.contains("Zeta Market"))
    XCTAssertEqual(
      plan, WalletNotificationPlanner.plan(
        purchase: recorded, language: .ru, accountEpoch: epoch, until: gate().expires))
  }

  func testNoOptInMeansNoNotice() throws {
    let recorded = try purchase(values())
    XCTAssertNil(
      WalletShortcutPolicy.notice(
        for: recorded, gate: gate(enabled: false), epoch: epoch, now: now))
  }

  func testNoGateMeansNoNotice() throws {
    XCTAssertNil(
      WalletShortcutPolicy.notice(for: try purchase(values()), gate: nil, epoch: epoch, now: now))
  }

  func testAnotherEpochMeansNoNotice() throws {
    let recorded = try purchase(values())
    XCTAssertNil(
      WalletShortcutPolicy.notice(
        for: recorded, gate: gate(epoch: "old-account"), epoch: epoch, now: now))
  }

  func testEndedSessionMeansNoNotice() throws {
    let recorded = try purchase(values())
    XCTAssertNil(
      WalletShortcutPolicy.notice(
        for: recorded, gate: gate(expires: now.addingTimeInterval(-1)), epoch: epoch, now: now))
  }

  func testTestPurchaseNeverNotifies() throws {
    let test = try purchase(
      values(amount: "1000", merchant: WalletLink.testMerchant, card: WalletLink.testCard))
    XCTAssertTrue(test.isTest)
    XCTAssertNil(WalletShortcutPolicy.notice(for: test, gate: gate(), epoch: epoch, now: now))
  }

  func testRecordingNeedsTheCurrentAccountEpoch() {
    XCTAssertTrue(WalletShortcutPolicy.mayRecord(gate: gate(), epoch: epoch))
    XCTAssertFalse(WalletShortcutPolicy.mayRecord(gate: nil, epoch: epoch))
    XCTAssertFalse(WalletShortcutPolicy.mayRecord(gate: gate(epoch: "old-account"), epoch: epoch))
  }

  func testEnglishAccountGetsAnEnglishNotice() throws {
    let plan = try XCTUnwrap(
      WalletShortcutPolicy.notice(
        for: try purchase(values()), gate: gate(language: .en), epoch: epoch, now: now))
    XCTAssertEqual(plan.title, "New purchase")
  }

  func testGateRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(gate())
    XCTAssertEqual(try JSONDecoder().decode(WalletAlertGate.self, from: data), gate())
  }
}
