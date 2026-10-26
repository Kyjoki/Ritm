import { useEffect, useRef, type ReactNode } from 'react';
import { X } from 'lucide-react';
import { useI18n } from '../lib/i18n';
import { activateDialogViewport } from '../lib/dialog-viewport';

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
  const exitTimer = useRef<number | null>(null);
  closeRef.current = onClose;
  const requestClose = () => {
    const dialog = ref.current;
    if (busy || !dialog || exitTimer.current !== null) return;
    dialog.classList.add('is-closing');
    exitTimer.current = window.setTimeout(
      () => {
        exitTimer.current = null;
        closeRef.current();
      },
      window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 120 : 180,
    );
  };
  useEffect(() => {
    const dialog = ref.current!;
    const previous = document.activeElement as HTMLElement | null;
    dialog.showModal();
    const releaseViewport = activateDialogViewport(dialog);
    dialog
      .querySelector<HTMLElement>(
        'input:not([type="hidden"]):not([type="radio"]):not([type="checkbox"]):not(:disabled), textarea:not(:disabled), select:not(:disabled)',
      )
      ?.focus({ preventScroll: true });
    return () => {
      if (exitTimer.current !== null) window.clearTimeout(exitTimer.current);
      dialog.close();
      releaseViewport();
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
        requestClose();
      }}
      onClick={(event) => {
        if ((event.target as HTMLElement).closest('[data-dialog-dismiss]')) {
          event.preventDefault();
          requestClose();
          return;
        }
        if (!busy && event.target === event.currentTarget) {
          const bounds = event.currentTarget.getBoundingClientRect();
          if (
            event.clientX < bounds.left ||
            event.clientX > bounds.right ||
            event.clientY < bounds.top ||
            event.clientY > bounds.bottom
          )
            requestClose();
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
          onClick={requestClose}
          disabled={busy}
        >
          <X size={20} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
