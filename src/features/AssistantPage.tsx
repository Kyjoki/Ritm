import { useI18n } from '../lib/i18n';
import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from 'react';
import {
  ArrowRight,
  ArrowUp,
  CalendarDays,
  Check,
  CheckCheck,
  ChevronDown,
  Clock3,
  Copy,
  History,
  LoaderCircle,
  MessageSquare,
  Plus,
  RefreshCw,
  Settings2,
  ShieldCheck,
  Sparkles,
  Trash2,
  Undo2,
  X,
} from 'lucide-react';
import type {
  AiStatus,
  ChatMessage,
  ChatMode,
  Conversation,
  ScheduleProposal,
  ScheduleTime,
} from '../../shared/types';
import { formatTime } from '../lib/date';
import { ApiError } from '../lib/api';
import { IdeaReviewPanel, ideaExpertRoles, ideaReviewCopyText } from './IdeaReviewPanel';
import {
  acceptedDiscussionReview,
  discussionIdeaText,
  latestDiscussionReview,
} from './idea-discussion';
import '../styles/assistant.css';

export interface AssistantPageProps {
  active?: boolean;
  conversations: Conversation[];
  aiStatus: AiStatus;
  onCreate: () => Promise<Conversation>;
  onDelete: (id: string) => Promise<void>;
  onSend: (
    conversationId: string | undefined,
    message: string,
    requestId: string,
    mode?: ChatMode,
    reviewMessageId?: string,
  ) => Promise<Conversation>;
  onApply: (conversationId: string, messageId: string, proposalIds: string[]) => Promise<void>;
  onReject: (conversationId: string, messageId: string, proposalIds: string[]) => Promise<void>;
  onUndo: (conversationId: string, messageId: string, proposalIds: string[]) => Promise<void>;
  onOpenSettings: () => void;
  initialPrompt?: string;
  onPromptConsumed?: () => void;
}

interface SendRequest {
  conversationId: string | undefined;
  message: string;
  requestId: string;
  mode: ChatMode;
  reviewMessageId?: string;
  status: 'sending' | 'failed';
  error?: string;
  retryAt?: number;
  retryBlocked?: boolean;
}

interface ComposerFocusRequest {
  requestId: string;
  conversationId: string | undefined;
  pageHash: string;
}

const prompts = [
  { title: 'Что у меня сегодня?', subtitle: 'Собрать дела в один план', icon: CalendarDays },
  { title: 'Спланируй неделю', subtitle: 'Оставить место для отдыха', icon: Clock3 },
  { title: 'Разбей задачу на шаги', subtitle: 'Начать с понятного действия', icon: CheckCheck },
  {
    title: 'Подготовь отчёт о выполненном',
    subtitle: 'Увидеть свой прогресс',
    icon: MessageSquare,
  },
];
const emptyMessages: ChatMessage[] = [];

function getErrorMessage(error: unknown, t: ReturnType<typeof useI18n>['t']): string {
  const code =
    typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : '';
  if (code === 'AI_DISCUSSION_STALE')
    return t(
      'Эта оценка уже обновилась или недоступна. Измените сообщение и выберите последнюю оценку идеи. Если её нет, обновите диалог.',
    );
  if (/stale|schedule_changed/i.test(code))
    return t(
      'Задача уже изменилась. Попросите Ritm составить новый план, чтобы использовать актуальное расписание.',
    );
  if (/not_configured|missing_key/i.test(code))
    return t('Подключите OpenAI в настройках и повторите запрос.');
  if (error instanceof ApiError && error.retryAfterSeconds && /rate_limit/i.test(code))
    return code === 'IDEA_REVIEW_RATE_LIMIT'
      ? t('Достигнут лимит частоты разбора идей в Ritm. Повтор станет доступен после паузы.')
      : t('Достигнут лимит частоты запросов в Ritm. Повтор станет доступен после паузы.');
  if (error instanceof Error && error.message) return t(error.message);
  return t('Не удалось выполнить действие. Проверьте соединение и попробуйте ещё раз.');
}

function formatSchedule(
  schedule: ScheduleTime,
  locale: string,
  t: ReturnType<typeof useI18n>['t'],
) {
  const date = schedule.date
    ? new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', year: 'numeric' }).format(
        new Date(`${schedule.date}T12:00:00`),
      )
    : t('Без даты');
  const time = schedule.time ? formatTime(schedule.time) : t('Время не выбрано');
  return { date, time, duration: t('{count} мин', { count: schedule.duration }) };
}

const proposalStatus: Record<ScheduleProposal['status'], string> = {
  pending: 'На рассмотрении',
  applied: 'Применено',
  rejected: 'Отклонено',
  undone: 'Изменение отменено',
};

function MessageCopyButton({ message }: { message: ChatMessage }) {
  const { t, locale } = useI18n();
  const [status, setStatus] = useState<'idle' | 'copied' | 'error'>('idle');
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const copyAttempt = useRef(0);

  useEffect(() => {
    setStatus('idle');
    return () => {
      copyAttempt.current += 1;
      if (resetTimer.current) clearTimeout(resetTimer.current);
    };
  }, []);

  async function copyAnswer() {
    const attempt = ++copyAttempt.current;
    if (resetTimer.current) clearTimeout(resetTimer.current);
    const steps = message.steps.length
      ? `${t('Понятные шаги')}\n${message.steps.map((step, index) => `${index + 1}. ${step}`).join('\n')}`
      : '';
    const proposals = message.proposals.length
      ? `${t('Предлагаемые изменения')}\n${message.proposals
          .map((proposal) => {
            const before = formatSchedule(proposal.before, locale, t);
            const after = formatSchedule(proposal.after, locale, t);
            return [
              `${proposal.title} — ${t(proposalStatus[proposal.status])}`,
              t('Было: {date}, {time}, {duration}', before),
              t('Станет: {date}, {time}, {duration}', after),
              proposal.reason,
            ]
              .filter(Boolean)
              .join('\n');
          })
          .join('\n\n')}`
      : '';
    try {
      await navigator.clipboard.writeText(
        message.ideaReview
          ? ideaReviewCopyText(message.ideaReview, t)
          : [message.text, steps, proposals].filter(Boolean).join('\n\n'),
      );
      if (copyAttempt.current !== attempt) return;
      setStatus('copied');
      resetTimer.current = setTimeout(() => setStatus('idle'), 3000);
    } catch {
      if (copyAttempt.current === attempt) setStatus('error');
    }
  }

  return (
    <div className="assistant-message-copy">
      <button type="button" onClick={() => void copyAnswer()}>
        {status === 'copied' ? (
          <Check size={14} aria-hidden="true" />
        ) : (
          <Copy size={14} aria-hidden="true" />
        )}
        {status === 'copied' ? t('Скопировано') : t('Копировать ответ')}
      </button>
      <span
        role="status"
        className={status === 'error' ? 'assistant-copy-error' : 'assistant-sr-only'}
      >
        {status === 'copied'
          ? t('Ответ скопирован')
          : status === 'error'
            ? t('Не удалось скопировать. Выделите текст и скопируйте вручную.')
            : ''}
      </span>
    </div>
  );
}

interface ProposalCardProps {
  conversationId: string;
  message: ChatMessage;
  onApply: AssistantPageProps['onApply'];
  onReject: AssistantPageProps['onReject'];
  onUndo: AssistantPageProps['onUndo'];
}

function ProposalCard({ conversationId, message, onApply, onReject, onUndo }: ProposalCardProps) {
  const { t, locale } = useI18n();
  const [selected, setSelected] = useState<string[]>([]);
  const [confirmation, setConfirmation] = useState<'apply' | 'undo' | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const actionLock = useRef(false);
  const sectionRef = useRef<HTMLElement>(null);
  const confirmationCancelRef = useRef<HTMLButtonElement>(null);
  const confirmationTriggerRef = useRef<HTMLElement | null>(null);
  const applyButtonRef = useRef<HTMLButtonElement>(null);
  const undoButtonRef = useRef<HTMLButtonElement>(null);
  const confirmationActionRef = useRef<'apply' | 'undo' | null>(null);
  const pending = message.proposals.filter((proposal) => proposal.status === 'pending');
  const applied = message.proposals.filter((proposal) => proposal.status === 'applied');
  const selectedPending = pending
    .filter((proposal) => selected.includes(proposal.id))
    .map((proposal) => proposal.id);
  const selectedApplied = applied
    .filter((proposal) => selected.includes(proposal.id))
    .map((proposal) => proposal.id);

  useEffect(() => {
    if (confirmation) {
      confirmationCancelRef.current?.focus();
    } else if (confirmationTriggerRef.current) {
      const trigger = confirmationTriggerRef.current;
      if (trigger.isConnected) trigger.focus();
      else {
        const replacement =
          confirmationActionRef.current === 'apply'
            ? applyButtonRef.current
            : undoButtonRef.current;
        if (replacement && !replacement.disabled) replacement.focus();
        else sectionRef.current?.focus();
      }
      confirmationTriggerRef.current = null;
      confirmationActionRef.current = null;
    }
  }, [confirmation]);

  function askConfirmation(action: 'apply' | 'undo') {
    confirmationTriggerRef.current =
      document.activeElement instanceof HTMLElement ? document.activeElement : null;
    confirmationActionRef.current = action;
    setConfirmation(action);
  }

  function toggle(id: string) {
    setSelected((current) =>
      current.includes(id) ? current.filter((value) => value !== id) : [...current, id],
    );
    setConfirmation(null);
    setError('');
  }

  async function runAction(action: 'apply' | 'reject' | 'undo') {
    const ids = action === 'undo' ? selectedApplied : selectedPending;
    if (!ids.length || actionLock.current) return;
    actionLock.current = true;
    setBusy(true);
    setError('');
    try {
      const callback = action === 'apply' ? onApply : action === 'reject' ? onReject : onUndo;
      await callback(conversationId, message.id, ids);
      setSelected((current) => current.filter((id) => !ids.includes(id)));
      setConfirmation(null);
    } catch (caught) {
      setError(getErrorMessage(caught, t));
      setConfirmation(null);
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }

  return (
    <section
      ref={sectionRef}
      tabIndex={-1}
      className="assistant-proposals"
      aria-label={t('Предлагаемые изменения расписания')}
      aria-busy={busy}
    >
      <div className="assistant-proposal-heading">
        <Sparkles size={16} aria-hidden="true" />
        <h3>{t('Предлагаемые изменения')}</h3>
        <span>{message.proposals.length}</span>
      </div>
      <p className="assistant-proposal-hint">
        {pending.length
          ? t('Выберите подходящие изменения. Ritm применит их после вашего подтверждения.')
          : applied.length
            ? t('Выберите применённые изменения, чтобы вернуть прежнее расписание.')
            : t('Этот план сохранён в истории диалога.')}
      </p>
      <div className="assistant-proposal-list">
        {message.proposals.map((proposal) => {
          const before = formatSchedule(proposal.before, locale, t);
          const after = formatSchedule(proposal.after, locale, t);
          const canSelect = proposal.status === 'pending' || proposal.status === 'applied';
          return (
            <article
              className={`assistant-proposal assistant-proposal--${proposal.status}`}
              key={proposal.id}
            >
              <div className="assistant-proposal-title">
                {canSelect ? (
                  <label className="assistant-proposal-select">
                    <input
                      type="checkbox"
                      checked={selected.includes(proposal.id)}
                      disabled={busy}
                      onChange={() => toggle(proposal.id)}
                      aria-label={t('Выбрать изменение: {title}', { title: proposal.title })}
                    />
                    <strong>{proposal.title}</strong>
                  </label>
                ) : (
                  <strong>{proposal.title}</strong>
                )}
                <span
                  className={`assistant-proposal-status assistant-proposal-status--${proposal.status}`}
                >
                  {proposal.status === 'applied' ? <Check size={12} aria-hidden="true" /> : null}
                  {t(proposalStatus[proposal.status])}
                </span>
              </div>
              <div className="assistant-comparison">
                <div>
                  <span>{t('Было')}</span>
                  <strong>{before.time}</strong>
                  <small>
                    {before.date} · {before.duration}
                  </small>
                </div>
                <ArrowRight size={18} aria-hidden="true" />
                <div className="assistant-comparison-after">
                  <span>{t('Станет')}</span>
                  <strong>{after.time}</strong>
                  <small>
                    {after.date} · {after.duration}
                  </small>
                </div>
              </div>
              {proposal.reason ? (
                <p className="assistant-proposal-reason">{proposal.reason}</p>
              ) : null}
            </article>
          );
        })}
      </div>
      {error ? (
        <p className="assistant-inline-error" role="alert">
          {t(error)}
        </p>
      ) : null}
      {confirmation ? (
        <div
          className="assistant-apply-confirmation"
          role="group"
          aria-label={t('Подтверждение изменений')}
        >
          <p>
            {confirmation === 'apply'
              ? t('Применить выбранные изменения ({count}) к вашему расписанию?', {
                  count: selectedPending.length,
                })
              : t('Вернуть прежнее расписание для выбранных задач ({count})?', {
                  count: selectedApplied.length,
                })}
          </p>
          <div className="assistant-proposal-actions">
            <button
              type="button"
              className="button button-primary"
              disabled={
                busy ||
                !(confirmation === 'apply' ? selectedPending.length : selectedApplied.length)
              }
              onClick={() => void runAction(confirmation)}
            >
              {busy ? (
                <LoaderCircle className="assistant-spinner" size={15} aria-hidden="true" />
              ) : (
                <Check size={15} aria-hidden="true" />
              )}
              {confirmation === 'apply' ? t('Подтвердить изменения') : t('Подтвердить отмену')}
            </button>
            <button
              ref={confirmationCancelRef}
              type="button"
              className="button button-secondary"
              disabled={busy}
              onClick={() => setConfirmation(null)}
            >
              {t('Назад')}
            </button>
          </div>
        </div>
      ) : (
        <div className="assistant-proposal-actions">
          {pending.length ? (
            <>
              <button
                ref={applyButtonRef}
                className="button button-primary"
                type="button"
                disabled={busy || !selectedPending.length}
                onClick={() => askConfirmation('apply')}
              >
                <Check size={15} aria-hidden="true" />
                {t('Применить выбранные')}
                {selectedPending.length ? ` (${selectedPending.length})` : ''}
              </button>
              <button
                className="button button-secondary"
                type="button"
                disabled={busy || !selectedPending.length}
                onClick={() => void runAction('reject')}
              >
                <X size={15} aria-hidden="true" />
                {t('Отклонить')}
              </button>
            </>
          ) : null}
          {applied.length ? (
            <button
              ref={undoButtonRef}
              className="button button-secondary"
              type="button"
              disabled={busy || !selectedApplied.length}
              onClick={() => askConfirmation('undo')}
            >
              <Undo2 size={15} aria-hidden="true" />
              {t('Отменить изменения')}
            </button>
          ) : null}
        </div>
      )}
    </section>
  );
}

export function AssistantPage({
  active = true,
  conversations,
  aiStatus,
  onCreate,
  onDelete,
  onSend,
  onApply,
  onReject,
  onUndo,
  onOpenSettings,
  initialPrompt,
  onPromptConsumed,
}: AssistantPageProps) {
  const { t, locale } = useI18n();
  const [selectedId, setSelectedId] = useState<string | undefined>(() => conversations[0]?.id);
  const [draft, setDraft] = useState('');
  const [mode, setMode] = useState<ChatMode>('assistant');
  const [reviewMessageId, setReviewMessageId] = useState<string | undefined>();
  const [discussionQuestionsOpen, setDiscussionQuestionsOpen] = useState(false);
  const [request, setRequest] = useState<SendRequest | null>(null);
  const [retryClock, setRetryClock] = useState(() => Date.now());
  const [historyOpen, setHistoryOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<Conversation | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [focusAfterDelete, setFocusAfterDelete] = useState<string | null | undefined>();
  const [pageError, setPageError] = useState('');
  const [documentVisible, setDocumentVisible] = useState(
    () => document.visibilityState === 'visible',
  );
  const [freshMessageIds, setFreshMessageIds] = useState<string[]>([]);
  const [motionEntry, setMotionEntry] = useState<'first' | 'return'>('first');
  const hasBeenActive = useRef(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const logRef = useRef<HTMLDivElement>(null);
  const historyRef = useRef<HTMLElement>(null);
  const newConversationButtonRef = useRef<HTMLButtonElement>(null);
  const deleteCancelRef = useRef<HTMLButtonElement>(null);
  const deleteTriggerRef = useRef<HTMLElement | null>(null);
  const sendLock = useRef(false);
  const createLock = useRef(false);
  const deleteLock = useRef(false);
  const nearBottom = useRef(true);
  const consumedPrompt = useRef('');
  const composerFocusRequest = useRef<ComposerFocusRequest | null>(null);
  const focusAfterHistory = useRef(false);
  const conversation = conversations.find((item) => item.id === selectedId);
  const messages = conversation?.messages ?? emptyMessages;
  const observedMessages = useRef({
    conversationId: selectedId,
    ids: new Set(messages.map((message) => message.id)),
  });
  const selectedReview = messages.find(
    (message) => message.id === reviewMessageId && message.ideaReview,
  );
  const currentDiscussionReview = reviewMessageId
    ? latestDiscussionReview(messages, reviewMessageId)
    : undefined;
  const discussionStale = !!reviewMessageId && currentDiscussionReview?.id !== reviewMessageId;
  const discussionRound = selectedReview?.ideaReview?.discussion?.round ?? 1;
  const discussionLimit = !!selectedReview && discussionRound >= 8;
  const sending = request?.status === 'sending';
  const retryRemaining =
    request?.status === 'failed' && request.retryAt
      ? Math.max(0, Math.ceil((request.retryAt - retryClock) / 1000))
      : 0;
  const requestIsVisible = !!request && request.conversationId === selectedId;
  const visibleRequest = requestIsVisible ? request : null;
  const orderedConversations = [...conversations].sort((a, b) =>
    b.updatedAt.localeCompare(a.updatedAt),
  );

  useEffect(() => {
    if (active) hasBeenActive.current = true;
    else if (hasBeenActive.current) {
      setMotionEntry('return');
      setFreshMessageIds([]);
    }
  }, [active]);

  useEffect(() => {
    const onVisibility = () => setDocumentVisible(document.visibilityState === 'visible');
    onVisibility();
    document.addEventListener('visibilitychange', onVisibility);
    return () => document.removeEventListener('visibilitychange', onVisibility);
  }, []);

  useLayoutEffect(() => {
    const ids = new Set(messages.map((message) => message.id));
    const previous = observedMessages.current;
    if (previous.conversationId !== selectedId) {
      observedMessages.current = { conversationId: selectedId, ids };
      setFreshMessageIds([]);
      return;
    }
    const added = messages
      .filter((message) => !previous.ids.has(message.id))
      .map((message) => message.id);
    observedMessages.current = { conversationId: selectedId, ids };
    if (added.length) setFreshMessageIds(added.slice(-1));
  }, [messages, selectedId]);

  useEffect(() => {
    if (!freshMessageIds.length) return;
    const timer = window.setTimeout(() => setFreshMessageIds([]), 700);
    return () => window.clearTimeout(timer);
  }, [freshMessageIds]);

  useEffect(() => {
    if (request?.status !== 'failed' || !request.retryAt) return;
    const retryAt = request.retryAt;
    setRetryClock(Date.now());
    if (Date.now() >= retryAt) return;
    const timer = setInterval(() => {
      const now = Date.now();
      setRetryClock(now);
      if (now >= retryAt) clearInterval(timer);
    }, 1000);
    return () => clearInterval(timer);
  }, [request?.status, request?.retryAt]);

  useEffect(() => {
    // Activity also cleans up effects when the page is hidden.
    return () => {
      composerFocusRequest.current = null;
      focusAfterHistory.current = false;
    };
  }, []);

  useEffect(() => {
    if (!sending || !composerFocusRequest.current) return;
    const cancelFocus = () => {
      composerFocusRequest.current = null;
    };
    const trackFocus = (event: FocusEvent) => {
      if (event.target !== inputRef.current && event.target !== document.body) cancelFocus();
    };
    const trackKey = (event: globalThis.KeyboardEvent) => {
      if (event.target !== inputRef.current || event.key !== 'Enter') cancelFocus();
    };
    document.addEventListener('focusin', trackFocus);
    document.addEventListener('pointerdown', cancelFocus);
    document.addEventListener('keydown', trackKey);
    document.addEventListener('visibilitychange', cancelFocus);
    window.addEventListener('hashchange', cancelFocus);
    return () => {
      document.removeEventListener('focusin', trackFocus);
      document.removeEventListener('pointerdown', cancelFocus);
      document.removeEventListener('keydown', trackKey);
      document.removeEventListener('visibilitychange', cancelFocus);
      window.removeEventListener('hashchange', cancelFocus);
    };
  }, [sending]);

  useEffect(() => {
    const pendingFocus = composerFocusRequest.current;
    if (sending || !pendingFocus) return;
    composerFocusRequest.current = null;
    const input = inputRef.current;
    if (
      pendingFocus.conversationId === selectedId &&
      pendingFocus.pageHash === window.location.hash &&
      document.visibilityState === 'visible' &&
      input &&
      !input.disabled &&
      input.getClientRects().length > 0 &&
      (document.activeElement === document.body || document.activeElement === input)
    )
      input.focus({ preventScroll: true });
  }, [sending, selectedId]);

  useEffect(() => {
    if (historyOpen || !focusAfterHistory.current) return;
    focusAfterHistory.current = false;
    const input = inputRef.current;
    if (input && !input.disabled && input.getClientRects().length > 0)
      input.focus({ preventScroll: true });
  }, [historyOpen, selectedId]);

  useEffect(() => {
    if (deleteTarget) deleteCancelRef.current?.focus();
    else if (deleteTriggerRef.current) {
      if (deleteTriggerRef.current.isConnected) deleteTriggerRef.current.focus();
      deleteTriggerRef.current = null;
    }
  }, [deleteTarget]);

  useEffect(() => {
    if (focusAfterDelete === undefined) return;
    const buttons =
      historyRef.current?.querySelectorAll<HTMLButtonElement>('[data-conversation-id]');
    const target = buttons
      ? Array.from(buttons).find((button) => button.dataset.conversationId === focusAfterDelete)
      : undefined;
    (target ?? newConversationButtonRef.current)?.focus();
    setFocusAfterDelete(undefined);
  }, [focusAfterDelete]);

  useEffect(() => {
    if (!initialPrompt) {
      consumedPrompt.current = '';
      return;
    }
    if (initialPrompt === consumedPrompt.current) return;
    consumedPrompt.current = initialPrompt;
    setMode('assistant');
    setReviewMessageId(undefined);
    setDraft(initialPrompt);
    inputRef.current?.focus();
    onPromptConsumed?.();
  }, [initialPrompt, onPromptConsumed]);

  useEffect(() => {
    if (logRef.current && nearBottom.current) {
      logRef.current.scrollTo({ top: logRef.current.scrollHeight, behavior: 'instant' });
    }
  }, [selectedId, messages.length, request?.status, reviewMessageId, discussionQuestionsOpen]);

  function chooseConversation(id: string) {
    if (sending) return;
    focusAfterHistory.current = historyOpen && window.matchMedia('(max-width: 800px)').matches;
    setSelectedId(id);
    setReviewMessageId(undefined);
    setDraft('');
    const lastAnswer = [...(conversations.find((item) => item.id === id)?.messages ?? [])]
      .reverse()
      .find((message) => message.role === 'assistant');
    setMode(lastAnswer?.ideaReview ? 'idea_review' : 'assistant');
    setHistoryOpen(false);
    setPageError('');
    nearBottom.current = true;
  }

  function choosePrompt(prompt: string) {
    setDraft(prompt);
    inputRef.current?.focus();
  }

  function discussReview(id: string, showQuestions = false) {
    if (sending || creating || deleting || request?.status === 'failed') return;
    const latest = latestDiscussionReview(messages, id);
    if (!latest || (latest.ideaReview?.discussion?.round ?? 1) >= 8) return;
    setReviewMessageId(latest.id);
    nearBottom.current = true;
    setDiscussionQuestionsOpen(showQuestions);
    setMode('idea_review');
    setPageError('');
    inputRef.current?.focus();
  }

  function startNewIdea() {
    if (sending || creating || deleting || request?.status === 'failed') return;
    setReviewMessageId(undefined);
    setDiscussionQuestionsOpen(false);
    setMode('idea_review');
    inputRef.current?.focus();
  }

  async function createConversation() {
    if (createLock.current || sending) return;
    createLock.current = true;
    setCreating(true);
    setPageError('');
    try {
      const created = await onCreate();
      setSelectedId(created.id);
      setReviewMessageId(undefined);
      setDraft('');
      setHistoryOpen(false);
      deleteTriggerRef.current = null;
      setDeleteTarget(null);
      nearBottom.current = true;
      inputRef.current?.focus();
    } catch (error) {
      setPageError(getErrorMessage(error, t));
    } finally {
      createLock.current = false;
      setCreating(false);
    }
  }

  async function deleteConversation() {
    if (!deleteTarget || deleteLock.current || sending) return;
    deleteLock.current = true;
    setDeleting(true);
    setPageError('');
    try {
      await onDelete(deleteTarget.id);
      const nextId =
        selectedId === deleteTarget.id
          ? orderedConversations.find((item) => item.id !== deleteTarget.id)?.id
          : selectedId;
      if (selectedId === deleteTarget.id) {
        setSelectedId(nextId);
        setReviewMessageId(undefined);
        setDraft('');
      }
      if (request?.conversationId === deleteTarget.id) setRequest(null);
      deleteTriggerRef.current = null;
      setDeleteTarget(null);
      setFocusAfterDelete(nextId ?? null);
    } catch (error) {
      setPageError(getErrorMessage(error, t));
    } finally {
      deleteLock.current = false;
      setDeleting(false);
    }
  }

  async function sendMessage(retry?: SendRequest) {
    const text = retry?.message ?? draft.trim();
    if (
      !text ||
      sendLock.current ||
      !aiStatus.configured ||
      creating ||
      deleting ||
      (!retry && request?.status === 'failed') ||
      (!retry && mode === 'idea_review' && (discussionStale || discussionLimit)) ||
      (retry?.retryAt !== undefined && retry.retryAt > Date.now()) ||
      retry?.retryBlocked
    )
      return;
    const next: SendRequest = retry
      ? { ...retry, status: 'sending', error: undefined, retryAt: undefined }
      : {
          conversationId: selectedId,
          message: text,
          requestId: crypto.randomUUID(),
          mode,
          reviewMessageId: mode === 'idea_review' ? reviewMessageId : undefined,
          status: 'sending',
        };
    composerFocusRequest.current =
      document.activeElement === inputRef.current
        ? {
            requestId: next.requestId,
            conversationId: next.conversationId,
            pageHash: window.location.hash,
          }
        : null;
    sendLock.current = true;
    setRequest(next);
    setSelectedId(next.conversationId);
    setDraft('');
    setPageError('');
    nearBottom.current = true;
    try {
      const result = await onSend(
        next.conversationId,
        next.message,
        next.requestId,
        next.mode,
        next.reviewMessageId,
      );
      if (composerFocusRequest.current?.requestId === next.requestId)
        composerFocusRequest.current.conversationId = result.id;
      setSelectedId(result.id);
      if (next.mode === 'idea_review') {
        const latestReview = acceptedDiscussionReview(
          result.messages,
          next.reviewMessageId,
          !!retry,
        );
        setReviewMessageId(latestReview?.id);
      } else setReviewMessageId(undefined);
      setRequest(null);
    } catch (error) {
      const now = Date.now();
      setRetryClock(now);
      setRequest({
        ...next,
        status: 'failed',
        error: getErrorMessage(error, t),
        retryBlocked:
          error instanceof ApiError &&
          ['AI_DISCUSSION_STALE', 'AI_DISCUSSION_LIMIT'].includes(error.code ?? ''),
        retryAt:
          error instanceof ApiError && error.retryAfterSeconds
            ? now + error.retryAfterSeconds * 1000
            : undefined,
      });
    } finally {
      sendLock.current = false;
    }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void sendMessage();
  }
  function handleComposerKey(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      void sendMessage();
    }
  }

  return (
    <div
      className="assistant-page"
      data-motion-active={active && documentVisible}
      data-motion-entry={motionEntry}
    >
      <header className="page-heading assistant-page-heading">
        <div>
          <p className="page-eyebrow">{t('Меньше рутины. Больше твоего времени.')}</p>
          <h1>{t('ИИ-помощник')}</h1>
          <p className="page-description">{t('Вместе найдём твой темп.')}</p>
        </div>
        <div className="assistant-heading-actions">
          <button
            className="button button-secondary assistant-history-toggle"
            type="button"
            aria-expanded={historyOpen}
            aria-controls="assistant-history"
            onClick={() => setHistoryOpen((value) => !value)}
          >
            <History size={17} aria-hidden="true" />
            {t('История')}
            <ChevronDown size={14} aria-hidden="true" />
          </button>
          <button
            ref={newConversationButtonRef}
            className="button button-secondary"
            type="button"
            disabled={creating || sending || deleting}
            onClick={() => void createConversation()}
          >
            {creating ? (
              <LoaderCircle className="assistant-spinner" size={16} aria-hidden="true" />
            ) : (
              <Plus size={16} aria-hidden="true" />
            )}
            {t('Новый диалог')}
          </button>
        </div>
      </header>
      {pageError ? (
        <div className="assistant-page-error" role="alert">
          {t(pageError)}
          <button
            type="button"
            aria-label={t('Закрыть сообщение об ошибке')}
            onClick={() => setPageError('')}
          >
            <X size={16} aria-hidden="true" />
          </button>
        </div>
      ) : null}
      {request?.status === 'failed' && !requestIsVisible ? (
        <div className="assistant-retry-outside" role="status">
          <span>{t('В другом диалоге осталось неотправленное сообщение.')}</span>
          <button
            type="button"
            className="button button-secondary"
            onClick={() => {
              setSelectedId(request.conversationId);
              setMode(request.mode);
              setReviewMessageId(request.reviewMessageId);
              setDraft('');
            }}
          >
            {t('Вернуться к сообщению')}
          </button>
        </div>
      ) : null}
      <div className="assistant-layout">
        <aside
          ref={historyRef}
          className={`panel assistant-history ${historyOpen ? 'assistant-history--open' : ''}`}
          id="assistant-history"
          aria-label={t('История диалогов')}
        >
          <div className="assistant-history-title">
            <h2>{t('Диалоги')}</h2>
            <span>{conversations.length}</span>
          </div>
          {orderedConversations.length ? (
            <ul className="assistant-conversation-list">
              {orderedConversations.map((item) => (
                <li
                  key={item.id}
                  className={selectedId === item.id ? 'assistant-conversation-active' : ''}
                >
                  <button
                    className="assistant-conversation-button"
                    data-conversation-id={item.id}
                    title={item.title || t('Новый диалог')}
                    aria-current={selectedId === item.id ? 'true' : undefined}
                    type="button"
                    disabled={sending || deleting}
                    onClick={() => chooseConversation(item.id)}
                  >
                    <MessageSquare size={15} aria-hidden="true" />
                    <span>{item.title || t('Новый диалог')}</span>
                  </button>
                  <button
                    className="assistant-conversation-delete"
                    type="button"
                    disabled={sending || deleting}
                    aria-label={t('Удалить диалог «{title}»', {
                      title: item.title || t('Новый диалог'),
                    })}
                    onClick={(event) => {
                      deleteTriggerRef.current = event.currentTarget;
                      setDeleteTarget(item);
                    }}
                  >
                    <Trash2 size={14} aria-hidden="true" />
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <div className="assistant-history-empty">
              <MessageSquare size={23} aria-hidden="true" />
              <p>{t('Ваши диалоги появятся здесь.')}</p>
            </div>
          )}
          {deleteTarget ? (
            <div
              className="assistant-delete-confirmation"
              role="group"
              aria-label={t('Подтверждение удаления диалога')}
            >
              <strong>{t('Удалить диалог?')}</strong>
              <p>
                {t('«{title}» и его сообщения будут удалены.', {
                  title: deleteTarget.title || t('Новый диалог'),
                })}
              </p>
              <div>
                <button
                  ref={deleteCancelRef}
                  type="button"
                  className="button button-secondary"
                  disabled={deleting}
                  onClick={() => setDeleteTarget(null)}
                >
                  {t('Оставить')}
                </button>
                <button
                  type="button"
                  className="button button-secondary assistant-delete-button"
                  disabled={deleting}
                  onClick={() => void deleteConversation()}
                >
                  {deleting ? t('Удаляем…') : t('Удалить')}
                </button>
              </div>
            </div>
          ) : null}
          <div className="assistant-history-note">
            <ShieldCheck size={17} aria-hidden="true" />
            <p>{t('Расписание меняется только с вашего согласия.')}</p>
          </div>
        </aside>
        <section className="panel assistant-chat" aria-label={t('Диалог с помощником Ritm')}>
          <header className="assistant-chat-header">
            <span
              className={`assistant-orb${sending ? ' assistant-orb--processing' : ''}`}
              aria-hidden="true"
            />
            <div>
              <h2>{mode === 'idea_review' ? t('Разбор идей') : t('Помощник Ritm')}</h2>
              <p>
                {aiStatus.configured
                  ? t('Готов к вашему запросу')
                  : t('Настройте OpenAI для начала диалога')}
              </p>
            </div>
            <span
              className={`assistant-connection ${aiStatus.configured ? 'assistant-connection--ready' : ''}`}
            >
              <i aria-hidden="true" />
              {aiStatus.configured ? t('Ключ настроен') : t('Не настроен')}
            </span>
            <div className="assistant-mode-switch" role="group" aria-label={t('Режим ИИ')}>
              <button
                type="button"
                aria-pressed={mode === 'assistant'}
                disabled={sending || creating || deleting || request?.status === 'failed'}
                onClick={() => {
                  setMode('assistant');
                  setReviewMessageId(undefined);
                }}
              >
                {t('Помощник')}
              </button>
              <button
                type="button"
                aria-pressed={mode === 'idea_review'}
                disabled={sending || creating || deleting || request?.status === 'failed'}
                onClick={() => setMode('idea_review')}
              >
                {t('Разбор идей')}
              </button>
            </div>
          </header>
          <div
            className="assistant-chat-scroll"
            ref={logRef}
            onScroll={() => {
              const log = logRef.current;
              if (log)
                nearBottom.current = log.scrollHeight - log.scrollTop - log.clientHeight < 100;
            }}
          >
            {!messages.length && !visibleRequest ? (
              <div className="assistant-welcome">
                <div className="assistant-welcome-spark" aria-hidden="true">
                  <Sparkles size={25} />
                </div>
                <h3>
                  {mode === 'idea_review'
                    ? t('Посмотрим на идею с четырёх сторон')
                    : t('С чего начнём?')}
                </h3>
                <p>
                  {mode === 'idea_review'
                    ? t(
                        'Опишите идею, для кого она и чего вы хотите добиться. Получите отдельные оценки экспертов и общий вывод, включая разногласия.',
                      )
                    : t('Помогу распределить дела, найти свободное время и сделать первый шаг.')}
                </p>
                {mode === 'idea_review' ? (
                  <div className="assistant-idea-roles">
                    {Object.entries(ideaExpertRoles).map(([id, role]) => (
                      <div className="assistant-idea-role" key={id}>
                        <strong>{t(role.title)}</strong>
                        <p>{t(role.description)}</p>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="assistant-welcome-prompts">
                    {prompts.map(({ title, subtitle, icon: Icon }) => (
                      <button type="button" key={title} onClick={() => choosePrompt(t(title))}>
                        <span>
                          <Icon size={19} aria-hidden="true" />
                        </span>
                        <div>
                          <strong>{t(title)}</strong>
                          <small>{t(subtitle)}</small>
                        </div>
                        <ArrowRight size={16} aria-hidden="true" />
                      </button>
                    ))}
                  </div>
                )}
                {!aiStatus.configured ? (
                  <div className="assistant-setup">
                    <Settings2 size={18} aria-hidden="true" />
                    <div>
                      <strong>{t('Помощник пока не подключён')}</strong>
                      <p>
                        {t(
                          'Добавьте API-ключ OpenAI в настройках. После подключения Ritm сможет отвечать на ваши запросы.',
                        )}
                      </p>
                    </div>
                    <button
                      className="button button-secondary"
                      type="button"
                      onClick={onOpenSettings}
                    >
                      {t('Открыть настройки')}
                    </button>
                  </div>
                ) : null}
              </div>
            ) : null}
            <div
              className="assistant-messages"
              role="log"
              aria-label={t('Сообщения диалога')}
              aria-live="polite"
              aria-relevant="additions"
            >
              {messages.map((message) => (
                <article
                  className={`assistant-message assistant-message--${message.role}${freshMessageIds.includes(message.id) ? ' assistant-message--fresh' : ''}`}
                  key={message.id}
                >
                  <span className="assistant-message-author">
                    {message.role === 'user' ? t('Вы') : 'Ritm'}
                  </span>
                  {message.ideaReview ? (
                    <IdeaReviewPanel
                      report={message.ideaReview}
                      onDiscuss={(showQuestions) => discussReview(message.id, showQuestions)}
                      discussionSelected={mode === 'idea_review' && reviewMessageId === message.id}
                      discussionDisabled={
                        sending ||
                        creating ||
                        deleting ||
                        request?.status === 'failed' ||
                        (message.ideaReview.discussion?.round ?? 1) >= 8
                      }
                      superseded={latestDiscussionReview(messages, message.id)?.id !== message.id}
                    />
                  ) : (
                    <div className="assistant-message-text">{message.text}</div>
                  )}
                  {message.steps.length ? (
                    <div className="assistant-steps">
                      <h3>{t('Понятные шаги')}</h3>
                      <ol>
                        {message.steps.map((step, index) => (
                          <li key={`${message.id}-step-${index}`}>{step}</li>
                        ))}
                      </ol>
                    </div>
                  ) : null}
                  {!message.ideaReview && message.proposals.length && conversation ? (
                    <ProposalCard
                      conversationId={conversation.id}
                      message={message}
                      onApply={onApply}
                      onReject={onReject}
                      onUndo={onUndo}
                    />
                  ) : null}
                  {message.role === 'assistant' ? <MessageCopyButton message={message} /> : null}
                </article>
              ))}
              {visibleRequest ? (
                <>
                  <article className="assistant-message assistant-message--user assistant-message--pending">
                    <span className="assistant-message-author">{t('Вы')}</span>
                    <div className="assistant-message-text">{visibleRequest.message}</div>
                    <small>
                      {visibleRequest.status === 'sending'
                        ? t('Отправляем…')
                        : t('Не удалось получить ответ')}
                    </small>
                  </article>
                  {visibleRequest.status === 'sending' ? (
                    <div className="assistant-waiting" role="status">
                      <span
                        className="assistant-orb assistant-orb--small assistant-orb--processing"
                        aria-hidden="true"
                      />
                      <span>
                        {visibleRequest.mode === 'idea_review'
                          ? visibleRequest.reviewMessageId
                            ? t('Эксперты пересматривают свои оценки…')
                            : t('Эксперты оценивают идею…')
                          : t('Ritm изучает ваши планы')}
                        <span className="assistant-thinking-dots" aria-hidden="true">
                          <i />
                          <i />
                          <i />
                        </span>
                      </span>
                    </div>
                  ) : (
                    <div className="assistant-request-error" role="alert">
                      <strong>{t('Не удалось получить ответ')}</strong>
                      <p>{visibleRequest.error ? t(visibleRequest.error) : ''}</p>
                      <div>
                        <button
                          type="button"
                          className="button button-secondary"
                          disabled={
                            !aiStatus.configured ||
                            sending ||
                            retryRemaining > 0 ||
                            visibleRequest.retryBlocked
                          }
                          onClick={() => void sendMessage(visibleRequest)}
                        >
                          <RefreshCw size={15} aria-hidden="true" />
                          {retryRemaining > 0
                            ? t('Повторить через {count} с', { count: retryRemaining })
                            : t('Повторить')}
                        </button>
                        <button
                          type="button"
                          className="button button-secondary"
                          onClick={() => {
                            setDraft(visibleRequest.message);
                            setMode(visibleRequest.mode);
                            setReviewMessageId(visibleRequest.reviewMessageId);
                            setRequest(null);
                            inputRef.current?.focus();
                          }}
                        >
                          {t('Изменить сообщение')}
                        </button>
                        {!aiStatus.configured ? (
                          <button
                            type="button"
                            className="button button-secondary"
                            onClick={onOpenSettings}
                          >
                            {t('Настройки')}
                          </button>
                        ) : null}
                      </div>
                    </div>
                  )}
                </>
              ) : null}
            </div>
            <div className="assistant-discussion-log-context">
              {mode === 'idea_review' ? (
                selectedReview ? (
                  <section
                    className="assistant-discussion-context"
                    aria-label={t('Текущее обсуждение идеи')}
                  >
                    <div className="assistant-discussion-heading">
                      <strong>
                        {t('Обсуждение идеи · Оценка №{round}', { round: discussionRound })}
                      </strong>
                      <button
                        type="button"
                        className="button button-secondary"
                        disabled={sending || creating || deleting || request?.status === 'failed'}
                        onClick={startNewIdea}
                      >
                        <Plus size={14} aria-hidden="true" />
                        {t('Новая идея')}
                      </button>
                    </div>
                    <p className="assistant-discussion-idea">
                      {discussionIdeaText(messages, selectedReview)}
                    </p>
                    {selectedReview.ideaReview?.synthesis.questions.length ? (
                      <details
                        className="assistant-discussion-questions"
                        open={discussionQuestionsOpen}
                        onToggle={(event) => setDiscussionQuestionsOpen(event.currentTarget.open)}
                      >
                        <summary>
                          {t('Вопросы экспертов ({count})', {
                            count: selectedReview.ideaReview.synthesis.questions.length,
                          })}
                        </summary>
                        <ol>
                          {selectedReview.ideaReview.synthesis.questions.map((question, index) => (
                            <li key={index}>{question}</li>
                          ))}
                        </ol>
                      </details>
                    ) : null}
                    <p id="assistant-discussion-hint">
                      {discussionLimit
                        ? t(
                            'Достигнуто 8 оценок этой идеи. Начните новый разбор с её обновлённым описанием.',
                          )
                        : discussionStale
                          ? t('Появилась новая оценка. Выберите её, чтобы продолжить обсуждение.')
                          : t(
                              'Ответьте на вопросы или уточните идею. Каждый эксперт пересмотрит своё мнение с учётом ваших ответов.',
                            )}
                    </p>
                    {discussionStale && currentDiscussionReview ? (
                      <button
                        type="button"
                        className="button button-secondary"
                        disabled={sending || request?.status === 'failed'}
                        onClick={() => discussReview(currentDiscussionReview.id)}
                      >
                        {t('Перейти к новой оценке')}
                      </button>
                    ) : null}
                  </section>
                ) : reviewMessageId ? (
                  <div className="assistant-discussion-context" role="status">
                    <p id="assistant-discussion-hint">
                      {t(
                        'Эта оценка больше недоступна. Выберите сохранённый разбор или начните новую идею.',
                      )}
                    </p>
                    <button
                      type="button"
                      className="button button-secondary"
                      disabled={sending || request?.status === 'failed'}
                      onClick={startNewIdea}
                    >
                      {t('Новая идея')}
                    </button>
                  </div>
                ) : null
              ) : null}
            </div>
          </div>
          <div className="assistant-composer-area">
            {messages.length && mode === 'assistant' ? (
              <div className="assistant-prompt-chips" aria-label={t('Быстрые запросы')}>
                {prompts.map(({ title }) => (
                  <button
                    type="button"
                    key={title}
                    disabled={sending}
                    onClick={() => choosePrompt(t(title))}
                  >
                    {t(title)}
                  </button>
                ))}
              </div>
            ) : null}
            {!aiStatus.configured && messages.length ? (
              <div className="assistant-compact-setup">
                <span>{t('Для новых ответов подключите OpenAI.')}</span>
                <button type="button" onClick={onOpenSettings}>
                  {t('Настройки')}
                  <ArrowRight size={13} aria-hidden="true" />
                </button>
              </div>
            ) : null}
            {mode === 'idea_review' ? (
              <p className="assistant-idea-hint" id="assistant-idea-hint">
                {t(
                  'Четыре отдельные оценки и общий вывод. Одна модель, пять запросов OpenAI; без проверки фактов в интернете.',
                )}
              </p>
            ) : null}
            <form className="assistant-composer" onSubmit={submit}>
              <label htmlFor="assistant-message-input" className="assistant-sr-only">
                {mode === 'idea_review'
                  ? reviewMessageId
                    ? t('Ответ экспертам или уточнение идеи')
                    : t('Идея для разбора экспертами')
                  : t('Сообщение ИИ-помощнику')}
              </label>
              <textarea
                id="assistant-message-input"
                name="message"
                ref={inputRef}
                value={draft}
                rows={2}
                maxLength={6000}
                placeholder={
                  mode === 'idea_review'
                    ? reviewMessageId
                      ? t('Ответьте на вопросы или уточните идею…')
                      : t('Опишите вашу идею…')
                    : t('Спросите о своих планах…')
                }
                disabled={sending}
                onChange={(event) => setDraft(event.target.value)}
                onKeyDown={handleComposerKey}
                aria-describedby={
                  mode === 'idea_review'
                    ? `assistant-idea-hint assistant-composer-hint${reviewMessageId ? ' assistant-discussion-hint' : ''}`
                    : 'assistant-composer-hint'
                }
              />
              <button
                className="button button-primary assistant-send"
                type="submit"
                disabled={
                  !draft.trim() ||
                  sending ||
                  !aiStatus.configured ||
                  creating ||
                  deleting ||
                  (mode === 'idea_review' && (discussionStale || discussionLimit)) ||
                  request?.status === 'failed'
                }
                aria-label={sending ? t('Отправка сообщения') : t('Отправить сообщение')}
                title={
                  !aiStatus.configured
                    ? t('Сначала подключите OpenAI в настройках')
                    : t('Отправить')
                }
              >
                {sending ? (
                  <LoaderCircle size={19} className="assistant-spinner" aria-hidden="true" />
                ) : (
                  <ArrowUp size={21} aria-hidden="true" />
                )}
              </button>
            </form>
            <p id="assistant-composer-hint" className="assistant-composer-hint">
              <ShieldCheck size={13} aria-hidden="true" />
              <span>
                {mode === 'idea_review'
                  ? t('Разбор идеи не меняет ваше расписание')
                  : t('Изменения только после вашего подтверждения')}
              </span>
              <span className="assistant-key-hint">
                {t('Enter — отправить · Shift + Enter — новая строка')}
              </span>
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}
