import { Check } from 'lucide-react';
import type { CSSProperties } from 'react';
import { CALENDAR_COLORS } from '../../shared/calendar-colors';
import '../styles/calendar-colors.css';

export function CalendarColorPicker({
  value,
  onChange,
  disabled = false,
}: {
  value?: string | null;
  onChange: (id: string | null) => void;
  disabled?: boolean;
}) {
  const colors = [{ id: '', name: 'По умолчанию', hex: 'var(--accent)' }, ...CALENDAR_COLORS];
  return (
    <fieldset className="calendar-color-picker" disabled={disabled}>
      <legend>Цвет записи</legend>
      <div className="calendar-color-options">
        {colors.map((color) => (
          <label className="calendar-color-option" key={color.id} title={color.name}>
            <input
              type="radio"
              name="calendar-color"
              value={color.id}
              checked={(value ?? '') === color.id}
              onChange={() => onChange(color.id || null)}
              aria-label={color.name}
            />
            <span style={{ '--swatch': color.hex } as CSSProperties}>
              {(value ?? '') === color.id ? <Check size={15} aria-hidden="true" /> : null}
            </span>
          </label>
        ))}
      </div>
      <small>{colors.find((color) => color.id === (value ?? ''))?.name ?? 'По умолчанию'}</small>
    </fieldset>
  );
}
