import Foundation

/// An omitted optional patch field means "leave unchanged"; .null explicitly clears it.
public enum NullableField<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
  case value(Value)
  case null
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = container.decodeNil() ? .null : .value(try container.decode(Value.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .value(let value): try container.encode(value)
    }
  }
}

public struct TaskPatch: Encodable, Sendable, Equatable {
  public var title: String?
  public var description: String?
  public var date: NullableField<String>?
  public var time: NullableField<String>?
  public var duration: Int?
  public var priority: Priority?
  public var `repeat`: TaskRepeat?
  public var kind: TaskKind?
  public var completed: Bool?
  public var calendarEntry: Bool?
  public var colorId: NullableField<String>?
  public var occurrenceDate: String?

  public init(
    title: String? = nil, description: String? = nil,
    date: NullableField<String>? = nil, time: NullableField<String>? = nil,
    duration: Int? = nil, priority: Priority? = nil, `repeat` recurrence: TaskRepeat? = nil,
    kind: TaskKind? = nil, completed: Bool? = nil, calendarEntry: Bool? = nil,
    colorId: NullableField<String>? = nil, occurrenceDate: String? = nil
  ) {
    self.title = title
    self.description = description
    self.date = date
    self.time = time
    self.duration = duration
    self.priority = priority
    self.repeat = recurrence
    self.kind = kind
    self.completed = completed
    self.calendarEntry = calendarEntry
    self.colorId = colorId
    self.occurrenceDate = occurrenceDate
  }
}
