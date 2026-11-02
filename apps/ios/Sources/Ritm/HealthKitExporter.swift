import Foundation
import RitmCore

#if canImport(HealthKit)
  import HealthKit

  /// The only place that talks to HealthKit. It WRITES finished workouts and nothing else:
  /// no calories, no heart rate, no weights, no read types, never another app's samples, never
  /// a delete. Share access is requested for `HKWorkoutType` only, and only after a user tap.
  ///
  /// Not verified on a device: whether Apple grants the HealthKit entitlement to a free
  /// developer team is decided by Apple's server at install time. Also unverified: that an
  /// app can look up its own earlier sample without read access; if the lookup finds nothing,
  /// the retry writes the same sync identifier and version, which Health does not duplicate.
  actor HealthKitExporter: HealthWorkoutWriting {
    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()

    func requestShareAuthorization() async -> HealthShareStatus {
      guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
      // The error is deliberately not reported: the status below is the confirmed fact.
      try? await store.requestAuthorization(toShare: [workoutType], read: [])
      return currentStatus()
    }

    func shareStatus() async -> HealthShareStatus { currentStatus() }

    /// Write status only; HealthKit never reveals whether READ access was granted.
    private func currentStatus() -> HealthShareStatus {
      guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
      switch store.authorizationStatus(for: workoutType) {
      case .sharingAuthorized: return .allowed
      case .sharingDenied: return .denied
      default: return .notDetermined
      }
    }

    func save(_ payload: HealthWorkoutPayload) async throws -> String? {
      let configuration = HKWorkoutConfiguration()
      configuration.activityType = Self.activityType(payload.activity)
      let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
      do {
        try await builder.beginCollection(at: payload.start)
        try await builder.addMetadata([
          HKMetadataKeySyncIdentifier: payload.syncIdentifier,
          HKMetadataKeySyncVersion: payload.syncVersion,
        ])
        try await builder.endCollection(at: payload.end)
        guard let workout = try await builder.finishWorkout() else {
          throw HealthWriteError.outcomeUnknown
        }
        return workout.uuid.uuidString
      } catch let error as HealthWriteError {
        throw error
      } catch let error as HKError {
        throw HealthWriteError.failure(Self.reason(error.code), retryable: Self.isRetryable(error.code))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw HealthWriteError.failure(.saveFailed, retryable: true)
      }
    }

    func findExisting(syncIdentifier: String) async throws -> String? {
      let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        HKQuery.predicateForObjects(from: HKSource.default()),
        HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier]),
      ])
      let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [], limit: 1)
      return try await descriptor.result(for: store).first?.uuid.uuidString
    }

    private static func activityType(_ kind: HealthActivityKind) -> HKWorkoutActivityType {
      switch kind { case .traditionalStrengthTraining: return .traditionalStrengthTraining }
    }

    private static func reason(_ code: HKError.Code) -> HealthExportFailure {
      switch code {
      case .errorAuthorizationDenied, .errorAuthorizationNotDetermined: return .notAuthorized
      case .errorHealthDataUnavailable, .errorHealthDataRestricted: return .healthUnavailable
      case .errorDatabaseInaccessible: return .dataProtected
      default: return .saveFailed
      }
    }

    private static func isRetryable(_ code: HKError.Code) -> Bool {
      switch code {
      case .errorHealthDataUnavailable, .errorHealthDataRestricted: return false
      default: return true
      }
    }
  }
#endif

/// The writer the app uses: HealthKit where it exists, otherwise one that reports it as unavailable.
func makeHealthWriter() -> any HealthWorkoutWriting {
  #if canImport(HealthKit)
    return HealthKitExporter()
  #else
    return HealthUnavailableWriter()
  #endif
}
