import { useRef, useState, type KeyboardEvent } from 'react';
import { useI18n } from '../../lib/i18n';
import { stepIndex, tapOutcome, type WalletMotion, type WalletTap } from './finance-stack';
import type { FinanceCard } from './finance-wallet';

const MOTION_OF_TAP: Record<WalletTap['kind'], WalletMotion> = {
  open: 'open',
  collapse: 'close',
  select: 'slide',
};

/**
 * Open/collapse state of the wallet. The stack is open exactly while a card is selected, so the selected
 * card keeps driving the right column; collapsing clears the selection and remembers which card stays in front.
 */
export function useWalletStack({
  cards,
  selectedId,
  nameOf,
  onSelect,
}: {
  cards: FinanceCard[];
  selectedId: string | null;
  nameOf: (card: FinanceCard) => string;
  onSelect: (id: string | null) => void;
}) {
  const { t } = useI18n();
  const ref = useRef<HTMLDivElement>(null);
  const [rememberedId, setRememberedId] = useState<string | null>(null);
  const [motion, setMotion] = useState<{ kind: WalletMotion; flip: number }>({
    kind: 'open',
    flip: 0,
  });
  const [captionGone, setCaptionGone] = useState(false);
  const [announcement, setAnnouncement] = useState('');
  const selectedIndex = cards.findIndex((card) => card.id === selectedId);
  const open = selectedIndex >= 0;
  const front = open
    ? selectedIndex
    : Math.max(
        cards.findIndex((c) => c.id === rememberedId),
        0,
      );

  function run(tap: WalletTap) {
    const kind: WalletMotion = MOTION_OF_TAP[tap.kind];
    setMotion((old) => ({ kind, flip: old.flip + 1 }));
    if (tap.kind === 'collapse') {
      setRememberedId(selectedId);
      setCaptionGone(true);
      setAnnouncement(t('Карты собраны'));
      onSelect(null);
      return;
    }
    setAnnouncement(t('Выбран счёт: {name}', { name: nameOf(cards[tap.index]) }));
    onSelect(cards[tap.index].id);
  }
  const tap = (index: number) => run(tapOutcome(open, selectedIndex, index));
  const select = (index: number) => {
    if (open && index !== selectedIndex) run({ kind: 'select', index });
  };

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (!open) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      run({ kind: 'collapse', index: selectedIndex });
      return;
    }
    const delta = { ArrowLeft: -1, ArrowRight: 1 }[event.key as 'ArrowLeft' | 'ArrowRight'];
    if (!delta) return;
    event.preventDefault();
    const next = stepIndex(selectedIndex, delta, cards.length);
    if (next === selectedIndex) return;
    select(next);
    ref.current?.querySelectorAll<HTMLElement>('.fin-card')[next]?.focus({ preventScroll: true });
  }

  return {
    ref,
    open,
    front,
    selectedIndex,
    motion,
    captionGone,
    announcement,
    tap,
    select,
    onKeyDown,
  };
}
