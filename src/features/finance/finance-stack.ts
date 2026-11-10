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
