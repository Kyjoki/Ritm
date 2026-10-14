import type { ChatMessage } from '../../shared/types';

export function discussionRootId(message: ChatMessage): string {
  return message.ideaReview?.discussion?.rootMessageId ?? message.id;
}

export function latestDiscussionReview(
  messages: ChatMessage[],
  reviewMessageId: string,
): ChatMessage | undefined {
  const selected = messages.find((message) => message.id === reviewMessageId && message.ideaReview);
  if (!selected) return undefined;
  const rootId = discussionRootId(selected);
  return [...messages]
    .reverse()
    .find((message) => message.ideaReview && discussionRootId(message) === rootId);
}

export function discussionIdeaText(messages: ChatMessage[], report: ChatMessage): string {
  const rootIndex = messages.findIndex((message) => message.id === discussionRootId(report));
  if (rootIndex < 0) return '';
  return (
    [...messages.slice(0, rootIndex)].reverse().find((message) => message.role === 'user')?.text ??
    ''
  );
}

export function acceptedDiscussionReview(
  messages: ChatMessage[],
  parentMessageId?: string,
  standaloneRetry = false,
): ChatMessage | undefined {
  if (parentMessageId) return latestDiscussionReview(messages, parentMessageId);
  // A replay can contain later ideas from another device; their ids are not this request's receipt.
  if (standaloneRetry) return undefined;
  return [...messages].reverse().find((message) => message.ideaReview);
}
