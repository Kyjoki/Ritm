import { useCallback, useId, useState, type CSSProperties, type ReactNode } from 'react';
import { ChevronRight, type LucideIcon } from 'lucide-react';
import type { Tone } from './settings-summaries';

export interface Accordion {
  openId: string | null;
  toggle: (id: string) => void;
}

/** At most one inline section is open at a time. */
export function useAccordion(): Accordion {
  const [openId, setOpenId] = useState<string | null>(null);
  const toggle = useCallback(
    (id: string) => setOpenId((current) => (current === id ? null : id)),
    [],
  );
  return { openId, toggle };
}

export function Group({
  title,
  label,
  children,
}: {
  title?: string;
  label?: string;
  children: ReactNode;
}) {
  const headingId = useId();
  return (
    <section aria-labelledby={title ? headingId : undefined} aria-label={title ? undefined : label}>
      {title ? (
        <h2 id={headingId} className="st-group-label">
          {title}
        </h2>
      ) : null}
      <div className="st-group">{children}</div>
    </section>
  );
}

/** Colour slot 0-5 of the settings palette. */
export type TileTone = 0 | 1 | 2 | 3 | 4 | 5;

export function Tile({ icon: Icon, tone }: { icon: LucideIcon; tone: TileTone }) {
  return (
    <span className="st-tile" style={{ '--tc': `var(--st-c${tone})` } as CSSProperties}>
      <Icon size={17} aria-hidden="true" />
    </span>
  );
}

export function StatusDot({ tone }: { tone: Tone }) {
  return <span className={`st-dot st-dot-${tone}`} aria-hidden="true" />;
}

export function StatusText({ tone, children }: { tone: Tone; children: ReactNode }) {
  return (
    <span className={`st-value st-value-${tone}`}>
      <StatusDot tone={tone} />
      {children}
    </span>
  );
}

interface ExpandItemProps {
  id: string;
  accordion: Accordion;
  children: ReactNode;
  /** Replaces the icon, title and value of a standard row (the profile row). */
  lead?: ReactNode;
  icon?: LucideIcon;
  tone?: TileTone;
  title?: string;
  value?: ReactNode;
  className?: string;
}

/** A row that unfolds its controls right below it. */
export function ExpandItem({
  id,
  accordion,
  children,
  lead,
  icon,
  tone = 0,
  title,
  value,
  className = '',
}: ExpandItemProps) {
  const panelId = useId();
  const open = accordion.openId === id;
  return (
    <div className={`st-item ${className}`} data-open={open}>
      <button
        type="button"
        className="st-row st-row-button"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={() => accordion.toggle(id)}
      >
        {lead ?? (
          <>
            {icon ? <Tile icon={icon} tone={tone} /> : null}
            <span className="st-title">{title}</span>
            <span className="st-value">{value}</span>
          </>
        )}
        <ChevronRight className="st-chev" size={16} aria-hidden="true" />
      </button>
      <div className="st-exp" id={panelId} role="group" aria-label={title} inert={!open}>
        <div className="st-exp-in">
          <div className="st-pad">{children}</div>
        </div>
      </div>
    </div>
  );
}

export function Switch({
  checked,
  label,
  disabled = false,
  onChange,
}: {
  checked: boolean;
  label: string;
  disabled?: boolean;
  onChange: (next: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      className="st-switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
    />
  );
}

/** A row without a section of its own: a title, an optional value and a control. */
export function FlatRow({
  icon,
  tone,
  title,
  children,
}: {
  icon: LucideIcon;
  tone: TileTone;
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="st-item">
      <div className="st-row">
        <Tile icon={icon} tone={tone} />
        <span className="st-title">{title}</span>
        {children}
      </div>
    </div>
  );
}

interface OpenRowProps {
  icon: LucideIcon;
  tone: TileTone;
  title: string;
  /** Right-hand text when there is no quick action. */
  status?: ReactNode;
  /** Short action shown in the row; it works without opening the details. */
  quickLabel?: string | null;
  quickTone?: Tone;
  quickBusy?: boolean;
  danger?: boolean;
  attention?: boolean;
  ariaLabel?: string;
  onOpen: () => void;
  onQuick?: () => void;
}

/** A row that opens a dialog, optionally with a separate quick-action button inside. */
export function OpenRow({
  icon,
  tone,
  title,
  status,
  quickLabel,
  quickTone = 'idle',
  quickBusy = false,
  danger = false,
  attention = false,
  ariaLabel,
  onOpen,
  onQuick,
}: OpenRowProps) {
  const hasQuick = Boolean(quickLabel && onQuick);
  return (
    <div className="st-item" data-attention={attention} data-danger={danger}>
      <button
        type="button"
        className="st-row st-row-button"
        aria-label={ariaLabel}
        data-quick={hasQuick}
        onClick={onOpen}
      >
        <Tile icon={icon} tone={tone} />
        <span className="st-title">{title}</span>
        {hasQuick ? null : <span className="st-value">{status}</span>}
        <ChevronRight className="st-chev" size={16} aria-hidden="true" />
      </button>
      {hasQuick ? (
        <button
          type="button"
          className={`st-quick st-quick-${quickTone}`}
          disabled={quickBusy}
          data-busy={quickBusy}
          onClick={onQuick}
        >
          {quickLabel}
        </button>
      ) : null}
    </div>
  );
}

export function FieldError({ id, children }: { id: string; children: string }) {
  return (
    <small id={id} className="st-field-error" role="alert">
      {children}
    </small>
  );
}
