import XCTest

@testable import RitmCore

final class FinanceCategoriesTests: XCTestCase {
  func testListsMatchTheApprovedDesign() {
    XCTAssertEqual(
      FinanceCategories.expense.map(\.label),
      [
        "Продукты", "Кафе", "Транспорт", "Дом", "Здоровье", "Покупки", "Развлечения", "Подарки",
        "Спорт", "Путешествия", "Образование", "Связь", "Одежда", "Красота", "Дети", "Питомцы",
        "Платежи", "Другое",
      ])
    XCTAssertEqual(
      FinanceCategories.income.map(\.label),
      ["Зарплата", "Подработка", "Подарок", "Проценты", "Возврат", "Продажа", "Другое"])
  }

  func testListsHaveNoDuplicates() {
    for list in [FinanceCategories.expense, FinanceCategories.income] {
      XCTAssertEqual(Set(list.map(\.label)).count, list.count)
      XCTAssertEqual(Set(list.map(\.english)).count, list.count)
    }
  }

  func testEveryCategoryHasADistinctSymbolExceptTheGiftAlias() {
    for list in [FinanceCategories.expense, FinanceCategories.income] {
      let symbols = list.filter { $0.label != "Подарок" }.map(\.symbol)
      XCTAssertEqual(Set(symbols).count, symbols.count)
    }
    let all = (FinanceCategories.expense + FinanceCategories.income).filter {
      $0.label != "Подарок" && $0.label != "Другое"
    }
    XCTAssertEqual(Set(all.map(\.symbol)).count, all.count)
    XCTAssertEqual(FinanceCategories.symbol(for: "Подарок"), FinanceCategories.symbol(for: "Подарки"))
  }

  func testUnknownOrEmptyFallsBackToOther() {
    XCTAssertEqual(FinanceCategories.symbol(for: nil), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: ""), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: "  "), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: "Кофе на вынос"), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: "Другое"), FinanceCategories.otherSymbol)
  }

  func testLookupIgnoresCaseAndSurroundingSpaces() {
    XCTAssertEqual(FinanceCategories.symbol(for: " кафе "), "cup.and.saucer")
    XCTAssertTrue(FinanceCategories.isKnown("Зарплата"))
    XCTAssertFalse(FinanceCategories.isKnown("Кофе"))
    XCTAssertFalse(FinanceCategories.isKnown(nil))
  }

  func testWebsOldCategoriesStillMap() {
    let old = [
      "Зарплата", "Подработка", "Подарок", "Проценты", "Продукты", "Кафе", "Транспорт", "Дом",
      "Здоровье", "Покупки", "Развлечения",
    ]
    for label in old {
      XCTAssertTrue(FinanceCategories.isKnown(label), label)
      XCTAssertNotEqual(FinanceCategories.symbol(for: label), FinanceCategories.otherSymbol, label)
    }
  }

  func testEnglishNames() {
    XCTAssertEqual(FinanceCategories.englishName(for: "Продукты"), "Groceries")
    XCTAssertEqual(FinanceCategories.englishName(for: "Своё"), "Своё")
  }

  func testMainAndMoreSplitTheListsInOrder() {
    XCTAssertEqual(
      FinanceCategories.expenseMain.map(\.label),
      ["Продукты", "Кафе", "Транспорт", "Развлечения", "Дом", "Образование", "Здоровье"])
    XCTAssertEqual(
      FinanceCategories.incomeMain.map(\.label),
      ["Зарплата", "Подработка", "Подарок", "Проценты"])
    XCTAssertEqual(
      FinanceCategories.incomeMore.map(\.label), ["Возврат", "Продажа", "Другое"])
    for (main, more, all) in [
      (FinanceCategories.expenseMain, FinanceCategories.expenseMore, FinanceCategories.expense),
      (FinanceCategories.incomeMain, FinanceCategories.incomeMore, FinanceCategories.income),
    ] {
      XCTAssertTrue(Set(main.map(\.label)).isDisjoint(with: more.map(\.label)))
      XCTAssertEqual(Set(main.map(\.label) + more.map(\.label)), Set(all.map(\.label)))
      XCTAssertEqual(main.count + more.count, all.count)
    }
    XCTAssertEqual(FinanceCategories.expenseMore.last?.label, "Другое")
  }

  func testNeedsMoreWhenTheStoredCategoryIsHiddenOrUnlisted() {
    XCTAssertFalse(FinanceCategories.needsMore(nil, income: false))
    XCTAssertFalse(FinanceCategories.needsMore("", income: true))
    XCTAssertFalse(FinanceCategories.needsMore("Кафе", income: false))
    XCTAssertFalse(FinanceCategories.needsMore(" Зарплата ", income: true))
    XCTAssertTrue(FinanceCategories.needsMore("Спорт", income: false))
    XCTAssertTrue(FinanceCategories.needsMore("Возврат", income: true))
    XCTAssertTrue(FinanceCategories.needsMore("Другое", income: false))
    XCTAssertTrue(FinanceCategories.needsMore("Кофе на вынос", income: false))
    XCTAssertTrue(FinanceCategories.needsMore("Спорт", income: true))
  }
}
