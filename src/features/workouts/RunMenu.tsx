import { useEffect, useRef, useState, type ReactNode } from 'react';
import { ArrowLeftRight, Check, CircleMinus, List, MoreVertical, Plus, Trash2 } from 'lucide-react';
import { useI18n } from '../../lib/i18n';
import type { RunActions } from './RunView';

/** The ⋮ menu of the running workout: exercise list, add, replace, remove, finish, cancel. */
export function RunMenu({
  actions,
  current,
  index,
  canRemove,
}: {
  actions: RunActions;
  current: string;
  index: number;
  canRemove: boolean;
}) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const wrap = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    wrap.current
      ?.querySelector<HTMLElement>('[role="menuitem"]:not(:disabled)')
      ?.focus({ preventScroll: true });
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && setOpen(false);
    const onDown = (event: PointerEvent) => {
      if (!wrap.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onDown);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('pointerdown', onDown);
    };
  }, [open]);
  const item = (
    icon: ReactNode,
    label: string,
    run: () => void,
    extra: { danger?: boolean; narrow?: boolean; disabled?: boolean } = {},
  ) => (
    <button
      type="button"
      role="menuitem"
      disabled={extra.disabled}
      className={extra.narrow ? 'narrow-only' : undefined}
      data-danger={extra.danger ? '1' : undefined}
      onClick={() => {
        setOpen(false);
        run();
      }}
    >
      {icon}
      <span>{label}</span>
    </button>
  );
  return (
    <div className="wk-mw" ref={wrap}>
      <button
        type="button"
        className="wk-ib"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={t('Меню тренировки')}
        onClick={() => setOpen(!open)}
      >
        <MoreVertical className="wk-i" aria-hidden="true" />
      </button>
      {open ? (
        <div className="wk-menu" role="menu">
          {item(<List className="wk-i" />, t('Упражнения и порядок'), actions.onList, {
            narrow: true,
          })}
          {item(<Plus className="wk-i" />, t('Добавить после текущего'), () =>
            actions.onAdd(index),
          )}
          {item(<Plus className="wk-i" />, t('Добавить в конец'), () => actions.onAdd(null))}
          {item(<ArrowLeftRight className="wk-i" />, t('Заменить текущее'), () =>
            actions.onReplace(current),
          )}
          {item(
            <CircleMinus className="wk-i" />,
            t('Убрать текущее'),
            () => actions.onRemove(current),
            {
              disabled: !canRemove,
            },
          )}
          <hr />
          {item(<Check className="wk-i" />, t('Завершить тренировку'), actions.onFinish)}
          {item(<Trash2 className="wk-i" />, t('Отменить тренировку'), actions.onCancel, {
            danger: true,
          })}
        </div>
      ) : null}
    </div>
  );
}
