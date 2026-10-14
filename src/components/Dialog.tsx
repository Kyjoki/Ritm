import { useEffect, useRef, type ReactNode } from 'react';
import { X } from 'lucide-react';
import { useI18n } from '../lib/i18n';

export function Dialog({
  title,
  children,
  onClose,
  busy = false,
  className = '',
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  busy?: boolean;
  className?: string;
}) {
  const { t: tr } = useI18n();
  const ref = useRef<HTMLDialogElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    const dialog = ref.current!;
    const previous = document.activeElement as HTMLElement | null;
    dialog.showModal();
    dialog
      .querySelector<HTMLElement>(
        'input:not([type="hidden"]):not([type="radio"]):not([type="checkbox"]):not(:disabled), textarea:not(:disabled), select:not(:disabled)',
      )
      ?.focus({ preventScroll: true });
    return () => {
      dialog.close();
      const target =
        previous?.isConnected && previous.getClientRects().length
          ? previous
          : document.getElementById('main-content');
      target?.focus({ preventScroll: true });
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className={`dialog ${className}`}
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) closeRef.current();
      }}
      onClick={(event) => {
        if (!busy && event.target === event.currentTarget) {
          const bounds = event.currentTarget.getBoundingClientRect();
          if (
            event.clientX < bounds.left ||
            event.clientX > bounds.right ||
            event.clientY < bounds.top ||
            event.clientY > bounds.bottom
          )
            onClose();
        }
      }}
      aria-labelledby="dialog-title"
    >
      <div className="dialog-head">
        <div>
          <span className="page-eyebrow">{tr('RITM · ВАШ ПЛАН')}</span>
          <h2 id="dialog-title">{title}</h2>
        </div>
        <button
          type="button"
          className="icon-button"
          aria-label={tr('Закрыть')}
          onClick={onClose}
          disabled={busy}
        >
          <X size={20} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
