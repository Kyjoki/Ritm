import XCTest

@testable import RitmCore

final class WalletStateTests: XCTestCase {
  private let received = "2026-03-15T09:30:00Z"

  private func purchase(
    _ merchant: String = "Zeta Market", amount: Int = 150_000, card: String? = nil
  ) -> WalletPurchase {
    WalletPurchase(
      id: WalletPurchase.makeID(
        date: "2026-03-14", amountMinor: amount, currency: .KZT, merchant: merchant, card: card),
      merchant: merchant, amountMinor: amount, currency: .KZT, card: card, date: "2026-03-14",
      receivedAt: received)
  }

  func testReceivingAddsOnceAndSuggestsFromMemory() {
    let learned = WalletState()
      .receiving(purchase("Zeta Market")).state
      .confirming(id: purchase("Zeta Market").id, category: "Продукты", at: received)
    let next = learned.receiving(purchase("Zeta Market", amount: 90_000))
    XCTAssertTrue(next.added)
    XCTAssertEqual(next.state.pending.first?.suggestedCategory, "Продукты")
    XCTAssertTrue(next.state.allHaveCategory)
  }

  func testConfirmedAndSkippedPurchasesDoNotComeBack() {
    let first = purchase("Zeta Market")
    let second = purchase("Lumen Cafe", amount: 20_000)
    var state = WalletState().receiving(first).state.receiving(second).state
    state = state.confirming(id: first.id, category: "Продукты", at: received)
      .skipping(id: second.id)
    XCTAssertTrue(state.pending.isEmpty)
    XCTAssertFalse(state.receiving(first).added)
    XCTAssertFalse(state.receiving(second).added)
  }

  func testKnownIDsAreCappedKeepingTheNewest() {
    var state = WalletState()
    for index in 0..<(WalletState.maxKnownIDs + 5) {
      let item = purchase("Shop \(index)x", amount: 100 + index)
      state = state.receiving(item).state.skipping(id: item.id)
    }
    XCTAssertEqual(state.knownIDs.count, WalletState.maxKnownIDs)
    let oldest = purchase("Shop 0x", amount: 100)
    XCTAssertTrue(state.receiving(oldest).added)
    let newest = purchase("Shop \(WalletState.maxKnownIDs + 4)x", amount: 100 + WalletState.maxKnownIDs + 4)
    XCTAssertFalse(state.receiving(newest).added)
  }

  func testSettingCategoryDoesNotTeachUntilConfirmed() {
    let item = purchase("Lumen Cafe")
    var state = WalletState().receiving(item).state.settingCategory("Кафе", for: item.id)
    XCTAssertEqual(state.pending.first?.suggestedCategory, "Кафе")
    XCTAssertNil(state.memory.suggest(merchant: "Lumen Cafe"))
    state = state.confirming(id: item.id, category: "Кафе", at: received)
    XCTAssertEqual(state.memory.suggest(merchant: "Lumen Cafe"), "Кафе")
  }

  func testClearingMemoryKeepsThePendingList() {
    let item = purchase("Lumen Cafe")
    let learned = WalletState().receiving(item).state
      .confirming(id: item.id, category: "Кафе", at: received)
    let waiting = purchase("Zeta Market")
    let state = learned.receiving(waiting).state.clearingMemory()
    XCTAssertEqual(state.memory.merchantCount, 0)
    XCTAssertEqual(state.pending.map(\.id), [waiting.id])
    XCTAssertEqual(state.knownIDs, [item.id])
  }

  func testStateSurvivesAJSONRoundTrip() throws {
    let item = purchase("Lumen Cafe")
    let state = WalletState().receiving(item).state
      .confirming(id: item.id, category: "Кафе", at: received)
      .receiving(purchase("Zeta Market")).state
    let data = try JSONEncoder().encode(state)
    XCTAssertEqual(try JSONDecoder().decode(WalletState.self, from: data), state)
  }

  func testTestPurchaseFlowsThroughTheLinkAndTeachesNothing() throws {
    let url = try XCTUnwrap(WalletLink.testURL(date: "2026-03-15"))
    let item = try WalletLink.parse(url, today: "2026-03-15", receivedAt: received).get()
    XCTAssertTrue(item.isTest)
    XCTAssertEqual(item.merchant, WalletLink.testMerchant)
    XCTAssertEqual(item.amountMinor, 100_000)
    XCTAssertEqual(item.currency, .KZT)
    XCTAssertFalse(purchase().isTest)

    let confirmed = WalletState().receiving(item).state
      .confirming(id: item.id, category: "Другое", at: received)
    XCTAssertEqual(confirmed.memory.merchantCount, 0)
    XCTAssertFalse(confirmed.receiving(item).added)
    XCTAssertTrue(confirmed.forgettingKnown(id: item.id).receiving(item).added)
  }

  func testBookingNeedsAnAccountInThePurchaseCurrency() {
    func account(_ currency: FinanceCurrency) -> FinanceEntry {
      FinanceEntry(
        id: "a-\(currency.rawValue)",
        input: .init(type: .account, currency: currency, valueMinor: 0, asOf: "2026-01-01"),
        createdAt: received, updatedAt: received)
    }
    let item = purchase()
    XCTAssertFalse(WalletBooking.hasAccount(for: item, in: []))
    XCTAssertFalse(WalletBooking.hasAccount(for: item, in: [account(.USD)]))
    XCTAssertTrue(WalletBooking.hasAccount(for: item, in: [account(.USD), account(.KZT)]))
  }
}
