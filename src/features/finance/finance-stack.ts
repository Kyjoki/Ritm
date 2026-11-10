import type { FinanceCurrency } from '../../../shared/types';
import type { FinanceCard } from './finance-wallet';

/** Pure layout rules of the wallet stack: which card is in front, how the rest peek out, and card colours. */
const STRIP_PX = 44;
const SHRINK_PER_STEP = 0.04;
const DIM_PER_STEP = 0.035;

export type CardTone = 'violet' | 'indigo' | 'plum' | 'teal' | 'graphite' | 'rose' | 'forest';
const ACCOUNT_TONE: Record<FinanceCurrency, CardTone> = {
  KZT: 'violet',
  USD: 'graphite',
  EUR: 'forest',
  RUB: 'rose',
};

/** Stable colour of a card: accounts by currency, deposits alternate, stocks are teal. */
export function cardTones(cards: FinanceCard[]): Map<string, CardTone> {
  let deposits = 0;
  return new Map(
    cards.map((card) => {
      if (card.kind === 'stocks') return [card.id, 'teal'] as const;
      if (card.kind === 'account') return [card.id, ACCOUNT_TONE[card.currency]] as const;
      deposits += 1;
      return [card.id, deposits % 2 ? 'indigo' : 'plum'] as const;
    }),
  );
}

/** Position of card `index` in the stack when `front` is the active one (front is drawn last, lowest). */
export function stackSlot(index: number, front: number, count: number) {
  const depth = index === front ? 0 : index < front ? index + 1 : index;
  return {
    offset: (count - 1 - depth) * STRIP_PX,
    scale: 1 - SHRINK_PER_STEP * depth,
    dim: 1 - DIM_PER_STEP * depth,
    layer: count - depth,
  };
}

/* ---- carousel: the stack opens into a row of cards, the selected one centred ---- */
const CAROUSEL_SCALE = 300 / 350;
const NEIGHBOUR_SCALE = 0.92;
const CAROUSEL_GAP_PX = 12;
const CAROUSEL_TOP_PX = 12;
const OPEN_MS = 380;
const CLOSE_MS = 340;
const SLIDE_MS = 360;
const OPEN_STAGGER_MS = 30;
const CLOSE_STAGGER_MS = 25;

/** Card box in carousel mode; percentages are of the card's own width (x) and height (y). */
export function carouselSlot(index: number, centre: number) {
  const offset = index - centre;
  const distance = Math.abs(offset);
  const scale = CAROUSEL_SCALE * (1 - (1 - NEIGHBOUR_SCALE) * Math.min(distance, 1));
  const nearStep = (CAROUSEL_SCALE * (1 + NEIGHBOUR_SCALE)) / 2;
  const farStep = CAROUSEL_SCALE * NEIGHBOUR_SCALE;
  const widths =
    distance <= 1 ? offset * nearStep : Math.sign(offset) * (nearStep + (distance - 1) * farStep);
  return {
    xPercent: widths * 100,
    xPx: offset * CAROUSEL_GAP_PX,
    yPercent: ((CAROUSEL_SCALE - scale) / 2) * 100,
    yPx: CAROUSEL_TOP_PX,
    scale,
    dim: 1 - 0.14 * Math.min(distance, 1),
    layer: 100 - Math.round(distance * 10),
  };
}

export type WalletTap =
  | { kind: 'open'; index: number }
  | { kind: 'collapse'; index: number }
  | { kind: 'select'; index: number };

/** What a tap on card `tapped` does: open the stack, collapse on the centred card, or move a neighbour in. */
export function tapOutcome(open: boolean, selected: number, tapped: number): WalletTap {
  if (!open) return { kind: 'open', index: tapped };
  return tapped === selected
    ? { kind: 'collapse', index: tapped }
    : { kind: 'select', index: tapped };
}

/** Arrow-key step within the carousel; it stops at both ends. */
export function stepIndex(current: number, delta: number, count: number): number {
  return Math.min(Math.max(current + delta, 0), Math.max(count - 1, 0));
}

export type WalletMotion = 'open' | 'close' | 'slide';

/** Per-card transition: the stack fans out from the selected card and folds back towards it. */
export function cardTiming(kind: WalletMotion, index: number, anchor: number, count: number) {
  const distance = Math.abs(index - anchor);
  const farthest = Math.max(anchor, count - 1 - anchor);
  if (kind === 'open') return { durationMs: OPEN_MS, delayMs: distance * OPEN_STAGGER_MS };
  if (kind === 'close') {
    return { durationMs: CLOSE_MS, delayMs: (farthest - distance) * CLOSE_STAGGER_MS };
  }
  return { durationMs: SLIDE_MS, delayMs: 0 };
}
