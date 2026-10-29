import Foundation

/// Idea discussions and failure handling of the assistant (src/features/idea-discussion.ts,
/// src/features/AssistantPage.tsx).
public enum AssistantPlan {
  /// The kinds of failure the web explains with their own text.
  public enum Failure: Sendable, Equatable {
    case discussionStale, scheduleChanged, notConfigured, ideaRateLimit, rateLimit, server
  }

  public static let discussionRounds = 8

  public static func rootID(_ message: ChatMessage) -> String {
    message.ideaReview?.discussion?.rootMessageId ?? message.id
  }

  /// The newest review in the discussion the given review belongs to.
  public static func latestReview(_ messages: [ChatMessage], from id: String) -> ChatMessage? {
    guard let selected = messages.first(where: { $0.id == id && $0.ideaReview != nil }) else {
      return nil
    }
    let root = rootID(selected)
    return messages.last { $0.ideaReview != nil && rootID($0) == root }
  }

  /// The idea as the user first wrote it: the last user message before the root review.
  public static func ideaText(_ messages: [ChatMessage], review: ChatMessage) -> String {
    guard let rootIndex = messages.firstIndex(where: { $0.id == rootID(review) }) else { return "" }
    return messages[..<rootIndex].last { $0.role == "user" }?.text ?? ""
  }

  /// The review a send produced. A replayed standalone request may now carry later ideas from
  /// another device, so it selects none.
  public static func acceptedReview(
    _ messages: [ChatMessage], parent: String?, standaloneRetry: Bool = false
  ) -> ChatMessage? {
    if let parent { return latestReview(messages, from: parent) }
    if standaloneRetry { return nil }
    return messages.last { $0.ideaReview != nil }
  }

  public static func discussionLimitReached(_ review: ChatMessage) -> Bool {
    (review.ideaReview?.discussion?.round ?? 1) >= discussionRounds
  }

  public static func failure(code: String?, retryAfter: Int?) -> Failure {
    let code = code ?? ""
    if code == "AI_DISCUSSION_STALE" { return .discussionStale }
    if code.range(of: "stale|schedule_changed", options: [.regularExpression, .caseInsensitive]) != nil {
      return .scheduleChanged
    }
    if code.range(of: "not_configured|missing_key", options: [.regularExpression, .caseInsensitive]) != nil {
      return .notConfigured
    }
    if retryAfter != nil, code.range(of: "rate_limit", options: .caseInsensitive) != nil {
      return code == "IDEA_REVIEW_RATE_LIMIT" ? .ideaRateLimit : .rateLimit
    }
    return .server
  }

  /// A stale or exhausted discussion cannot be retried as is; the message must change.
  public static func retryBlocked(code: String?) -> Bool {
    code == "AI_DISCUSSION_STALE" || code == "AI_DISCUSSION_LIMIT"
  }
}
