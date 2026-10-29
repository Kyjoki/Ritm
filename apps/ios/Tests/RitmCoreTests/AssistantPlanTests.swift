import Foundation
import XCTest

@testable import RitmCore

/// Mirrors src/features/idea-discussion.ts and the error rules of AssistantPage.tsx.
final class AssistantPlanTests: XCTestCase {
  private func review(_ id: String, root: String? = nil, round: Int = 1) -> ChatMessage {
    let synthesis = IdeaReviewSynthesis(
      verdict: .needsTesting, summary: "s", agreements: [], disagreements: [], questions: ["q"],
      nextSteps: [])
    let discussion = root.map {
      IdeaReviewDiscussion(
        round: round, parentMessageId: $0, rootMessageId: $0, changes: [], verdictChanges: [])
    }
    return ChatMessage(
      id: id, role: "assistant", text: "",
      ideaReview: IdeaReviewReport(model: "m", experts: [], synthesis: synthesis, discussion: discussion))
  }

  private var thread: [ChatMessage] {
    [
      ChatMessage(id: "u1", role: "user", text: "Coffee cart"),
      review("r1"),
      ChatMessage(id: "u2", role: "user", text: "Only mornings"),
      review("r2", root: "r1", round: 2),
      ChatMessage(id: "u3", role: "user", text: "Second idea"),
      review("s1"),
    ]
  }

  func testLatestReviewFollowsTheRootOfTheDiscussion() {
    XCTAssertEqual(AssistantPlan.latestReview(thread, from: "r1")?.id, "r2")
    XCTAssertEqual(AssistantPlan.latestReview(thread, from: "r2")?.id, "r2")
    XCTAssertEqual(AssistantPlan.latestReview(thread, from: "s1")?.id, "s1")
    XCTAssertNil(AssistantPlan.latestReview(thread, from: "u1"))
  }

  func testIdeaTextIsTheUserMessageBeforeTheRootReview() {
    XCTAssertEqual(AssistantPlan.ideaText(thread, review: review("r2", root: "r1", round: 2)), "Coffee cart")
    XCTAssertEqual(AssistantPlan.ideaText(thread, review: review("s1")), "Second idea")
  }

  func testAcceptedReviewAfterASend() {
    XCTAssertEqual(AssistantPlan.acceptedReview(thread, parent: "r1")?.id, "r2")
    XCTAssertEqual(AssistantPlan.acceptedReview(thread, parent: nil)?.id, "s1")
    XCTAssertNil(AssistantPlan.acceptedReview(thread, parent: nil, standaloneRetry: true))
  }

  func testDiscussionStopsAfterEightRounds() {
    XCTAssertFalse(AssistantPlan.discussionLimitReached(review("r7", root: "r1", round: 7)))
    XCTAssertTrue(AssistantPlan.discussionLimitReached(review("r8", root: "r1", round: 8)))
    XCTAssertFalse(AssistantPlan.discussionLimitReached(review("r1")))
  }

  func testFailuresMapToTheWebMessages() {
    XCTAssertEqual(AssistantPlan.failure(code: "AI_DISCUSSION_STALE", retryAfter: nil), .discussionStale)
    XCTAssertEqual(AssistantPlan.failure(code: "TASK_STALE", retryAfter: nil), .scheduleChanged)
    XCTAssertEqual(AssistantPlan.failure(code: "SCHEDULE_CHANGED", retryAfter: nil), .scheduleChanged)
    XCTAssertEqual(AssistantPlan.failure(code: "AI_NOT_CONFIGURED", retryAfter: nil), .notConfigured)
    XCTAssertEqual(AssistantPlan.failure(code: "IDEA_REVIEW_RATE_LIMIT", retryAfter: 30), .ideaRateLimit)
    XCTAssertEqual(AssistantPlan.failure(code: "RATE_LIMIT", retryAfter: 30), .rateLimit)
    XCTAssertEqual(AssistantPlan.failure(code: "RATE_LIMIT", retryAfter: nil), .server)
    XCTAssertEqual(AssistantPlan.failure(code: nil, retryAfter: nil), .server)
    XCTAssertTrue(AssistantPlan.retryBlocked(code: "AI_DISCUSSION_LIMIT"))
    XCTAssertTrue(AssistantPlan.retryBlocked(code: "AI_DISCUSSION_STALE"))
    XCTAssertFalse(AssistantPlan.retryBlocked(code: "AI_LIMIT"))
  }
}
