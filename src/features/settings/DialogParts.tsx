import type { ReactNode } from 'react';
import { AlertCircle } from 'lucide-react';
import { useI18n } from '../../lib/i18n';

/** A label on the left, a value or control on the right. */
export function InfoRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="st-info-row">
      <span className="st-info-label">{label}</span>
      <span className="st-info-value">{children}</span>
    </div>
  );
}

/** Inline error; the text is a Russian source string or a server message. */
export function DialogError({ children }: { children: string }) {
  const { t } = useI18n();
  return (
    <p className="st-dialog-error" role="alert">
      <AlertCircle size={16} aria-hidden="true" />
      {t(children)}
    </p>
  );
}
