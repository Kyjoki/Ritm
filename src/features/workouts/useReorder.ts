import { useRef, type KeyboardEvent, type PointerEvent } from 'react';

interface Drag {
  row: HTMLElement;
  rows: HTMLElement[];
  from: number;
  to: number;
  y0: number;
  pointer: number;
  height: number;
}
const clamp = (value: number, low: number, high: number) => Math.min(high, Math.max(low, value));

/**
 * Drag a row by its grip (pointer) or move it with ArrowUp / ArrowDown on the focused grip.
 * Rows are the children of the list element that carry `data-row`; the order is changed through
 * `onMove` only, never by touching the DOM permanently.
 */
export function useReorder(onMove: (from: number, to: number) => void) {
  const list = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const rowsOf = () => [
    ...(list.current?.querySelectorAll<HTMLElement>(':scope > [data-row]') ?? []),
  ];

  const down = (event: PointerEvent<HTMLElement>, index: number) => {
    if (event.button) return;
    const rows = rowsOf();
    const row = rows[index];
    if (!row) return;
    const height =
      rows.length > 1
        ? rows[1].getBoundingClientRect().top - rows[0].getBoundingClientRect().top
        : row.offsetHeight;
    drag.current = {
      row,
      rows,
      from: index,
      to: index,
      y0: event.clientY,
      pointer: event.pointerId,
      height,
    };
    row.classList.add('lift');
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      /* capture is optional */
    }
    event.preventDefault();
  };
  const move = (event: PointerEvent<HTMLElement>) => {
    const d = drag.current;
    if (!d || event.pointerId !== d.pointer) return;
    const dy = event.clientY - d.y0;
    d.to = clamp(Math.round(d.from + dy / d.height), 0, d.rows.length - 1);
    d.row.style.transform = `translateY(${dy}px)`;
    d.rows.forEach((row, index) => {
      if (row === d.row) return;
      const shift =
        d.from < d.to && index > d.from && index <= d.to
          ? -d.height
          : d.from > d.to && index < d.from && index >= d.to
            ? d.height
            : 0;
      row.style.transform = shift ? `translateY(${shift}px)` : '';
    });
  };
  const up = (event: PointerEvent<HTMLElement>) => {
    const d = drag.current;
    if (!d || event.pointerId !== d.pointer) return;
    drag.current = null;
    d.row.classList.remove('lift');
    d.rows.forEach((row) => (row.style.transform = ''));
    if (d.to !== d.from) onMove(d.from, d.to);
  };
  const key = (event: KeyboardEvent<HTMLElement>, index: number) => {
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    event.preventDefault();
    const to = index + (event.key === 'ArrowUp' ? -1 : 1);
    if (to < 0 || to >= rowsOf().length) return;
    onMove(index, to);
    const grip = event.currentTarget;
    window.setTimeout(() => {
      const grips = list.current?.querySelectorAll<HTMLElement>('[data-grip]');
      (grips?.[to] ?? grip).focus({ preventScroll: true });
    }, 0);
  };
  const gripProps = (index: number) => ({
    'data-grip': true,
    onPointerDown: (event: PointerEvent<HTMLElement>) => down(event, index),
    onPointerMove: move,
    onPointerUp: up,
    onPointerCancel: up,
    onKeyDown: (event: KeyboardEvent<HTMLElement>) => key(event, index),
  });
  return { list, gripProps };
}
