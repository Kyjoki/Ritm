import type { CSSProperties } from 'react';
import { Check, ChartNoAxesCombined, Landmark, Wallet } from 'lucide-react';
import { MotionNumber } from '../../components/Motion';
import { useI18n } from '../../lib/i18n';
import { useMoney } from './finance-format';
import {
  cardTiming,
  cardTones,
  carouselSlot,
  stackSlot,
  type CardTone,
  type WalletMotion,
} from './finance-stack';
import type { FinanceCard } from './finance-wallet';
import { useWalletStack } from './useWalletStack';

const WAVES = [
  {
    fill: 'M-10 221V205C90 205 170 170 245 120S330 70 360 60V221Z',
    lines: [
      'M-10 190C80 190 150 150 215 105S320 30 360 20',
      'M-10 215C90 215 160 180 230 140S330 80 360 70',
    ],
  },
  {
    fill: 'M-10 221V175C70 150 130 205 200 188S310 115 360 135V221Z',
    lines: [
      'M-10 150C60 120 120 190 190 170S300 90 360 110',
      'M-10 182C70 152 130 212 200 196S310 122 360 142',
    ],
  },
];

function CardIcon({ kind }: { kind: FinanceCard['kind'] }) {
  const Icon = kind === 'account' ? Wallet : kind === 'deposit' ? Landmark : ChartNoAxesCombined;
  return <Icon size={26} aria-hidden="true" />;
}

interface CardBox {
  index: number;
  front: number;
  count: number;
  open: boolean;
  selectedIndex: number;
  motion: WalletMotion;
}

/** Inline box of a card: its stack slot while collapsed, its carousel slot while open. */
function cardStyle({ index, front, count, open, selectedIndex, motion }: CardBox): CSSProperties {
  const timing = cardTiming(motion, index, open ? selectedIndex : front, count);
  const slot = open ? carouselSlot(index, selectedIndex) : null;
  const stack = stackSlot(index, front, count);
  const x = slot ? `calc(${slot.xPercent}% + ${slot.xPx}px)` : '0px';
  const y = slot ? `calc(${slot.yPercent}% + ${slot.yPx}px)` : `${stack.offset}px`;
  return {
    transform: `translate3d(${x}, ${y}, 0) scale(${slot ? slot.scale : stack.scale})`,
    filter: `brightness(${slot ? slot.dim : stack.dim})`,
    zIndex: slot ? slot.layer : stack.layer,
    '--dur': `${timing.durationMs}ms`,
    '--delay': `${timing.delayMs}ms`,
  } as CSSProperties;
}

function StackCard({
  card,
  waveIndex,
  tone,
  open,
  strip,
  centred,
  style,
  label,
  name,
  onTap,
}: {
  card: FinanceCard;
  waveIndex: number;
  tone: CardTone | undefined;
  open: boolean;
  strip: boolean;
  centred: boolean;
  style: CSSProperties;
  label: string;
  name: string;
  onTap: () => void;
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  const wave = WAVES[waveIndex % 2];
  const balance = card.balanceMinor;
  const balanceText = balance === null ? '—' : money(balance, card.currency);
  const hint = !open
    ? 'Нажмите, чтобы открыть счёт'
    : centred
      ? 'Нажмите, чтобы свернуть'
      : 'Нажмите, чтобы выбрать';
  const sub =
    card.kind === 'deposit'
      ? 'Депозит'
      : card.kind === 'stocks'
        ? 'Брокерский счёт'
        : 'Расчётный счёт';
  return (
    <button
      type="button"
      className={`fin-card is-${tone}${centred ? ' is-sel' : ''}${strip ? ' is-strip' : ''}`}
      style={style}
      tabIndex={open && !centred ? -1 : 0}
      aria-expanded={open && centred}
      aria-label={`${label}, ${balanceText}. ${t(hint)}`}
      onClick={onTap}
    >
      <svg
        className="fin-card-wave"
        viewBox="0 0 350 221"
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <path className="is-fill" d={wave.fill} />
        {wave.lines.map((line) => (
          <path key={line} d={line} />
        ))}
      </svg>
      <span className="fin-card-face">
        <span className="fin-card-top">
          <span className="fin-card-name">{name}</span>
          <span className="fin-card-sub">{t(sub)}</span>
        </span>
        <span className="fin-card-balance">
          {balance === null ? (
            '—'
          ) : (
            <MotionNumber
              value={balance}
              format={(value) => money(value, card.currency)}
              step={100}
            />
          )}
        </span>
        <span className="fin-card-bottom">
          <span className="fin-card-icon">
            <CardIcon kind={card.kind} />
          </span>
          <span className="fin-card-meta">{card.currency}</span>
        </span>
      </span>
      <span className="fin-card-strip" aria-hidden="true">
        <span className="fin-card-strip-name">{label}</span>
        <span className="fin-card-strip-sum">{balanceText}</span>
      </span>
      <span className="fin-card-check" aria-hidden="true">
        <Check size={16} strokeWidth={2.6} />
      </span>
    </button>
  );
}

/**
 * The wallet: a stack of cards. A tap opens it into a carousel (the tapped card centred and selected);
 * a tap on the centred card folds it back, a tap on a neighbour brings that card to the centre.
 */
export function WalletStack({
  cards,
  selectedId,
  onSelect,
}: {
  cards: FinanceCard[];
  selectedId: string | null;
  onSelect: (id: string | null) => void;
}) {
  const { t } = useI18n();
  const manyCurrencies = new Set(cards.map((card) => card.currency)).size > 1;
  const nameOf = (card: FinanceCard) =>
    card.kind === 'account'
      ? t('Основной счёт')
      : card.kind === 'stocks'
        ? t('Акции')
        : (card.name ?? t('Депозит'));
  const wallet = useWalletStack({ cards, selectedId, nameOf, onSelect });
  if (!cards.length) return null;
  const tones = cardTones(cards);
  const labelOf = (card: FinanceCard) =>
    nameOf(card) + (manyCurrencies ? ` · ${card.currency}` : '');
  const { open, front, selectedIndex, motion } = wallet;
  return (
    <div className="fin-wallet">
      <div
        ref={wallet.ref}
        className="fin-stack"
        role="group"
        aria-label={t('Счета и карты')}
        data-open={open}
        data-motion={motion.kind}
        data-flip={motion.flip % 2}
        style={{ '--n': cards.length } as CSSProperties}
        onKeyDown={wallet.onKeyDown}
      >
        {cards.map((card, index) => (
          <StackCard
            key={card.id}
            card={card}
            waveIndex={index}
            tone={tones.get(card.id)}
            open={open}
            strip={!open && index !== front}
            centred={open && index === selectedIndex}
            style={cardStyle({
              index,
              front,
              count: cards.length,
              open,
              selectedIndex,
              motion: motion.kind,
            })}
            name={nameOf(card)}
            label={labelOf(card)}
            onTap={() => wallet.tap(index)}
          />
        ))}
        <div className="fin-dots">
          {cards.map((card, index) => (
            <button
              key={card.id}
              type="button"
              className="fin-dot"
              aria-current={open && index === selectedIndex}
              aria-label={t('Счёт {number}: {name}', { number: index + 1, name: labelOf(card) })}
              onClick={() => wallet.select(index)}
            />
          ))}
        </div>
        <p className={`fin-cap${wallet.captionGone ? ' is-gone' : ''}`} aria-hidden="true">
          {t('Нажмите на карту, чтобы свернуть')}
        </p>
        <span role="status" aria-live="polite">
          {wallet.announcement}
        </span>
      </div>
    </div>
  );
}
