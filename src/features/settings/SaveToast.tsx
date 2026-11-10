import { AlertCircle, Check, X } from 'lucide-react';
import { useI18n } from '../../lib/i18n';
import type { SaveFeedback } from './useSaveFeedback';

/** Floating "Сохранено" pill; errors stay longer and can be dismissed. */
export function SaveToast({ feedback }: { feedback: SaveFeedback }) {
  const { t } = useI18n();
  const { message } = feedback;
  return (
    <div className="st-toast-dock">
      {message?.kind === 'saved' ? (
        <div key={message.id} className="st-toast" role="status">
          <Check size={16} aria-hidden="true" />
          {message.message || t('Сохранено')}
        </div>
      ) : null}
      {message?.kind === 'error' ? (
        <div key={message.id} className="st-toast st-toast-error" role="alert">
          <AlertCircle size={16} aria-hidden="true" />
          <span>{message.message}</span>
          <button type="button" aria-label={t('Закрыть')} onClick={feedback.dismiss}>
            <X size={15} aria-hidden="true" />
          </button>
        </div>
      ) : null}
    </div>
  );
}
