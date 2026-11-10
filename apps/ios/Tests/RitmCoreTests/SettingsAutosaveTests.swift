import Foundation
import XCTest

@testable import RitmCore

final class SettingsPatchTests: XCTestCase {
  private let base = AccountSettings(
    displayName: "Максим", email: "a@b.kz", theme: .dark, language: .ru,
    timeZone: "Asia/Almaty", notifications: true, dailyBriefing: false,
    workDayStart: "09:00", workDayEnd: "21:00")

  func testEncodesOnlyTheChangedFields() throws {
    let patch = AccountSettingsPatch(theme: .light, notifications: false)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["theme", "notifications"])
    XCTAssertEqual(object["theme"] as? String, "light")
    XCTAssertEqual(object["notifications"] as? Bool, false)
  }

  func testDiffListsOnlyDifferentFields() {
    var changed = base
    changed.language = .en
    changed.workDayEnd = "20:00"
    let patch = AccountSettingsPatch.diff(from: base, to: changed)
    XCTAssertEqual(patch.fields, [.language, .workDayEnd])
    XCTAssertEqual(patch.applied(to: base), changed)
    XCTAssertTrue(AccountSettingsPatch.diff(from: base, to: base).isEmpty)
  }

  func testOverlayTakesTheNewerValueAndKeepsTheRest() {
    let older = AccountSettingsPatch(displayName: "A", theme: .light)
    let newer = AccountSettingsPatch(displayName: "B", language: .en)
    let merged = older.overlaid(by: newer)
    XCTAssertEqual(merged.displayName, "B")
    XCTAssertEqual(merged.theme, .light)
    XCTAssertEqual(merged.language, .en)
  }

  func testRemovingAndKeepingSplitAPatch() {
    let patch = AccountSettingsPatch(displayName: "A", email: "x@y.kz", dailyBriefing: true)
    XCTAssertEqual(patch.removing([.email]).fields, [.displayName, .dailyBriefing])
    XCTAssertEqual(patch.keeping([.email]), AccountSettingsPatch(email: "x@y.kz"))
  }

  func testClientSendsAPartialPatchAndRejectsAnEmptyOne() async throws {
    var saved = base
    saved.theme = .light
    let json = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
    let transport = StubTransport([StubReply(json: json)])
    let client = try APIClient(transport: transport)
    let result = try await client.patchSettings(AccountSettingsPatch(theme: .light))
    XCTAssertEqual(result.theme, .light)
    let requests = await transport.requests()
    XCTAssertEqual(requests[0].httpMethod, "PATCH")
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["theme"])
    do {
      _ = try await client.patchSettings(AccountSettingsPatch())
      XCTFail("An empty patch must not be sent")
    } catch {
      let count = await transport.requests().count
      XCTAssertEqual(count, 1)
    }
  }
}

final class SettingsValidationTests: XCTestCase {
  private let base = AccountSettings(displayName: "Максим", workDayStart: "09:00", workDayEnd: "21:00")

  func testNameIsTrimmedAndEmptyOrLongNamesAreHeld() {
    var draft = base
    draft.displayName = "  Лена  "
    var check = SettingsValidator.check(AccountSettingsPatch(displayName: "  Лена  "), in: draft)
    XCTAssertEqual(check.valid.displayName, "Лена")
    check = SettingsValidator.check(AccountSettingsPatch(displayName: "   "), in: base)
    XCTAssertTrue(check.valid.isEmpty)
    XCTAssertEqual(check.issues, [.emptyName])
    let long = String(repeating: "я", count: 61)
    check = SettingsValidator.check(AccountSettingsPatch(displayName: long), in: base)
    XCTAssertEqual(check.issues, [.nameTooLong])
  }

  func testEmailMayBeEmptyOtherwiseMustLookLikeAnAddress() {
    func issues(_ email: String) -> [SettingsIssue] {
      SettingsValidator.check(AccountSettingsPatch(email: email), in: base).issues
    }
    XCTAssertEqual(issues(""), [])
    XCTAssertEqual(issues(" me@example.com "), [])
    XCTAssertEqual(issues("me@example"), [.invalidEmail])
    XCTAssertEqual(issues("me example@x.kz"), [.invalidEmail])
    XCTAssertEqual(issues("@x.kz"), [.invalidEmail])
    XCTAssertEqual(issues("a@@x.kz"), [.invalidEmail])
  }

  func testWorkDayMustEndAfterItStartsAndBothFieldsAreHeldTogether() {
    var draft = base
    draft.workDayEnd = "08:00"
    let check = SettingsValidator.check(AccountSettingsPatch(workDayEnd: "08:00"), in: draft)
    XCTAssertTrue(check.valid.isEmpty)
    XCTAssertEqual(check.issues, [.workDayOrder])
    XCTAssertEqual(check.invalidFields, [.workDayStart, .workDayEnd])
    draft.workDayEnd = "09:00"
    XCTAssertEqual(
      SettingsValidator.check(AccountSettingsPatch(workDayEnd: "09:00"), in: draft).issues,
      [.workDayOrder])
  }

  func testUnknownTimeZoneIsHeld() {
    let check = SettingsValidator.check(AccountSettingsPatch(timeZone: "Mars/Olympus"), in: base)
    XCTAssertEqual(check.issues, [.unknownTimeZone])
    XCTAssertTrue(
      SettingsValidator.check(AccountSettingsPatch(timeZone: "Europe/Berlin"), in: base).issues
        .isEmpty)
  }

  func testMovingStartPastEndDragsEndAnHourAlong() {
    let moved = WorkDayBounds.settingStart("22:00", start: "09:00", end: "21:00")
    XCTAssertEqual(moved.start, "22:00")
    XCTAssertEqual(moved.end, "23:00")
    XCTAssertEqual(WorkDayBounds.settingStart("10:30", start: "09:00", end: "21:00").end, "21:00")
  }

  func testMovingEndBeforeStartDragsStartAnHourBack() {
    let moved = WorkDayBounds.settingEnd("08:00", start: "09:00", end: "21:00")
    XCTAssertEqual(moved.end, "08:00")
    XCTAssertEqual(moved.start, "07:00")
  }

  func testBoundsStayValidAtTheEdgesOfTheDay() {
    let late = WorkDayBounds.settingStart("23:59", start: "09:00", end: "21:00")
    XCTAssertTrue(WorkDayBounds.isValid(start: late.start, end: late.end))
    let early = WorkDayBounds.settingEnd("00:00", start: "09:00", end: "21:00")
    XCTAssertTrue(WorkDayBounds.isValid(start: early.start, end: early.end))
    XCTAssertEqual(early.start, "00:00")
    XCTAssertEqual(early.end, "00:01")
  }
}

final class SettingsAutosaveStateTests: XCTestCase {
  private let base = AccountSettings(
    displayName: "Максим", email: "", theme: .system, language: .ru, timeZone: "Asia/Almaty",
    notifications: false, dailyBriefing: false, workDayStart: "09:00", workDayEnd: "21:00")

  func testAnEditShowsAtOnceAndSendsOnlyThatField() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(language: .en))
    XCTAssertEqual(state.draft.language, .en)
    XCTAssertEqual(state.begin(), AccountSettingsPatch(language: .en))
    XCTAssertTrue(state.isSending)
  }

  func testOneRequestRunsAtATimeAndLaterEditsFollow() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(theme: .dark))
    XCTAssertNotNil(state.begin())
    state.edit(AccountSettingsPatch(dailyBriefing: true))
    XCTAssertNil(state.begin(), "a second request waits for the first")
    var saved = base
    saved.theme = .dark
    state.succeed(saved)
    XCTAssertEqual(state.begin(), AccountSettingsPatch(dailyBriefing: true))
    XCTAssertEqual(state.draft.theme, .dark)
  }

  func testChangesBeforeASendAreCoalescedIntoOneRequest() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(notifications: true))
    state.edit(AccountSettingsPatch(dailyBriefing: true))
    state.edit(AccountSettingsPatch(theme: .light, notifications: false))
    XCTAssertEqual(
      state.begin(), AccountSettingsPatch(theme: .light, dailyBriefing: true),
      "a switch flipped back is no change at all")
  }

  func testAValueEditedAgainWhileSendingIsNotOverwrittenByTheResponse() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(language: .en))
    _ = state.begin()
    state.edit(AccountSettingsPatch(language: .ru, workDayEnd: "20:00"))
    var saved = base
    saved.language = .en
    state.succeed(saved)
    XCTAssertEqual(state.draft.language, .ru)
    XCTAssertEqual(state.draft.workDayEnd, "20:00")
    XCTAssertEqual(state.begin(), AccountSettingsPatch(language: .ru, workDayEnd: "20:00"))
  }

  func testAFailureRevertsOnlyWhatWasInFlight() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(theme: .dark))
    _ = state.begin()
    state.edit(AccountSettingsPatch(dailyBriefing: true))
    let reverted = state.fail()
    XCTAssertEqual(reverted, [.theme])
    XCTAssertEqual(state.draft.theme, .system)
    XCTAssertTrue(state.draft.dailyBriefing, "a newer edit stays and is sent next")
    XCTAssertEqual(state.begin(), AccountSettingsPatch(dailyBriefing: true))
  }

  func testStaleServerDataNeverOverwritesPendingEdits() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(displayName: "Лена"))
    var polled = base
    polled.theme = .dark
    polled.displayName = "Старое"
    state.adopt(polled)
    XCTAssertEqual(state.draft.displayName, "Лена")
    XCTAssertEqual(state.draft.theme, .dark, "untouched fields follow the server")
    XCTAssertEqual(state.begin(), AccountSettingsPatch(displayName: "Лена"))
  }

  func testAPendingEditThatEqualsTheServerBecomesNoChange() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(theme: .dark))
    var polled = base
    polled.theme = .dark
    state.adopt(polled)
    XCTAssertNil(state.begin())
    XCTAssertFalse(state.hasPendingChanges)
  }

  func testInvalidValuesAreNeverSentAndRevertWhenTheOwnerLeaves() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(displayName: "   "))
    XCTAssertNil(state.begin())
    XCTAssertEqual(state.heldIssues, [.emptyName])
    state.edit(AccountSettingsPatch(theme: .light))
    XCTAssertEqual(state.begin(), AccountSettingsPatch(theme: .light), "valid changes still go")
    XCTAssertEqual(state.revertInvalid(), [.emptyName])
    XCTAssertEqual(state.draft.displayName, "Максим")
    XCTAssertTrue(state.heldIssues.isEmpty)
  }

  func testAnInvalidWorkdayIsHeldAndRestoredAsAPair() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(workDayEnd: "08:00"))
    XCTAssertNil(state.begin())
    XCTAssertEqual(state.heldIssues, [.workDayOrder])
    state.edit(AccountSettingsPatch(workDayEnd: "22:00"))
    XCTAssertEqual(state.begin(), AccountSettingsPatch(workDayEnd: "22:00"))
  }

  func testTheNameIsSentTrimmedAndTakesTheServerSpellingBack() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(displayName: "  Лена "))
    XCTAssertEqual(state.begin(), AccountSettingsPatch(displayName: "Лена"))
    var saved = base
    saved.displayName = "Лена"
    state.succeed(saved)
    XCTAssertEqual(state.draft.displayName, "Лена")
  }

  func testATrimOnlyChangeSendsNothing() {
    var state = SettingsAutosaveState(server: base)
    state.edit(AccountSettingsPatch(displayName: "Максим  "))
    XCTAssertNil(state.begin())
  }
}
