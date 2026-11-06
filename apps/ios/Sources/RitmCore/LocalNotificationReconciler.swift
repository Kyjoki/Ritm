import Foundation

/// Foundation-only scheduling boundary. Tests use delayed adds to exercise the same races as iOS.
@MainActor
public struct LocalNotificationDriver {
  public var pendingIdentifiers: () async -> [String]
  public var deliveredIdentifiers: () async -> [String]
  public var add: (LocalNotificationPlan, String) async throws -> Void
  public var removePending: ([String]) -> Void
  public var removeDelivered: ([String]) -> Void

  public init(
    pendingIdentifiers: @escaping () async -> [String],
    deliveredIdentifiers: @escaping () async -> [String],
    add: @escaping (LocalNotificationPlan, String) async throws -> Void,
    removePending: @escaping ([String]) -> Void, removeDelivered: @escaping ([String]) -> Void
  ) {
    self.pendingIdentifiers = pendingIdentifiers
    self.deliveredIdentifiers = deliveredIdentifiers
    self.add = add
    self.removePending = removePending
    self.removeDelivered = removeDelivered
  }
}

/// Each async add has its own physical ID. A stale completion can therefore cancel itself
/// without ever removing a newer replacement. No process-local lock is mistaken for an OS lock.
@MainActor
public final class LocalNotificationReconciler {
  private struct Applied {
    let plan: LocalNotificationPlan
    let requestID: String
  }

  private let driver: LocalNotificationDriver
  private let owns: (String) -> Bool
  private var revision = 0
  private var applied: [String: Applied] = [:]
  private var desired: [LocalNotificationPlan] = []
  private var runner: Task<Void, Never>?
  private var inFlightID: String?
  private var sweepDelivered = false

  public init(driver: LocalNotificationDriver, owns: @escaping (String) -> Bool) {
    self.driver = driver
    self.owns = owns
  }

  /// Returns logical IDs actually retained or scheduled; failed adds are not reported as success.
  @discardableResult
  public func replace(_ plans: [LocalNotificationPlan]) async -> Set<String> {
    setPlans(plans)
    await runner?.value
    let requested = Dictionary(plans.map { ($0.identifier, $0) }, uniquingKeysWith: { _, last in last })
    return Set(applied.compactMap { requested[$0.key] == $0.value.plan ? $0.key : nil })
  }

  /// Update the desired set before returning, including callers that cannot await the drain.
  public func setPlans(_ plans: [LocalNotificationPlan]) {
    revision &+= 1
    desired = plans.filter { owns($0.identifier) }
    startRunner()
  }

  /// Wait for a scoped logout sweep before the application releases its account state.
  public func flush() async { await runner?.value }

  /// Synchronous invalidation is important for logout and cancellation during an async add.
  /// Persisted requests from an earlier launch are swept asynchronously, only in this namespace.
  public func clear() {
    revision &+= 1
    desired = []
    sweepDelivered = true
    var known = applied.values.map(\.requestID)
    if let inFlightID { known.append(inFlightID) }
    applied = [:]
    if !known.isEmpty {
      driver.removePending(known)
      driver.removeDelivered(known)
    }
    startRunner()
  }

  private func startRunner() {
    guard runner == nil else { return }
    runner = Task { [weak self] in
      guard let self else { return }
      await run()
      runner = nil
    }
  }

  /// One drain serializes OS adds, including immediate notices. Replacing an identical plan
  /// during an add adopts the result instead of producing a second banner.
  private func run() async {
    while true {
      let ticket = revision
      let plans = desired
      let wanted = Dictionary(plans.map { ($0.identifier, $0) }, uniquingKeysWith: { _, last in last })
      let pending = await driver.pendingIdentifiers()
      if ticket != revision { continue }
      let pendingSet = Set(pending)
      var kept: [String: Applied] = [:]
      for (identifier, current) in applied where wanted[identifier] == current.plan {
        if current.plan.fireDate == nil || pendingSet.contains(current.requestID) {
          kept[identifier] = current
        }
      }
      let retainedIDs = Set(kept.values.map(\.requestID))
      let obsolete = pending.filter { owns($0) && !retainedIDs.contains($0) }
      if !obsolete.isEmpty { driver.removePending(obsolete) }
      let oldDelivered = applied.values.filter { !retainedIDs.contains($0.requestID) }.map(\.requestID)
      if !oldDelivered.isEmpty { driver.removeDelivered(oldDelivered) }
      applied = kept
      if sweepDelivered {
        let delivered = await driver.deliveredIdentifiers()
        if ticket != revision { continue }
        let stale = delivered.filter { owns($0) && !retainedIDs.contains($0) }
        if !stale.isEmpty { driver.removeDelivered(stale) }
        sweepDelivered = false
      }
      for plan in plans where wanted[plan.identifier] == plan && applied[plan.identifier] == nil {
        if ticket != revision { break }
        let requestID = plan.identifier + ".request." + UUID().uuidString.lowercased()
        inFlightID = requestID
        do {
          try await driver.add(plan, requestID)
          // The same logical plan can be adopted by a newer request while the add is running.
          if desired.contains(plan) {
            applied[plan.identifier] = Applied(plan: plan, requestID: requestID)
          } else {
            driver.removePending([requestID])
            driver.removeDelivered([requestID])
          }
        } catch {
          // A transport can fail after handing the request to the OS. Cancel only this attempt.
          driver.removePending([requestID])
          driver.removeDelivered([requestID])
        }
        inFlightID = nil
      }
      if ticket == revision { return }
    }
  }
}
