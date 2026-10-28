import Foundation

public enum ChatMode: String, Codable, Sendable, CaseIterable {
  case assistant
  case ideaReview = "idea_review"
}
public enum ProposalAction: String, Codable, Sendable { case apply, undo }
public enum ProposalStatus: String, Codable, Sendable { case pending, applied, rejected, undone }
public enum IdeaExpertID: String, Codable, Sendable, CaseIterable {
  case value, feasibility, resources, risks
}
public enum IdeaVerdict: String, Codable, Sendable {
  case promising
  case needsTesting = "needs_testing"
  case weak
}

public struct ScheduleTime: Codable, Sendable, Equatable {
  public var date: String?
  public var time: String?
  public var duration: Int
  public init(date: String?, time: String?, duration: Int) {
    self.date = date
    self.time = time
    self.duration = duration
  }
  private enum CodingKeys: String, CodingKey { case date, time, duration }
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(date, forKey: .date)
    try values.encode(time, forKey: .time)
    try values.encode(duration, forKey: .duration)
  }
}

public struct ScheduleProposal: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var taskId: String
  public var title: String
  public var before: ScheduleTime
  public var after: ScheduleTime
  public var reason: String
  public var status: ProposalStatus
  public var taskUpdatedAt: String
  public init(
    id: String, taskId: String, title: String, before: ScheduleTime, after: ScheduleTime,
    reason: String, status: ProposalStatus = .pending, taskUpdatedAt: String
  ) {
    self.id = id
    self.taskId = taskId
    self.title = title
    self.before = before
    self.after = after
    self.reason = reason
    self.status = status
    self.taskUpdatedAt = taskUpdatedAt
  }
}

public struct ProposalResult: Codable, Sendable, Equatable {
  public var tasks: [RitmTask]
  public var conversation: Conversation
  public init(tasks: [RitmTask], conversation: Conversation) {
    self.tasks = tasks
    self.conversation = conversation
  }
}

public struct IdeaExpertReview: Codable, Sendable, Equatable, Identifiable {
  public var id: IdeaExpertID
  public var verdict: IdeaVerdict
  public var summary: String
  public var strengths: [String]
  public var concerns: [String]
  public var assumptions: [String]
  public var firstTest: String
  public init(
    id: IdeaExpertID, verdict: IdeaVerdict, summary: String, strengths: [String],
    concerns: [String], assumptions: [String], firstTest: String
  ) {
    self.id = id
    self.verdict = verdict
    self.summary = summary
    self.strengths = strengths
    self.concerns = concerns
    self.assumptions = assumptions
    self.firstTest = firstTest
  }
}

public struct IdeaReviewSynthesis: Codable, Sendable, Equatable {
  public var verdict: IdeaVerdict
  public var summary: String
  public var agreements: [String]
  public var disagreements: [String]
  public var questions: [String]
  public var nextSteps: [String]
  public init(
    verdict: IdeaVerdict, summary: String, agreements: [String], disagreements: [String],
    questions: [String], nextSteps: [String]
  ) {
    self.verdict = verdict
    self.summary = summary
    self.agreements = agreements
    self.disagreements = disagreements
    self.questions = questions
    self.nextSteps = nextSteps
  }
}

public struct IdeaVerdictChange: Codable, Sendable, Equatable, Identifiable {
  public var id: IdeaExpertID
  public var before: IdeaVerdict
  public var after: IdeaVerdict
  public init(id: IdeaExpertID, before: IdeaVerdict, after: IdeaVerdict) {
    self.id = id
    self.before = before
    self.after = after
  }
}

public struct IdeaReviewDiscussion: Codable, Sendable, Equatable {
  public var round: Int
  public var parentMessageId: String
  public var rootMessageId: String
  public var changes: [String]
  public var verdictChanges: [IdeaVerdictChange]
  public init(
    round: Int, parentMessageId: String, rootMessageId: String, changes: [String],
    verdictChanges: [IdeaVerdictChange]
  ) {
    self.round = round
    self.parentMessageId = parentMessageId
    self.rootMessageId = rootMessageId
    self.changes = changes
    self.verdictChanges = verdictChanges
  }
}

public struct IdeaReviewReport: Codable, Sendable, Equatable {
  public var version: Int
  public var model: String
  public var experts: [IdeaExpertReview]
  public var synthesis: IdeaReviewSynthesis
  public var discussion: IdeaReviewDiscussion?
  public init(
    version: Int = 1, model: String, experts: [IdeaExpertReview], synthesis: IdeaReviewSynthesis,
    discussion: IdeaReviewDiscussion? = nil
  ) {
    self.version = version
    self.model = model
    self.experts = experts
    self.synthesis = synthesis
    self.discussion = discussion
  }
}
