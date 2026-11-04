import XCTest

@testable import RitmCore

final class WalletFileImportTests: XCTestCase {
  private let today = "2026-03-15"
  private let received = "2026-03-15T09:30:00Z"

  private func parse(_ text: String) -> (purchases: [WalletPurchase], skipped: Int) {
    WalletFileImport.parse(text: text, today: today, receivedAt: received)
  }

  private func line(_ merchant: String, amount: String = "1500", date: String = "2026-03-14")
    -> String
  {
    "ritm://add?amount=\(amount)&merchant=\(merchant)&card=Orbit Gold&date=\(date)"
  }

  func testReadsRawLinesAsShortcutsWritesThem() {
    let text = """
      ritm://add?amount=1 234,50 ₸&merchant=Zeta Market&card=Visa 4321&date=14.03.2026, 18:20
      ritm://add?amount=900&merchant=Кофейня «Люмен»&card=Orbit Gold&date=2026-03-13
      """
    let result = parse(text)
    XCTAssertEqual(result.skipped, 0)
    XCTAssertEqual(result.purchases.map(\.merchant), ["Zeta Market", "Кофейня «Люмен»"])
    XCTAssertEqual(result.purchases.map(\.amountMinor), [123_450, 90_000])
    XCTAssertEqual(result.purchases.first?.card, "•••• 4321")
    XCTAssertEqual(result.purchases.first?.date, "2026-03-14")
    XCTAssertEqual(result.purchases.last?.card, "Orbit Gold")
    XCTAssertEqual(result.purchases.first?.receivedAt, received)
  }

  func testAlreadyEncodedLinesStillWork() {
    let result = parse("ritm://add?amount=10&merchant=A%2BB%20Shop+Two&date=2026-03-14\n")
    XCTAssertEqual(result.purchases.first?.merchant, "A+B Shop Two")
    XCTAssertEqual(result.skipped, 0)
  }

  func testBareQueryLine() {
    let result = parse("amount=250&merchant=Lumen Cafe&date=2026-03-12\n?amount=5&merchant=Nord Kiosk")
    XCTAssertEqual(result.purchases.map(\.merchant), ["Lumen Cafe", "Nord Kiosk"])
    XCTAssertEqual(result.purchases.last?.date, today)
    XCTAssertEqual(result.skipped, 0)
  }

  func testToleratesBomCrlfCrAndWhitespace() {
    let text =
      "\u{FEFF}  \(line("Zeta Market"))  \r\n\r\n\t\(line("Lumen Cafe", amount: "20"))\r"
      + "\(line("Nord Kiosk", amount: "30"))\r\n   \r\n"
    let result = parse(text)
    XCTAssertEqual(result.purchases.map(\.merchant), ["Zeta Market", "Lumen Cafe", "Nord Kiosk"])
    XCTAssertEqual(result.skipped, 0)
  }

  func testDuplicateLinesWithATimeCountOnceAndAreNotSkipped() {
    let one = atLine("2026-10-30 14:05:09", merchant: "Zeta Market")
    let other = atLine("2026-10-30 15:00:00", merchant: "Zeta Market")
    let result = parse([one, one, other, one].joined(separator: "\n"))
    XCTAssertEqual(result.purchases.count, 2)
    XCTAssertEqual(result.skipped, 0)
  }

  func testGarbageLinesAreCountedAsSkipped() {
    let text = """
      hello world
      https://example.com/add?amount=10&merchant=X
      ritm://remove?amount=10&merchant=X
      ritm://add?amount=abc&merchant=X
      ritm://add?amount=10
      \(line("Zeta Market"))
      """
    let result = parse(text)
    XCTAssertEqual(result.purchases.count, 1)
    XCTAssertEqual(result.skipped, 5)
  }

  func testEmptyAndBlankTextGivesNothing() {
    XCTAssertTrue(parse("").purchases.isEmpty)
    XCTAssertEqual(parse("\n \r\n\t\n").skipped, 0)
  }

  func testLongLinesAreSkipped() {
    let long = "ritm://add?amount=10&merchant=" + String(repeating: "x", count: 1000)
    let result = parse("\(long)\n\(line("Zeta Market"))")
    XCTAssertEqual(result.purchases.map(\.merchant), ["Zeta Market"])
    XCTAssertEqual(result.skipped, 1)
  }

  func testOnlyTheLastFiveHundredLinesAreConsidered() {
    let lines = (1...520).map { "ritm://add?amount=\($0)&merchant=Shop&date=2026-03-14" }
    let result = parse(lines.joined(separator: "\n"))
    XCTAssertEqual(result.purchases.count, 500)
    XCTAssertEqual(result.purchases.first?.amountMinor, 21_00)
    XCTAssertEqual(result.purchases.last?.amountMinor, 520_00)
    XCTAssertEqual(result.skipped, 0)
  }

  func testPercentSignWithoutHexIsKeptAsLiteral() {
    let result = parse("ritm://add?amount=10&merchant=100% Juice&date=2026-03-14")
    XCTAssertEqual(result.purchases.first?.merchant, "100% Juice")
  }


  // MARK: - Same-day purchases and the `at` timestamp

  private func atLine(_ at: String, merchant: String = "Lumen Cafe") -> String {
    "ritm://add?amount=1200&merchant=\(merchant)&card=Orbit Gold&date=2026-10-30&at=\(at)"
  }

  func testTwoIdenticalPurchasesWithDifferentAtStayTwo() {
    let result = parse(
      "\(atLine("2026-10-30T09:05:09+05:00"))\n\(atLine("2026-10-30T13:40:12+05:00"))")
    XCTAssertEqual(result.purchases.count, 2)
    XCTAssertEqual(Set(result.purchases.map(\.id)).count, 2)
    XCTAssertEqual(result.purchases.map(\.date), ["2026-10-30", "2026-10-30"])
  }

  func testTheSameLineWithAtTwiceStaysOneAndKeepsItsIdAcrossReads() {
    let text = "\(atLine("2026-10-30 14:05:09"))\n\(atLine("2026-10-30 14:05:09"))"
    let first = parse(text)
    XCTAssertEqual(first.purchases.count, 1)
    XCTAssertEqual(parse(text).purchases.map(\.id), first.purchases.map(\.id))
  }

  func testAtFormatsNormaliseToTheSameStamp() {
    let same = [
      "2026-10-30T14:05:09+05:00", "2026-10-30T14:05:09Z", "2026-10-30 14:05:09",
      "2026-10-30T14:05:09.123+05:00", "30.10.2026, 14:05:09", "30 октября 2026 г. в 14:05:09",
      "30 окт. 2026, 14:05:09", "October 30, 2026 at 2:05:09 PM",
    ]
    let ids = Set(same.compactMap { parse(atLine($0)).purchases.first?.id })
    XCTAssertEqual(ids.count, 1, "\(same) should be one stamp")
    XCTAssertEqual(WalletTimestamp.normalise("30.10.2026, 14:05"), "2026-10-30 14:05:00")
    XCTAssertEqual(WalletTimestamp.normalise("October 30, 2026 12:05 AM"), "2026-10-30 00:05:00")
    XCTAssertEqual(WalletTimestamp.normalise("October 30, 2026 12:05 PM"), "2026-10-30 12:05:00")
  }

  func testUnparseableAtIsKeptAsTrimmedTextCutTo40() {
    XCTAssertEqual(WalletTimestamp.normalise("  yesterday evening "), "yesterday evening")
    XCTAssertEqual(WalletTimestamp.normalise(String(repeating: "x", count: 90)).count, 40)
    XCTAssertEqual(WalletTimestamp.normalise("2026-10-30"), "2026-10-30")
    let a = parse(atLine("evening")).purchases
    let b = parse(atLine("morning")).purchases
    XCTAssertNotEqual(a.first?.id, b.first?.id)
  }

  func testAtSuppliesTheDateWhenDateIsMissing() {
    let result = parse("ritm://add?amount=10&merchant=Lumen Cafe&at=2026-10-29T08:00:00+05:00")
    XCTAssertEqual(result.purchases.first?.date, "2026-10-29")
  }

  func testATimeInsideDateAlsoSeparatesPurchases() {
    let early = "ritm://add?amount=10&merchant=Lumen Cafe&date=30.10.2026, 09:00:01"
    let late = "ritm://add?amount=10&merchant=Lumen Cafe&date=30.10.2026, 17:30:00"
    let result = parse("\(early)\n\(late)\n\(early)")
    XCTAssertEqual(result.purchases.count, 2)
    XCTAssertEqual(result.purchases.first?.date, "2026-10-30")
  }

  func testIdenticalLinesWithoutAnyTimeAreSeparatePurchases() {
    let one = line("Zeta Market")
    let text = "\(one)\n\(one)\n\(one)"
    let result = parse(text)
    XCTAssertEqual(result.purchases.count, 3)
    // Reading again, or after more lines were appended, brings back the same ids.
    XCTAssertEqual(parse(text).purchases.map(\.id), result.purchases.map(\.id))
    XCTAssertEqual(
      Array(parse(text + "\n" + line("Lumen Cafe")).purchases.prefix(3).map(\.id)),
      result.purchases.map(\.id))
  }

  func testOldLinesWithoutAtKeepTheirOldIds() throws {
    let url = try XCTUnwrap(URL(string: "ritm://add?amount=1500&merchant=Zeta%20Market&date=2026-03-14"))
    let parsed = try WalletLink.parse(url, today: today, receivedAt: received).get()
    XCTAssertEqual(
      parsed.id,
      WalletPurchase.makeID(
        date: "2026-03-14", amountMinor: 150_000, currency: .KZT, merchant: "Zeta Market",
        card: nil))
    XCTAssertEqual(
      WalletPurchase.makeID(
        date: "d", amountMinor: 1, currency: .KZT, merchant: "m", card: nil, at: nil),
      WalletPurchase.makeID(date: "d", amountMinor: 1, currency: .KZT, merchant: "m", card: nil))
  }

  // MARK: - Into the inbox

  func testFileReceiptAddsOncePerPurchaseAndNeverReturnsKnownOnes() {
    let parsed = parse("\(line("Zeta Market"))\n\(line("Lumen Cafe", amount: "20"))").purchases
    let first = WalletState().receiving(file: parsed)
    XCTAssertEqual(first.receipt, WalletState.FileReceipt(added: 2, duplicates: 0, overflow: 0))
    XCTAssertEqual(first.state.pending.map(\.merchant), ["Lumen Cafe", "Zeta Market"])

    let confirmed = first.state.confirming(id: parsed[0].id, category: "Продукты", at: received)
      .skipping(id: parsed[1].id)
    let again = confirmed.receiving(file: parsed)
    XCTAssertEqual(again.receipt, WalletState.FileReceipt(added: 0, duplicates: 2, overflow: 0))
    XCTAssertTrue(again.state.pending.isEmpty)
  }

  func testFileReceiptNeverDropsPendingWhenTheInboxIsFull() {
    let lines = (1...(WalletInbox.capacity + 3)).map {
      "ritm://add?amount=\($0)&merchant=Shop&date=2026-03-14"
    }
    let parsed = parse(lines.joined(separator: "\n")).purchases
    let result = WalletState().receiving(file: parsed)
    XCTAssertEqual(result.state.pending.count, WalletInbox.capacity)
    XCTAssertEqual(result.receipt.added, WalletInbox.capacity)
    XCTAssertEqual(result.receipt.overflow, 3)
    let again = result.state.receiving(file: parsed)
    XCTAssertEqual(again.receipt.added, 0)
    XCTAssertEqual(again.receipt.duplicates, WalletInbox.capacity)
    XCTAssertEqual(again.receipt.overflow, 3)
  }

  func testRecognisesTheCopiesShortcutsMakesOfThePurchasesFile() {
    for name in ["purchases.txt", "Purchases.TXT", "purchases 2.txt", "purchases-1.txt", "purchases_3.txt",
      "purchases.txt.txt", " purchases.txt", "purchases.txt "]
    {
      XCTAssertTrue(WalletFileImport.isPurchasesFileName(name), name)
    }
    for name in ["purchases.rtf", "old purchases.txt", "purchases.txt.icloud", "purchases", "notes.txt"] {
      XCTAssertFalse(WalletFileImport.isPurchasesFileName(name), name)
    }
  }

  /// The exact line the owner's «Транзакция» automation wrote on 2026-11-04 (Kaspi Gold, iOS 27).
  func testReadsTheLineTheOwnersAutomationWrote() {
    let line =
      "ritm://add?amount=₸650,00&merchant=Ip Kudabaev&card=Kaspi Gold&date=2026-11-04T12:13:24+05:00&at=2026-11-04T12:13:24+05:00"
    let result = WalletFileImport.parse(
      text: line + "\n", today: "2026-11-04", receivedAt: "2026-11-04T12:30:00Z")
    XCTAssertEqual(result.skipped, 0)
    XCTAssertEqual(result.purchases.count, 1)
    XCTAssertEqual(result.purchases.first?.amountMinor, 65_000)
    XCTAssertEqual(result.purchases.first?.currency, .KZT)
    XCTAssertEqual(result.purchases.first?.merchant, "Ip Kudabaev")
    XCTAssertEqual(result.purchases.first?.date, "2026-11-04")
  }
}
