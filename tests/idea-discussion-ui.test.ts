import test from 'node:test';
import assert from 'node:assert/strict';
import type { ChatMessage, IdeaReviewReport } from '../shared/types.ts';
import {
  acceptedDiscussionReview,
  discussionIdeaText,
  discussionRootId,
  latestDiscussionReview,
} from '../src/features/idea-discussion.ts';

const report: IdeaReviewReport = {
  version: 1,
  model: 'test-model',
  experts: [],
  synthesis: {
    verdict: 'needs_testing',
    summary: 'Исходная оценка',
    agreements: [],
    disagreements: [],
    questions: ['Как проверить спрос?'],
    nextSteps: [],
  },
};
const message = (
  id: string,
  role: ChatMessage['role'],
  text: string,
  ideaReview?: IdeaReviewReport,
): ChatMessage => ({
  id,
  role,
  text,
  ideaReview,
  createdAt: '2026-10-14T12:00:00.000Z',
  proposals: [],
  steps: [],
});
const root = message('root', 'assistant', '', report);
const revision = message('revision', 'assistant', '', {
  ...report,
  discussion: {
    round: 2,
    rootMessageId: 'root',
    parentMessageId: 'root',
    changes: ['Уточнена аудитория'],
    verdictChanges: [],
  },
});

test('legacy reports are independent roots; only latest same-lineage review can continue', () => {
  const unrelated = message('unrelated', 'assistant', '', report);
  const messages = [root, revision, unrelated];
  assert.equal(discussionRootId(root), 'root');
  assert.equal(discussionRootId(revision), 'root');
  assert.equal(latestDiscussionReview(messages, 'root')?.id, 'revision');
  assert.equal(latestDiscussionReview(messages, 'revision')?.id, 'revision');
  assert.equal(latestDiscussionReview(messages, 'unrelated')?.id, 'unrelated');
});

test('missing or deleted references and other-conversation ids do not become a new discussion target', () => {
  const user = message('user', 'user', 'Не отчёт');
  assert.equal(latestDiscussionReview([root, revision], 'missing'), undefined);
  assert.equal(latestDiscussionReview([user, root], 'user'), undefined);
  assert.equal(latestDiscussionReview([root], 'revision'), undefined);
  assert.equal(latestDiscussionReview([], 'root'), undefined);
});

test('discussion context keeps original personal idea verbatim rather than later clarifications', () => {
  const original = 'Идея с именем Paul, $& и {title}';
  const messages = [
    message('idea', 'user', original),
    root,
    message('clarification', 'user', 'Новая информация'),
    revision,
  ];
  assert.equal(discussionIdeaText(messages, root), original);
  assert.equal(discussionIdeaText(messages, revision), original);
  assert.equal(discussionIdeaText([revision], revision), '');
});

test('a durable replay keeps the exact continued lineage and does not select an unrelated newer idea', () => {
  const unrelated = message('unrelated', 'assistant', '', report);
  const messages = [root, revision, unrelated];
  assert.equal(acceptedDiscussionReview(messages, 'root', true)?.id, 'revision');
  assert.equal(acceptedDiscussionReview(messages, undefined, true), undefined);
  assert.equal(acceptedDiscussionReview(messages, undefined, false)?.id, 'unrelated');
  assert.equal(acceptedDiscussionReview([unrelated], 'root', true), undefined);
});
