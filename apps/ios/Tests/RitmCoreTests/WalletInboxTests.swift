import XCTest

@testable import RitmCore

final class WalletInboxTests: XCTestCase {
  private let today = "2026-03-15"
  private let received = "2026-03-15T09:30:00Z"

  private func parse(_ query: String) -> Result<WalletPurchase, WalletLinkError> {
    WalletLink.parse(URL(string: "ritm://add?\(query)")!, today: today, receivedAt: received)
  }

  private func purchase(
    _ merchant: String = "Zeta Market", amount: Int = 150_000, date: String = "2026-03-14"
  ) -> WalletPurchase {
    WalletPurchase(
      id: WalletPurchase.makeID(
        date: date, amountMinor: amount, currency: .KZT, merchant: merchant, card: nil),
      merchant: merchant, amountMinor: amount, currency: .KZT, date: date, receivedAt: received)
  }

  // MARK: - Link

  func testParsesAFullLink() throws {
    let result = try parse("amount=1234.5&merchant=Zeta+Market&card=Orbit+Gold&date=2026-03-14")
      .get()
    XCTAssertEqual(result.amountMinor, 123_450)
    XCTAssertEqual(result.currency, .KZT)
    XCTAssertEqual(result.merchant, "Zeta Market")
    XCTAssertEqual(result.card, "Orbit Gold")
    XCTAssertEqual(result.date, "2026-03-14")
    XCTAssertEqual(result.receivedAt, received)
    XCTAssertNil(result.suggestedCategory)
  }

  func testPlusIsASpaceButEncodedPlusIsKept() throws {
    XCTAssertEqual(try parse("amount=10&merchant=Lumen+Cafe").get().merchant, "Lumen Cafe")
    XCTAssertEqual(try parse("amount=10&merchant=Lumen%20Cafe").get().merchant, "Lumen Cafe")
    XCTAssertEqual(try parse("amount=10&merchant=A%2BB+Shop").get().merchant, "A+B Shop")
  }

  func testRejectsWrongSchemeAndAction() {
    let other = URL(string: "https://add?amount=10&merchant=X")!
    XCTAssertEqual(
      WalletLink.parse(other, today: today, receivedAt: received), .failure(.wrongScheme))
    let remove = URL(string: "ritm://remove?amount=10&merchant=X")!
    XCTAssertEqual(
      WalletLink.parse(remove, today: today, receivedAt: received), .failure(.wrongAction))
  }

  func testMissingAndInvalidFields() {
    XCTAssertEqual(parse("merchant=X"), .failure(.missingAmount))
    XCTAssertEqual(parse("amount=&merchant=X"), .failure(.missingAmount))
    XCTAssertEqual(parse("amount=abc&merchant=X"), .failure(.invalidAmount))
    XCTAssertEqual(parse("amount=0&merchant=X"), .failure(.invalidAmount))
    XCTAssertEqual(parse("amount=10"), .failure(.missingMerchant))
    XCTAssertEqual(parse("amount=10&merchant=+%20+"), .failure(.missingMerchant))
  }

  func testTooLargeAmountAndTooLongLink() {
    XCTAssertEqual(parse("amount=99999999999&merchant=X"), .failure(.tooLarge))
    XCTAssertEqual(parse("amount=10&merchant=" + String(repeating: "a", count: 5_000)), .failure(.tooLarge))
  }

  func testMerchantIsTrimmedCollapsedAndCappedAt80() throws {
    let spaced = try parse("amount=10&merchant=%20%20Orbit%0A%20%20%20Taxi%20%20").get()
    XCTAssertEqual(spaced.merchant, "Orbit Taxi")
    let long = try parse("amount=10&merchant=" + String(repeating: "a", count: 200)).get()
    XCTAssertEqual(long.merchant.count, 80)
  }

  func testDateFallsBackToTodayAndAcceptsCommonFormats() throws {
    XCTAssertEqual(try parse("amount=10&merchant=X").get().date, today)
    XCTAssertEqual(try parse("amount=10&merchant=X&date=garbage").get().date, today)
    XCTAssertEqual(try parse("amount=10&merchant=X&date=2026-02-30").get().date, today)
    XCTAssertEqual(try parse("amount=10&merchant=X&date=14.03.2026").get().date, "2026-03-14")
    XCTAssertEqual(
      try parse("amount=10&merchant=X&date=2026-03-13T22:10:00%2B05:00").get().date, "2026-03-13")
  }

  func testCardDigitsAreNeverKept() throws {
    XCTAssertEqual(
      try parse("amount=10&merchant=X&card=4111%201111%201111%201234").get().card, "•••• 1234")
    XCTAssertEqual(try parse("amount=10&merchant=X&card=Orbit+Gold+5678").get().card, "•••• 5678")
    XCTAssertEqual(try parse("amount=10&merchant=X&card=Visa+2").get().card, "Visa 2")
    XCTAssertNil(try parse("amount=10&merchant=X&card=").get().card)
    XCTAssertEqual(
      try parse("amount=10&merchant=X&card=" + String(repeating: "n", count: 90)).get().card?.count,
      40)
  }

  func testTemplateShowsAllPlaceholders() {
    for language in Language.allCases {
      XCTAssertEqual(
        WalletLink.template(language: language),
        "ritm://add?amount=<Amount>&merchant=<Merchant>&card=<Card>&date=<Date>")
    }
  }

  // MARK: - Amounts

  func testParsesTheAmountFormatsShortcutsSends() {
    let cases: [(String, Int, FinanceCurrency)] = [
      ("1234.5", 123_450, .KZT),
      ("1 234,50", 123_450, .KZT),
      ("₸1,234.50", 123_450, .KZT),
      ("1 234,50 ₸", 123_450, .KZT),
      ("KZT 1234.50", 123_450, .KZT),
      ("-1234.50", 123_450, .KZT),
      ("$12.99", 1_299, .USD),
      ("12,99 €", 1_299, .EUR),
      ("1.234.567,89 ₽", 123_456_789, .RUB),
      ("1 234 567", 123_456_700, .KZT),
      ("1,234", 123_400, .KZT),
      ("99 RUB", 9_900, .RUB),
    ]
    for (text, minor, currency) in cases {
      let parsed = WalletLink.parseAmount(text, defaultCurrency: .KZT)
      XCTAssertEqual(parsed?.minor, minor, text)
      XCTAssertEqual(parsed?.currency, currency, text)
    }
  }

  func testRejectsZeroGarbageAndOversizedAmounts() {
    let bad = [
      "", "0", "-", "-0,00", "abc", "12 abc", "1.2.3,4", "12,9999", "12 99", "$12 €", "5€30",
      "10000000000.01", "99999999999999999999",
    ]
    for text in bad {
      XCTAssertNil(WalletLink.parseAmount(text, defaultCurrency: .KZT), text)
    }
    XCTAssertEqual(WalletLink.parseAmount("10000000000", defaultCurrency: .KZT)?.minor, 1_000_000_000_000)
  }

  func testDefaultCurrencyIsUsedWithoutAMark() {
    XCTAssertEqual(WalletLink.parseAmount("5", defaultCurrency: .USD)?.currency, .USD)
  }

  // MARK: - Identity

  func testIDIsStableAndSensitiveToEveryPart() throws {
    let a = try parse("amount=10&merchant=Zeta+Market&card=Orbit&date=2026-03-14").get()
    let b = try parse("amount=10&merchant=ZETA+MARKET+0123+ALMATY+KZ&card=Orbit&date=2026-03-14")
      .get()
    XCTAssertEqual(a.id, b.id)
    XCTAssertEqual(a.id.count, 17)
    XCTAssertEqual(a.id, try parse("amount=10&merchant=Zeta+Market&card=Orbit&date=2026-03-14").get().id)
    for other in [
      "amount=11&merchant=Zeta+Market&card=Orbit&date=2026-03-14",
      "amount=10&merchant=Zeta+Shop&card=Orbit&date=2026-03-14",
      "amount=10&merchant=Zeta+Market&card=Nova&date=2026-03-14",
      "amount=10&merchant=Zeta+Market&card=Orbit&date=2026-03-13",
      "amount=%2410&merchant=Zeta+Market&card=Orbit&date=2026-03-14",
    ] {
      XCTAssertNotEqual(a.id, try parse(other).get().id, other)
    }
  }

  // MARK: - Merchant memory

  func testNormaliseStripsTerminalsCitiesAndPunctuation() {
    XCTAssertEqual(MerchantMemory.normalise("KASPI MAGNUM 0123 ALMATY KZ"), "kaspi magnum")
    XCTAssertEqual(MerchantMemory.normalise("Zeta*Market #12 TS01234"), "zeta market")
    XCTAssertEqual(MerchantMemory.normalise("Lumen's  Cafe!!"), "lumens cafe")
    XCTAssertEqual(MerchantMemory.normalise("Кофейня  «Луна» Алматы KZ"), "кофейня луна")
    XCTAssertEqual(MerchantMemory.normalise("KZ"), "kz")
    XCTAssertEqual(MerchantMemory.normalise("  12345 "), "")
  }

  func testLearningIsImmutableAndSuggestsTheMostFrequentCategory() {
    let empty = MerchantMemory()
    let one = empty.learning(merchant: "Zeta Market", category: "Продукты", at: "2026-03-01")
    XCTAssertEqual(empty.merchantCount, 0)
    XCTAssertEqual(one.suggest(merchant: "ZETA MARKET 0042 ALMATY KZ"), "Продукты")
    let two = one.learning(merchant: "Zeta Market", category: "Дом", at: "2026-03-02")
      .learning(merchant: "Zeta Market", category: "Дом", at: "2026-03-03")
    XCTAssertEqual(two.suggest(merchant: "Zeta Market"), "Дом")
  }

  func testTieGoesToTheMostRecentCategory() {
    let memory = MerchantMemory()
      .learning(merchant: "Orbit Taxi", category: "Транспорт", at: "2026-03-01")
      .learning(merchant: "Orbit Taxi", category: "Путешествия", at: "2026-03-05")
    XCTAssertEqual(memory.suggest(merchant: "Orbit Taxi"), "Путешествия")
  }

  func testPrefixMatchSharesFirstTwoTokensAndStaysConservative() {
    let memory = MerchantMemory()
      .learning(merchant: "Zeta Market Express", category: "Продукты", at: "2026-03-01")
      .learning(merchant: "Nova", category: "Покупки", at: "2026-03-01")
    XCTAssertEqual(memory.suggest(merchant: "Zeta Market Central"), "Продукты")
    XCTAssertNil(memory.suggest(merchant: "Zeta Bank Central"))
    XCTAssertNil(memory.suggest(merchant: "Zeta"))
    XCTAssertNil(memory.suggest(merchant: "Nova Pharmacy"))
    let conflicting =
      memory
      .learning(merchant: "Zeta Market North", category: "Дом", at: "2026-03-02")
    XCTAssertNil(conflicting.suggest(merchant: "Zeta Market South"))
  }

  func testForgettingAndCapAt500DropsTheLeastRecent() {
    let one = MerchantMemory().learning(merchant: "Zeta Market", category: "Дом", at: "2026-03-01")
    XCTAssertNil(one.forgetting(merchant: "ZETA MARKET 99").suggest(merchant: "Zeta Market"))
    XCTAssertEqual(one.suggest(merchant: "Zeta Market"), "Дом")

    var memory = MerchantMemory()
    for index in 0..<(MerchantMemory.maxMerchants + 5) {
      let day = String(format: "2026-01-01T%06d", index)
      memory = memory.learning(merchant: "Shop \(Character(UnicodeScalar(97 + index % 26)!))\(index / 26 + 1)x", category: "Дом", at: day)
    }
    XCTAssertEqual(memory.merchantCount, MerchantMemory.maxMerchants)
  }

  func testMemoryRoundTripsThroughJSON() throws {
    let memory = MerchantMemory().learning(
      merchant: "Zeta Market", category: "Продукты", at: "2026-03-01")
    let data = try JSONEncoder().encode(memory)
    XCTAssertEqual(try JSONDecoder().decode(MerchantMemory.self, from: data), memory)
  }

  // MARK: - Inbox

  func testAddingFillsSuggestionAndPutsNewestFirst() {
    let memory = MerchantMemory().learning(
      merchant: "Zeta Market", category: "Продукты", at: "2026-03-01")
    let first = WalletInbox().adding(purchase("Zeta Market"), memory: memory, knownIDs: [])
    XCTAssertTrue(first.added)
    XCTAssertEqual(first.inbox.pending.first?.suggestedCategory, "Продукты")
    let second = first.inbox.adding(
      purchase("Lumen Cafe", amount: 90_000), memory: memory, knownIDs: [])
    XCTAssertEqual(second.inbox.pending.map(\.merchant), ["Lumen Cafe", "Zeta Market"])
    XCTAssertNil(second.inbox.pending.first?.suggestedCategory)
  }

  func testAddingIgnoresDuplicatesAndKnownIDs() {
    let item = purchase()
    let added = WalletInbox().adding(item, memory: MerchantMemory(), knownIDs: [])
    let again = added.inbox.adding(item, memory: MerchantMemory(), knownIDs: [])
    XCTAssertFalse(again.added)
    XCTAssertEqual(again.inbox, added.inbox)
    let skipped = WalletInbox().adding(item, memory: MerchantMemory(), knownIDs: [item.id])
    XCTAssertFalse(skipped.added)
    XCTAssertTrue(skipped.inbox.pending.isEmpty)
  }

  func testSuggestionsOutsideTheExpenseListAreDropped() {
    let memory = MerchantMemory().learning(
      merchant: "Zeta Market", category: "Зарплата", at: "2026-03-01")
    let result = WalletInbox().adding(purchase(), memory: memory, knownIDs: [])
    XCTAssertNil(result.inbox.pending.first?.suggestedCategory)
  }

  func testInboxKeepsOnlyTheNewest50() {
    var inbox = WalletInbox()
    for index in 1...60 {
      inbox = inbox.adding(
        purchase("Shop", amount: index * 100), memory: MerchantMemory(), knownIDs: []
      ).inbox
    }
    XCTAssertEqual(inbox.pending.count, 50)
    XCTAssertEqual(inbox.pending.first?.amountMinor, 6_000)
    XCTAssertEqual(inbox.pending.last?.amountMinor, 1_100)
  }

  func testRemovingAndSettingCategoryReturnNewValues() {
    let item = purchase()
    let inbox = WalletInbox().adding(item, memory: MerchantMemory(), knownIDs: []).inbox
    let changed = inbox.settingCategory("Кафе", for: item.id)
    XCTAssertEqual(changed.pending.first?.suggestedCategory, "Кафе")
    XCTAssertNil(inbox.pending.first?.suggestedCategory)
    XCTAssertEqual(changed.settingCategory("Кафе", for: "missing"), changed)
    XCTAssertTrue(changed.removing(id: item.id).pending.isEmpty)
    XCTAssertEqual(changed.removing(id: "missing"), changed)
  }

  func testInboxRoundTripsThroughJSON() throws {
    let inbox = WalletInbox().adding(purchase(), memory: MerchantMemory(), knownIDs: []).inbox
    let data = try JSONEncoder().encode(inbox)
    XCTAssertEqual(try JSONDecoder().decode(WalletInbox.self, from: data), inbox)
  }

  // MARK: - Entry

  func testExpenseEntryCarriesPurchaseFieldsWithoutCardDigits() throws {
    let parsed = try parse("amount=%2412.99&merchant=Lumen+Cafe&card=4111111111111111&date=2026-03-14")
      .get()
    let entry = WalletEntryBuilder.expense(from: parsed, category: "Кафе")
    XCTAssertEqual(entry.type, .expense)
    XCTAssertEqual(entry.currency, .USD)
    XCTAssertEqual(entry.amountMinor, 1_299)
    XCTAssertEqual(entry.date, "2026-03-14")
    XCTAssertEqual(entry.category, "Кафе")
    XCTAssertEqual(entry.note, "Apple Pay · Lumen Cafe")
    XCTAssertFalse(entry.note.contains("1111"))
  }

  func testExpenseNoteIsCappedAt400() {
    let long = WalletPurchase(
      id: "w1", merchant: String(repeating: "m", count: 900), amountMinor: 100, currency: .KZT,
      date: "2026-03-14", receivedAt: received)
    XCTAssertEqual(WalletEntryBuilder.expense(from: long, category: "Дом").note.count, 400)
  }
}
