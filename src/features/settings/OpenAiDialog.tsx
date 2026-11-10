import { useId, useState, type FormEvent } from 'react';
import { LoaderCircle, ShieldCheck } from 'lucide-react';
import type { AiStatus } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { DialogError, InfoRow } from './DialogParts';
import type { SaveFeedback } from './useSaveFeedback';

interface OpenAiDialogProps {
  status: AiStatus;
  onConfigure: (apiKey: string, model: string) => Promise<void>;
  onDisconnect: () => Promise<void>;
  onClose: () => void;
  feedback: SaveFeedback;
}

function failureText(failure: unknown): string {
  return failure instanceof Error
    ? failure.message
    : 'Не удалось сохранить изменения. Попробуй ещё раз.';
}

export function OpenAiDialog({
  status,
  onConfigure,
  onDisconnect,
  onClose,
  feedback,
}: OpenAiDialogProps) {
  const { t } = useI18n();
  const keyId = useId();
  const modelId = useId();
  const [replacing, setReplacing] = useState(false);
  const [apiKey, setApiKey] = useState('');
  const [model, setModel] = useState(status.model);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const managed = status.source === 'environment';
  const showForm = !managed && (!status.configured || replacing);

  async function run(operation: () => Promise<void>, message: string) {
    setBusy(true);
    setError('');
    try {
      await operation();
      feedback.showSaved(t(message));
      onClose();
    } catch (failure) {
      setError(failureText(failure));
      setBusy(false);
    }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    void run(() => onConfigure(apiKey.trim(), model.trim()), 'Настройки OpenAI сохранены.');
  }

  return (
    <Dialog title={t('Твой помощник на связи')} onClose={onClose} busy={busy} className="st-dialog">
      {managed ? (
        <>
          <InfoRow label={t('Источник ключа')}>{t('Сервер')}</InfoRow>
          <InfoRow label={t('Модель')}>{status.model}</InfoRow>
          <p className="st-note">{t('Настройкой управляет сервер')}</p>
        </>
      ) : null}
      {!managed && status.configured && !replacing ? (
        <>
          <InfoRow label={t('Ключ')}>{t('Сохранён на сервере')}</InfoRow>
          <InfoRow label={t('Модель')}>{status.model}</InfoRow>
          {error ? <DialogError>{error}</DialogError> : null}
          <div className="dialog-actions">
            <button
              type="button"
              className="button button-danger"
              disabled={busy}
              onClick={() => void run(onDisconnect, 'Сохранённый ключ удалён.')}
            >
              {busy ? t('Удаляем…') : t('Удалить ключ')}
            </button>
            <button
              type="button"
              className="button button-primary"
              onClick={() => setReplacing(true)}
            >
              {t('Заменить ключ')}
            </button>
          </div>
        </>
      ) : null}
      {showForm ? (
        <form className="st-dialog-form" onSubmit={submit}>
          <p className="st-note">
            {t('Добавь ключ OpenAI, чтобы планировать день и разбирать задачи вместе с Ritm.')}
          </p>
          <div className="st-field">
            <label htmlFor={keyId}>{t('API-ключ OpenAI')}</label>
            <input
              id={keyId}
              className="st-input"
              type="password"
              autoComplete="off"
              autoCapitalize="none"
              spellCheck={false}
              required
              minLength={20}
              maxLength={512}
              value={apiKey}
              placeholder="sk-…"
              disabled={busy}
              onChange={(event) => setApiKey(event.target.value)}
            />
          </div>
          <div className="st-field">
            <label htmlFor={modelId}>{t('Модель')}</label>
            <input
              id={modelId}
              className="st-input"
              required
              maxLength={100}
              value={model}
              placeholder={t('Название модели')}
              disabled={busy}
              onChange={(event) => setModel(event.target.value)}
            />
          </div>
          <p className="st-secure">
            <ShieldCheck size={16} aria-hidden="true" />
            {t('Ключ передаётся серверу и не сохраняется в браузере.')}
          </p>
          {error ? <DialogError>{error}</DialogError> : null}
          <div className="dialog-actions">
            <button
              type="button"
              className="button button-secondary"
              disabled={busy}
              data-dialog-dismiss
            >
              {t('Отмена')}
            </button>
            <button
              type="submit"
              className="button button-primary"
              disabled={busy || !apiKey.trim() || !model.trim()}
            >
              {busy ? (
                <>
                  <LoaderCircle className="st-spin" size={16} aria-hidden="true" />
                  {t('Сохраняем…')}
                </>
              ) : (
                t('Сохранить ключ')
              )}
            </button>
          </div>
        </form>
      ) : null}
    </Dialog>
  );
}
