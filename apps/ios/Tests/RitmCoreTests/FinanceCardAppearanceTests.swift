import Foundation
import XCTest

@testable import RitmCore

final class FinanceCardAppearanceTests: XCTestCase {
  private func card(_ id: String, _ kind: FinanceCard.Kind = .account) -> FinanceCard {
    FinanceCard(id: id, kind: kind, currency: .KZT)
  }

  private var cards: [FinanceCard] {
    [card("a"), card("d1", .deposit), card("d2", .deposit), card("s", .stocks)]
  }

  func testEmptyLayoutKeepsDefaultOrder() {
    XCTAssertEqual(FinanceCardLayout().ordered(cards).map(\.id), ["a", "d1", "d2", "s"])
  }

  func testSavedOrderComesFirst() {
    let layout = FinanceCardLayout(order: ["s", "d2", "a", "d1"])
    XCTAssertEqual(layout.ordered(cards).map(\.id), ["s", "d2", "a", "d1"])
  }

  func testNewCardIsAppendedInDefaultOrder() {
    let layout = FinanceCardLayout(order: ["d1", "a"])
    XCTAssertEqual(layout.ordered(cards).map(\.id), ["d1", "a", "d2", "s"])
  }

  func testRemovedCardIsIgnored() {
    let layout = FinanceCardLayout(order: ["gone", "s", "a", "gone", "s"])
    XCTAssertEqual(layout.ordered(cards).map(\.id), ["s", "a", "d1", "d2"])
  }

  func testMovingUsesFinalIndexAndClamps() {
    let layout = FinanceCardLayout(order: ["a", "b", "c", "d"])
    XCTAssertEqual(layout.moving(from: 0, to: 2).order, ["b", "c", "a", "d"])
    XCTAssertEqual(layout.moving(from: 3, to: 0).order, ["d", "a", "b", "c"])
    XCTAssertEqual(layout.moving(from: 1, to: 99).order, ["a", "c", "d", "b"])
    XCTAssertEqual(layout.moving(from: 9, to: 0), layout)
  }

  func testAlignedListsExactlyTheCurrentCards() {
    let layout = FinanceCardLayout(order: ["gone", "s"], themes: ["gone": "rose", "a": "sand"])
    let aligned = layout.aligned(to: cards)
    XCTAssertEqual(aligned.order, ["s", "a", "d1", "d2"])
    XCTAssertEqual(aligned.themes, ["a": "sand"])
  }

  func testSettingThemeStoresItAndKeepsOthers() {
    let layout = FinanceCardLayout().setting(theme: .rose, for: "a").setting(theme: .forest, for: "s")
    XCTAssertEqual(layout.theme(for: cards[0], among: cards), .rose)
    XCTAssertEqual(layout.theme(for: cards[3], among: cards), .forest)
    let changed = layout.setting(theme: .sand, for: "a")
    XCTAssertEqual(changed.theme(for: cards[0], among: cards), .sand)
    XCTAssertEqual(changed.theme(for: cards[3], among: cards), .forest)
  }

  func testThemeFallsBackByKind() {
    let layout = FinanceCardLayout()
    XCTAssertEqual(layout.theme(for: cards[0], among: cards), .violet)
    XCTAssertEqual(layout.theme(for: cards[1], among: cards), .indigo)
    XCTAssertEqual(layout.theme(for: cards[2], among: cards), .plum)
    XCTAssertEqual(layout.theme(for: cards[3], among: cards), .teal)
    let second = [card("a"), card("usd")]
    XCTAssertEqual(layout.theme(for: second[1], among: second), .graphite)
  }

  func testUnknownSavedThemeFallsBack() {
    let layout = FinanceCardLayout(themes: ["a": "neon"])
    XCTAssertEqual(layout.theme(for: cards[0], among: cards), .violet)
  }

  func testResolvedThemesCoverEveryCard() {
    let layout = FinanceCardLayout().setting(theme: .rose, for: "d1")
    let resolved = layout.resolvedThemes(for: cards)
    XCTAssertEqual(resolved["d1"], .rose)
    XCTAssertEqual(resolved.count, 4)
  }

  func testPrunedDropsRemovedIds() {
    let layout = FinanceCardLayout(order: ["a", "x", "d1"], themes: ["x": "rose", "a": "sand"])
    let pruned = layout.pruned(to: ["a", "d1"])
    XCTAssertEqual(pruned.order, ["a", "d1"])
    XCTAssertEqual(pruned.themes, ["a": "sand"])
  }

  func testCodableRoundTrip() throws {
    let layout = FinanceCardLayout(order: ["s", "a"], themes: ["a": "forest"])
    let data = try JSONEncoder().encode(layout)
    XCTAssertEqual(try JSONDecoder().decode(FinanceCardLayout.self, from: data), layout)
  }

  func testThemesHaveEightStableRawValues() {
    XCTAssertEqual(
      FinanceCardTheme.allCases.map(\.rawValue),
      ["violet", "indigo", "plum", "teal", "graphite", "rose", "sand", "forest"])
  }
}
