/**
 * State machine for automatic button feedback.
 *
 * Ritm components already disable their action button while a request runs
 * (`disabled={busy}`, `disabled={saving}` …). The interaction layer watches that
 * transition: a button that becomes disabled shortly after the user pressed it is
 * showing work in progress; when it is enabled again the outcome is success,
 * unless an error surfaced in the meantime.
 */
export type FeedbackState = 'idle' | 'armed' | 'loading' | 'success' | 'error';

export type FeedbackEvent =
  | { type: 'press'; at: number }
  | { type: 'disabled'; at: number }
  | { type: 'enabled'; at: number; errorSince: boolean }
  | { type: 'settle'; at: number };

export interface Feedback {
  state: FeedbackState;
  since: number;
}

/** A press arms the button for this long; a later `disabled` is not ours. */
export const ARM_WINDOW_MS = 600;
/** How long success / error stay on the button. */
export const OUTCOME_MS = 1300;

export const idle: Feedback = { state: 'idle', since: 0 };

export function nextFeedback(current: Feedback, event: FeedbackEvent): Feedback {
  switch (event.type) {
    case 'press':
      // A press during loading changes nothing: the request is still running.
      if (current.state === 'loading') return current;
      return { state: 'armed', since: event.at };
    case 'disabled':
      if (current.state === 'armed' && event.at - current.since <= ARM_WINDOW_MS)
        return { state: 'loading', since: event.at };
      return current;
    case 'enabled':
      if (current.state !== 'loading') return current;
      return { state: event.errorSince ? 'error' : 'success', since: event.at };
    case 'settle':
      if (current.state === 'armed' && event.at - current.since > ARM_WINDOW_MS) return idle;
      if (
        (current.state === 'success' || current.state === 'error') &&
        event.at - current.since >= OUTCOME_MS
      )
        return idle;
      return current;
  }
}
