import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react';
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
import { IdeaReviewPanel, ideaExpertRoles, ideaReviewCopyText } from './IdeaReviewPanel';
import '../styles/assistant.css';

export interface AssistantPageProps {
  conversations: Conversation[];
  aiStatus: AiStatus;
  onCreate: () => Promise<Conversation>;
  onDelete: (id: string) => Promise<void>;
  onSend: (
    conversationId: string | undefined,
    message: string,
    requestId: string,
    mode?: ChatMode,
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
  status: 'sending' | 'failed';
  error?: string;
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

function getErrorMessage(error: unknown): string {
  const code =
    typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : '';
  if (/stale|schedule_changed/i.test(code))
    return 'Задача уже изменилась. Попросите Ritm составить новый план, чтобы использовать актуальное расписание.';
  if (/not_configured|missing_key/i.test(code))
    return 'Подключите OpenAI в настройках и повторите запрос.';
  if (/rate_limit/i.test(code))
    return 'Сервис временно ограничил запросы. Повторите отправку чуть позже.';
  if (error instanceof Error && error.message) return error.message;
  return 'Не удалось выполнить действие. Проверьте соединение и попробуйте ещё раз.';
}

function formatSchedule(schedule: ScheduleTime) {
  const date = schedule.date
    ? new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' }).format(
        new Date(`${schedule.date}T12:00:00`),
      )
    : 'Без даты';
  const time = schedule.time ? formatTime(schedule.time) : 'Время не выбрано';
  return { date, time, duration: `${schedule.duration} мин` };
}

const proposalStatus: Record<ScheduleProposal['status'], string> = {
  pending: 'На рассмотрении',
  applied: 'Применено',
  rejected: 'Отклонено',
  undone: 'Изменение отменено',
};

function MessageCopyButton({ message }: { message: ChatMessage }) {
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
      ? `Понятные шаги\n${message.steps.map((step, index) => `${index + 1}. ${step}`).join('\n')}`
      : '';
    const proposals = message.proposals.length
      ? `Предлагаемые изменения\n${message.proposals
          .map((proposal) => {
            const before = formatSchedule(proposal.before);
            const after = formatSchedule(proposal.after);
            return [
              `${proposal.title} — ${proposalStatus[proposal.status]}`,
              `Было: ${before.date}, ${before.time}, ${before.duration}`,
              `Станет: ${after.date}, ${after.time}, ${after.duration}`,
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
          ? ideaReviewCopyText(message.ideaReview)
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
        {status === 'copied' ? 'Скопировано' : 'Копировать ответ'}
      </button>
      <span
        role="status"
        className={status === 'error' ? 'assistant-copy-error' : 'assistant-sr-only'}
      >
        {status === 'copied'
          ? 'Ответ скопирован'
          : status === 'error'
            ? 'Не удалось скопировать. Выделите текст и скопируйте вручную.'
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
      setError(getErrorMessage(caught));
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
      aria-label="Предлагаемые изменения расписания"
      aria-busy={busy}
    >
      <div className="assistant-proposal-heading">
        <Sparkles size={16} aria-hidden="true" />
        <h3>Предлагаемые изменения</h3>
        <span>{message.proposals.length}</span>
      </div>
      <p className="assistant-proposal-hint">
        {pending.length
          ? 'Выберите подходящие изменения. Ritm применит их после вашего подтверждения.'
          : applied.length
            ? 'Выберите применённые изменения, чтобы вернуть прежнее расписание.'
            : 'Этот план сохранён в истории диалога.'}
      </p>
      <div className="assistant-proposal-list">
        {message.proposals.map((proposal) => {
          const before = formatSchedule(proposal.before);
          const after = formatSchedule(proposal.after);
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
                      aria-label={`Выбрать изменение: ${proposal.title}`}
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
                  {proposalStatus[proposal.status]}
                </span>
              </div>
              <div className="assistant-comparison">
                <div>
                  <span>Было</span>
                  <strong>{before.time}</strong>
                  <small>
                    {before.date} · {before.duration}
                  </small>
                </div>
                <ArrowRight size={18} aria-hidden="true" />
                <div className="assistant-comparison-after">
                  <span>Станет</span>
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
          {error}
        </p>
      ) : null}
      {confirmation ? (
        <div
          className="assistant-apply-confirmation"
          role="group"
          aria-label="Подтверждение изменений"
        >
          <p>
            {confirmation === 'apply'
              ? `Применить выбранные изменения (${selectedPending.length}) к вашему расписанию?`
              : `Вернуть прежнее расписание для выбранных задач (${selectedApplied.length})?`}
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
              {confirmation === 'apply' ? 'Подтвердить изменения' : 'Подтвердить отмену'}
            </button>
            <button
              ref={confirmationCancelRef}
              type="button"
              className="button button-secondary"
              disabled={busy}
              onClick={() => setConfirmation(null)}
            >
              Назад
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
                Применить выбранные{selectedPending.length ? ` (${selectedPending.length})` : ''}
              </button>
              <button
                className="button button-secondary"
                type="button"
                disabled={busy || !selectedPending.length}
                onClick={() => void runAction('reject')}
              >
                <X size={15} aria-hidden="true" />
                Отклонить
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
              Отменить изменения
            </button>
          ) : null}
        </div>
      )}
    </section>
  );
}

export function AssistantPage({
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
  const [selectedId, setSelectedId] = useState<string | undefined>(() => conversations[0]?.id);
  const [draft, setDraft] = useState('');
  const [mode, setMode] = useState<ChatMode>('assistant');
  const [request, setRequest] = useState<SendRequest | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<Conversation | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [focusAfterDelete, setFocusAfterDelete] = useState<string | null | undefined>();
  const [pageError, setPageError] = useState('');
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
  const messages = conversation?.messages ?? [];
  const sending = request?.status === 'sending';
  const requestIsVisible = !!request && request.conversationId === selectedId;
  const visibleRequest = requestIsVisible ? request : null;
  const orderedConversations = [...conversations].sort((a, b) =>
    b.updatedAt.localeCompare(a.updatedAt),
  );

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
    setDraft(initialPrompt);
    inputRef.current?.focus();
    onPromptConsumed?.();
  }, [initialPrompt, onPromptConsumed]);

  useEffect(() => {
    if (logRef.current && nearBottom.current) {
      logRef.current.scrollTo({ top: logRef.current.scrollHeight, behavior: 'instant' });
    }
  }, [selectedId, messages.length, request?.status]);

  function chooseConversation(id: string) {
    if (sending) return;
    focusAfterHistory.current = historyOpen && window.matchMedia('(max-width: 800px)').matches;
    setSelectedId(id);
    setHistoryOpen(false);
    setPageError('');
    nearBottom.current = true;
  }

  function choosePrompt(prompt: string) {
    setDraft(prompt);
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
      setDraft('');
      setHistoryOpen(false);
      deleteTriggerRef.current = null;
      setDeleteTarget(null);
      nearBottom.current = true;
      inputRef.current?.focus();
    } catch (error) {
      setPageError(getErrorMessage(error));
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
      if (selectedId === deleteTarget.id) setSelectedId(nextId);
      if (request?.conversationId === deleteTarget.id) setRequest(null);
      deleteTriggerRef.current = null;
      setDeleteTarget(null);
      setFocusAfterDelete(nextId ?? null);
    } catch (error) {
      setPageError(getErrorMessage(error));
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
      (!retry && request?.status === 'failed')
    )
      return;
    const next: SendRequest = retry
      ? { ...retry, status: 'sending', error: undefined }
      : {
          conversationId: selectedId,
          message: text,
          requestId: crypto.randomUUID(),
          mode,
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
      const result = await onSend(next.conversationId, next.message, next.requestId, next.mode);
      if (composerFocusRequest.current?.requestId === next.requestId)
        composerFocusRequest.current.conversationId = result.id;
      setSelectedId(result.id);
      setRequest(null);
    } catch (error) {
      setRequest({ ...next, status: 'failed', error: getErrorMessage(error) });
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
    <div className="assistant-page">
      <header className="page-heading assistant-page-heading">
        <div>
          <p className="page-eyebrow">Меньше рутины. Больше твоего времени.</p>
          <h1>ИИ-помощник</h1>
          <p className="page-description">Вместе найдём твой темп.</p>
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
            История
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
            Новый диалог
          </button>
        </div>
      </header>
      {pageError ? (
        <div className="assistant-page-error" role="alert">
          {pageError}
          <button
            type="button"
            aria-label="Закрыть сообщение об ошибке"
            onClick={() => setPageError('')}
          >
            <X size={16} aria-hidden="true" />
          </button>
        </div>
      ) : null}
      {request?.status === 'failed' && !requestIsVisible ? (
        <div className="assistant-retry-outside" role="status">
          <span>В другом диалоге осталось неотправленное сообщение.</span>
          <button
            type="button"
            className="button button-secondary"
            onClick={() => setSelectedId(request.conversationId)}
          >
            Вернуться к сообщению
          </button>
        </div>
      ) : null}
      <div className="assistant-layout">
        <aside
          ref={historyRef}
          className={`panel assistant-history ${historyOpen ? 'assistant-history--open' : ''}`}
          id="assistant-history"
          aria-label="История диалогов"
        >
          <div className="assistant-history-title">
            <h2>Диалоги</h2>
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
                    title={item.title || 'Новый диалог'}
                    aria-current={selectedId === item.id ? 'true' : undefined}
                    type="button"
                    disabled={sending || deleting}
                    onClick={() => chooseConversation(item.id)}
                  >
                    <MessageSquare size={15} aria-hidden="true" />
                    <span>{item.title || 'Новый диалог'}</span>
                  </button>
                  <button
                    className="assistant-conversation-delete"
                    type="button"
                    disabled={sending || deleting}
                    aria-label={`Удалить диалог «${item.title || 'Новый диалог'}»`}
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
              <p>Ваши диалоги появятся здесь.</p>
            </div>
          )}
          {deleteTarget ? (
            <div
              className="assistant-delete-confirmation"
              role="group"
              aria-label="Подтверждение удаления диалога"
            >
              <strong>Удалить диалог?</strong>
              <p>«{deleteTarget.title || 'Новый диалог'}» и его сообщения будут удалены.</p>
              <div>
                <button
                  ref={deleteCancelRef}
                  type="button"
                  className="button button-secondary"
                  disabled={deleting}
                  onClick={() => setDeleteTarget(null)}
                >
                  Оставить
                </button>
                <button
                  type="button"
                  className="button button-secondary assistant-delete-button"
                  disabled={deleting}
                  onClick={() => void deleteConversation()}
                >
                  {deleting ? 'Удаляем…' : 'Удалить'}
                </button>
              </div>
            </div>
          ) : null}
          <div className="assistant-history-note">
            <ShieldCheck size={17} aria-hidden="true" />
            <p>Расписание меняется только с вашего согласия.</p>
          </div>
        </aside>
        <section className="panel assistant-chat" aria-label="Диалог с помощником Ritm">
          <header className="assistant-chat-header">
            <span className="assistant-orb" aria-hidden="true" />
            <div>
              <h2>{mode === 'idea_review' ? 'Разбор идей' : 'Помощник Ritm'}</h2>
              <p>
                {aiStatus.configured
                  ? 'Готов к вашему запросу'
                  : 'Настройте OpenAI для начала диалога'}
              </p>
            </div>
            <span
              className={`assistant-connection ${aiStatus.configured ? 'assistant-connection--ready' : ''}`}
            >
              <i aria-hidden="true" />
              {aiStatus.configured ? 'Ключ настроен' : 'Не настроен'}
            </span>
            <div className="assistant-mode-switch" role="group" aria-label="Режим ИИ">
              <button
                type="button"
                aria-pressed={mode === 'assistant'}
                disabled={sending || creating || deleting || request?.status === 'failed'}
                onClick={() => setMode('assistant')}
              >
                Помощник
              </button>
              <button
                type="button"
                aria-pressed={mode === 'idea_review'}
                disabled={sending || creating || deleting || request?.status === 'failed'}
                onClick={() => setMode('idea_review')}
              >
                Разбор идей
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
                  {mode === 'idea_review' ? 'Посмотрим на идею с четырёх сторон' : 'С чего начнём?'}
                </h3>
                <p>
                  {mode === 'idea_review'
                    ? 'Опишите идею, для кого она и чего вы хотите добиться. Получите отдельные оценки экспертов и общий вывод, включая разногласия.'
                    : 'Помогу распределить дела, найти свободное время и сделать первый шаг.'}
                </p>
                {mode === 'idea_review' ? (
                  <div className="assistant-idea-roles">
                    {Object.entries(ideaExpertRoles).map(([id, role]) => (
                      <div className="assistant-idea-role" key={id}>
                        <strong>{role.title}</strong>
                        <p>{role.description}</p>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="assistant-welcome-prompts">
                    {prompts.map(({ title, subtitle, icon: Icon }) => (
                      <button type="button" key={title} onClick={() => choosePrompt(title)}>
                        <span>
                          <Icon size={19} aria-hidden="true" />
                        </span>
                        <div>
                          <strong>{title}</strong>
                          <small>{subtitle}</small>
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
                      <strong>Помощник пока не подключён</strong>
                      <p>
                        Добавьте API-ключ OpenAI в настройках. После подключения Ritm сможет
                        отвечать на ваши запросы.
                      </p>
                    </div>
                    <button
                      className="button button-secondary"
                      type="button"
                      onClick={onOpenSettings}
                    >
                      Открыть настройки
                    </button>
                  </div>
                ) : null}
              </div>
            ) : null}
            <div
              className="assistant-messages"
              role="log"
              aria-label="Сообщения диалога"
              aria-live="polite"
              aria-relevant="additions"
            >
              {messages.map((message) => (
                <article
                  className={`assistant-message assistant-message--${message.role}`}
                  key={message.id}
                >
                  <span className="assistant-message-author">
                    {message.role === 'user' ? 'Вы' : 'Ritm'}
                  </span>
                  {message.ideaReview ? (
                    <IdeaReviewPanel report={message.ideaReview} />
                  ) : (
                    <div className="assistant-message-text">{message.text}</div>
                  )}
                  {message.steps.length ? (
                    <div className="assistant-steps">
                      <h3>Понятные шаги</h3>
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
                    <span className="assistant-message-author">Вы</span>
                    <div className="assistant-message-text">{visibleRequest.message}</div>
                    <small>
                      {visibleRequest.status === 'sending'
                        ? 'Отправляем…'
                        : 'Не удалось получить ответ'}
                    </small>
                  </article>
                  {visibleRequest.status === 'sending' ? (
                    <div className="assistant-waiting" role="status">
                      <span className="assistant-orb assistant-orb--small" aria-hidden="true" />
                      <span>
                        {visibleRequest.mode === 'idea_review'
                          ? 'Эксперты оценивают идею…'
                          : 'Ritm изучает ваши планы'}
                        <span className="assistant-thinking-dots" aria-hidden="true">
                          <i />
                          <i />
                          <i />
                        </span>
                      </span>
                    </div>
                  ) : (
                    <div className="assistant-request-error" role="alert">
                      <strong>Не удалось получить ответ</strong>
                      <p>{visibleRequest.error}</p>
                      <div>
                        <button
                          type="button"
                          className="button button-secondary"
                          disabled={!aiStatus.configured || sending}
                          onClick={() => void sendMessage(visibleRequest)}
                        >
                          <RefreshCw size={15} aria-hidden="true" />
                          Повторить
                        </button>
                        <button
                          type="button"
                          className="button button-secondary"
                          onClick={() => {
                            setDraft(visibleRequest.message);
                            setMode(visibleRequest.mode);
                            setRequest(null);
                            inputRef.current?.focus();
                          }}
                        >
                          Изменить сообщение
                        </button>
                        {!aiStatus.configured ? (
                          <button
                            type="button"
                            className="button button-secondary"
                            onClick={onOpenSettings}
                          >
                            Настройки
                          </button>
                        ) : null}
                      </div>
                    </div>
                  )}
                </>
              ) : null}
            </div>
          </div>
          <div className="assistant-composer-area">
            {messages.length && mode === 'assistant' ? (
              <div className="assistant-prompt-chips" aria-label="Быстрые запросы">
                {prompts.map(({ title }) => (
                  <button
                    type="button"
                    key={title}
                    disabled={sending}
                    onClick={() => choosePrompt(title)}
                  >
                    {title}
                  </button>
                ))}
              </div>
            ) : null}
            {!aiStatus.configured && messages.length ? (
              <div className="assistant-compact-setup">
                <span>Для новых ответов подключите OpenAI.</span>
                <button type="button" onClick={onOpenSettings}>
                  Настройки <ArrowRight size={13} aria-hidden="true" />
                </button>
              </div>
            ) : null}
            {mode === 'idea_review' ? (
              <p className="assistant-idea-hint" id="assistant-idea-hint">
                Четыре отдельные оценки и общий вывод. Одна модель, пять запросов OpenAI; без
                проверки фактов в интернете.
              </p>
            ) : null}
            <form className="assistant-composer" onSubmit={submit}>
              <label htmlFor="assistant-message-input" className="assistant-sr-only">
                {mode === 'idea_review' ? 'Идея для разбора экспертами' : 'Сообщение ИИ-помощнику'}
              </label>
              <textarea
                id="assistant-message-input"
                name="message"
                ref={inputRef}
                value={draft}
                rows={2}
                maxLength={6000}
                placeholder={
                  mode === 'idea_review' ? 'Опишите вашу идею…' : 'Спросите о своих планах…'
                }
                disabled={sending}
                onChange={(event) => setDraft(event.target.value)}
                onKeyDown={handleComposerKey}
                aria-describedby={
                  mode === 'idea_review'
                    ? 'assistant-idea-hint assistant-composer-hint'
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
                  request?.status === 'failed'
                }
                aria-label={sending ? 'Отправка сообщения' : 'Отправить сообщение'}
                title={
                  !aiStatus.configured ? 'Сначала подключите OpenAI в настройках' : 'Отправить'
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
                  ? 'Разбор идеи не меняет ваше расписание'
                  : 'Изменения только после вашего подтверждения'}
              </span>
              <span className="assistant-key-hint">
                Enter — отправить · Shift + Enter — новая строка
              </span>
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}
