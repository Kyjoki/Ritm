import { useRef, type CSSProperties, type KeyboardEvent, type ReactNode } from 'react';

export interface Choice<V extends string | number> {
  value: V;
  /** Visible text unless `content` is given. */
  label: string;
  content?: ReactNode;
}

interface ChoiceGroupProps<V extends string | number> {
  label: string;
  value: V;
  choices: readonly Choice<V>[];
  onChange: (value: V, trigger: Element) => void;
  className?: string;
  choiceClassName?: string;
  /** Selected index drives the sliding thumb of the segmented variant. */
  style?: CSSProperties;
}

const MOVE_KEYS: Record<string, number> = {
  ArrowRight: 1,
  ArrowDown: 1,
  ArrowLeft: -1,
  ArrowUp: -1,
};

/**
 * A radio group with a roving tab stop. Arrow keys, Home and End move focus between the
 * choices; Space or Enter picks the focused one, so browsing never triggers a save.
 */
export function ChoiceGroup<V extends string | number>({
  label,
  value,
  choices,
  onChange,
  className = '',
  choiceClassName = '',
  style,
}: ChoiceGroupProps<V>) {
  const group = useRef<HTMLDivElement>(null);
  const selected = choices.findIndex((choice) => choice.value === value);
  const tabStop = selected >= 0 ? selected : 0;

  function moveFocus(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    const step = MOVE_KEYS[event.key];
    const target = event.key === 'Home' ? 0 : event.key === 'End' ? choices.length - 1 : undefined;
    const next =
      target ?? (step === undefined ? undefined : (index + step + choices.length) % choices.length);
    if (next === undefined) return;
    event.preventDefault();
    group.current?.querySelectorAll<HTMLButtonElement>('[role="radio"]')[next]?.focus();
  }

  return (
    <div ref={group} role="radiogroup" aria-label={label} className={className} style={style}>
      {choices.map((choice, index) => (
        <button
          key={choice.value}
          type="button"
          role="radio"
          aria-checked={choice.value === value}
          tabIndex={index === tabStop ? 0 : -1}
          className={choiceClassName}
          onClick={(event) => onChange(choice.value, event.currentTarget)}
          onKeyDown={(event) => moveFocus(event, index)}
        >
          {choice.content ?? choice.label}
        </button>
      ))}
    </div>
  );
}
