import type { ReactNode } from 'react';
import { Pencil, Trash2 } from 'lucide-react';
import { useI18n } from '../../lib/i18n';

/** Edit and delete buttons of a row; delete asks for a second tap and resets once the request ends. */
export function RowActions({
  label,
  confirming,
  deleting,
  onAskDelete,
  onCancel,
  onEdit,
  onDelete,
  extra,
}: {
  label: string;
  confirming: boolean;
  deleting: boolean;
  onAskDelete: () => void;
  onCancel: () => void;
  onEdit: () => void;
  onDelete: () => Promise<void> | void;
  extra?: ReactNode;
}) {
  const { t } = useI18n();
  if (confirming)
    return (
      <span className="fin-row-actions">
        <button
          type="button"
          className="is-danger"
          disabled={deleting}
          onClick={() => void Promise.resolve(onDelete()).then(onCancel)}
        >
          {deleting ? t('Удаляем…') : t('Удалить?')}
        </button>
        <button type="button" onClick={onCancel}>
          {t('Отмена')}
        </button>
      </span>
    );
  return (
    <span className="fin-row-actions">
      {extra}
      <button
        type="button"
        aria-label={`${t('Изменить')} ${label}`}
        title={t('Изменить')}
        onClick={onEdit}
      >
        <Pencil size={15} />
      </button>
      <button
        type="button"
        aria-label={`${t('Удалить')} ${label}`}
        title={t('Удалить')}
        onClick={onAskDelete}
      >
        <Trash2 size={15} />
      </button>
    </span>
  );
}
