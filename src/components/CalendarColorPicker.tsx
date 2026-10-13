import { Check } from 'lucide-react';
import type { CSSProperties } from 'react';
import { CALENDAR_PALETTE } from '../../shared/calendar-colors';
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
  const current = CALENDAR_PALETTE.find((color) => color.id === value || color.hex === value);
  const selected = current?.id ?? value ?? '';
  const custom =
    !current && value && /^#[0-9a-f]{6}$/i.test(value)
      ? [{ id: value, name: 'Цвет Google', hex: value }]
      : [];
  const colors = [
    ...CALENDAR_PALETTE,
    ...custom,
    { id: '', name: 'По умолчанию', hex: 'var(--accent)' },
  ];
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
              checked={selected === color.id}
              onChange={() => onChange(color.id || null)}
              aria-label={color.name}
            />
            <span
              style={
                {
                  '--swatch': color.hex,
                  '--swatch-ink': ['5', '#e4c441', '#c0ca33', '#b39ddb'].includes(color.id)
                    ? '#21192d'
                    : '#ffffff',
                } as CSSProperties
              }
            >
              {selected === color.id ? <Check size={15} aria-hidden="true" /> : null}
            </span>
          </label>
        ))}
      </div>
      <small>{current?.name ?? (value ? 'Цвет Google' : 'По умолчанию')}</small>
    </fieldset>
  );
}
