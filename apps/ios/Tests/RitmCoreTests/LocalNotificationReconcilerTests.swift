import Foundation
import XCTest

@testable import RitmCore

@MainActor
final class LocalNotificationReconcilerTests: XCTestCase {
  private func plan(_ value: String, immediate: Bool = false) -> LocalNotificationPlan {
    LocalNotificationPlan(
      identifier: "ritm.account.reminder.\(value)",
      fireDate: immediate ? nil : Date(timeIntervalSince1970: 4_000_000_000),
      title: value, body: value, threadIdentifier: "test", categoryIdentifier: "test",
      destination: .day)
  }

  private func reconciler(_ center: FakeNotificationDriver) -> LocalNotificationReconciler {
    LocalNotificationReconciler(
      driver: center.driver, owns: { $0.hasPrefix(LocalNotificationNamespace.reminders) })
  }

  func testClearDuringAddCancelsLateCompletionAndPreservesRestAndForeignNotices() async {
    let center = FakeNotificationDriver(delayed: true)
    center.pending["ritm.workout.rest.w"] = plan("rest")
    center.delivered["external.notice"] = plan("external")
    let scheduler = reconciler(center)
    let task = Task { [self] in await scheduler.replace([plan("old")]) }
    await center.waitForAdds(1)
    scheduler.clear()
    center.finishNext()
    let accepted = await task.value
    XCTAssertTrue(accepted.isEmpty)
    XCTAssertEqual(Set(center.pending.keys), ["ritm.workout.rest.w"])
    XCTAssertEqual(Set(center.delivered.keys), ["external.notice"])
  }

  func testNewerPlanWinsWhenOlderOSAddFinishesLate() async {
    let center = FakeNotificationDriver(delayed: true)
    let scheduler = reconciler(center)
    let task = Task { [self] in await scheduler.replace([plan("old")]) }
    await center.waitForAdds(1)
    scheduler.setPlans([plan("new")])
    center.finishNext()
    await center.waitForAdds(2)
    center.finishNext()
    let accepted = await task.value
    XCTAssertTrue(accepted.isEmpty)
    XCTAssertEqual(center.pending.values.map(\.title), ["new"])
    XCTAssertEqual(center.adds.count, 2)
    XCTAssertNotEqual(center.adds[0], center.adds[1])
  }

  func testIdenticalImmediatePlanDuringAddIsAdoptedWithoutSecondBanner() async {
    let center = FakeNotificationDriver(delayed: true)
    let scheduler = reconciler(center)
    let notice = plan("wallet-like", immediate: true)
    let task = Task { await scheduler.replace([notice]) }
    await center.waitForAdds(1)
    scheduler.setPlans([notice])
    center.finishNext()
    let initial = await task.value
    XCTAssertEqual(initial, [notice.identifier])
    XCTAssertEqual(center.adds.count, 1)
    center.deliverPending()
    let repeated = await scheduler.replace([notice])
    XCTAssertEqual(repeated, [notice.identifier])
    XCTAssertEqual(center.adds.count, 1)
    XCTAssertEqual(center.delivered.count, 1)
  }

  func testRestartSweepAndChangedPlanOnlyRemoveOwnedIdentifiers() async {
    let center = FakeNotificationDriver()
    center.pending["ritm.account.reminder.previous-process"] = plan("old")
    center.pending["ritm.account.wallet.keep"] = plan("wallet")
    center.pending["ritm.workout.rest.keep"] = plan("rest")
    let scheduler = reconciler(center)
    let first = plan("one")
    let firstResult = await scheduler.replace([first])
    XCTAssertEqual(firstResult, [first.identifier])
    XCTAssertEqual(center.pending.count, 3)
    XCTAssertNil(center.pending["ritm.account.reminder.previous-process"])
    let second = plan("two")
    let secondResult = await scheduler.replace([second])
    XCTAssertEqual(secondResult, [second.identifier])
    XCTAssertEqual(center.pending.count, 3)
    XCTAssertTrue(center.pending.keys.contains("ritm.account.wallet.keep"))
    XCTAssertTrue(center.pending.keys.contains("ritm.workout.rest.keep"))
    let repeated = await scheduler.replace([second])
    XCTAssertEqual(repeated, [second.identifier])
    XCTAssertEqual(center.adds.count, 2)
  }

  func testFailedAddIsNotSuccessAndCanRetry() async {
    let center = FakeNotificationDriver()
    center.fails = true
    let scheduler = reconciler(center)
    let first = plan("retry")
    let failed = await scheduler.replace([first])
    XCTAssertTrue(failed.isEmpty)
    XCTAssertTrue(center.pending.isEmpty)
    center.fails = false
    let retried = await scheduler.replace([first])
    XCTAssertEqual(retried, [first.identifier])
    XCTAssertEqual(center.adds.count, 2)
  }

  func testClearingPersistedDeliveredNoticesOnlyAffectsOwnedNamespace() async {
    let center = FakeNotificationDriver()
    center.delivered["ritm.account.reminder.old"] = plan("old")
    center.delivered["ritm.workout.rest.old"] = plan("rest")
    let scheduler = reconciler(center)
    scheduler.clear()
    _ = await scheduler.replace([])
    XCTAssertEqual(Set(center.delivered.keys), ["ritm.workout.rest.old"])
  }

  func testRestReconcilerCancelsLateRestAddWithoutTouchingAccountAndWallet() async {
    let center = FakeNotificationDriver(delayed: true)
    center.pending["ritm.account.reminder.task"] = plan("task")
    center.delivered["ritm.account.wallet.purchase"] = plan("wallet")
    let scheduler = LocalNotificationReconciler(
      driver: center.driver, owns: { $0.hasPrefix(RestNotificationPlanner.identifierPrefix) })
    let rest = LocalNotificationPlan(
      identifier: RestNotificationPlanner.identifier(workoutID: "w"),
      fireDate: Date(timeIntervalSince1970: 4_000_000_000), title: "Rest is over", body: "Next set",
      threadIdentifier: "ritm.workout.rest", categoryIdentifier: "RITM_WORKOUT_REST",
      destination: .workout(id: "w"))
    let task = Task { await scheduler.replace([rest]) }
    await center.waitForAdds(1)
    scheduler.clear()
    center.finishNext()
    let result = await task.value
    await scheduler.flush()
    XCTAssertTrue(result.isEmpty)
    XCTAssertEqual(Set(center.pending.keys), ["ritm.account.reminder.task"])
    XCTAssertEqual(Set(center.delivered.keys), ["ritm.account.wallet.purchase"])
  }

  func testCannotScheduleAPlanOutsideOwnedNamespace() async {
    let center = FakeNotificationDriver()
    let scheduler = LocalNotificationReconciler(
      driver: center.driver, owns: { $0.hasPrefix(RestNotificationPlanner.identifierPrefix) })
    let result = await scheduler.replace([plan("account")])
    XCTAssertTrue(result.isEmpty)
    XCTAssertTrue(center.adds.isEmpty)
  }
}

@MainActor
private final class FakeNotificationDriver {
  var pending: [String: LocalNotificationPlan] = [:]
  var delivered: [String: LocalNotificationPlan] = [:]
  var adds: [String] = []
  var fails = false
  let delayed: Bool
  private var suspended: [CheckedContinuation<Void, Never>] = []
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(delayed: Bool = false) { self.delayed = delayed }

  var driver: LocalNotificationDriver {
    LocalNotificationDriver(
      pendingIdentifiers: { Array(self.pending.keys) },
      deliveredIdentifiers: { Array(self.delivered.keys) },
      add: { plan, id in
        self.adds.append(id)
        if self.delayed {
          await withCheckedContinuation { continuation in
            self.suspended.append(continuation)
            self.resumeWaiters()
          }
        } else {
          self.resumeWaiters()
        }
        if self.fails { throw FakeFailure.failed }
        self.pending[id] = plan
      },
      removePending: { ids in for id in ids { self.pending.removeValue(forKey: id) } },
      removeDelivered: { ids in for id in ids { self.delivered.removeValue(forKey: id) } })
  }

  func waitForAdds(_ count: Int) async {
    guard adds.count < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }

  func finishNext() { suspended.removeFirst().resume() }

  func deliverPending() {
    delivered.merge(pending, uniquingKeysWith: { _, next in next })
    pending = [:]
  }

  private func resumeWaiters() {
    let ready = waiters.filter { $0.0 <= adds.count }
    waiters.removeAll { $0.0 <= adds.count }
    for (_, waiter) in ready { waiter.resume() }
  }
}

private enum FakeFailure: Error { case failed }
