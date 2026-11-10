import { type CSSProperties } from 'react';
import { Check, ChartNoAxesCombined, Landmark, Wallet } from 'lucide-react';
import type { FinanceCurrency } from '../../../shared/types';
import { MotionNumber } from '../../components/Motion';
import { useI18n } from '../../lib/i18n';
import { useMoney } from './finance-format';
import { cardTones, stackSlot, type CardTone } from './finance-stack';
import type { FinanceCard } from './finance-wallet';

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

export function FinanceTotals({
  totals,
}: {
  totals: { currency: FinanceCurrency; amountMinor: number }[];
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  return (
    <div className="fin-totals">
      <span className="fin-totals-label">{t('Всего средств')}</span>
      <div className="fin-totals-values">
        {totals.length ? (
          totals.map((total, index) => (
            <span key={total.currency} className="fin-totals-item">
              {index > 0 && (
                <span className="fin-totals-sep" aria-hidden="true">
                  ·
                </span>
              )}
              <span className={index ? 'fin-total-sub' : 'fin-total-main'}>
                <MotionNumber
                  value={total.amountMinor}
                  format={(value) => money(value, total.currency)}
                  step={100}
                />
              </span>
            </span>
          ))
        ) : (
          <span className="fin-total-main">—</span>
        )}
      </div>
      {totals.length > 1 && (
        <p className="fin-totals-note">{t('Суммы в разных валютах не складываются.')}</p>
      )}
    </div>
  );
}

function StackCard({
  card,
  index,
  front,
  count,
  tone,
  selected,
  label,
  name,
  onSelect,
}: {
  card: FinanceCard;
  index: number;
  front: number;
  count: number;
  tone: CardTone | undefined;
  selected: boolean;
  label: string;
  name: string;
  onSelect: () => void;
}) {
  const { t } = useI18n();
  const { money } = useMoney();
  const slot = stackSlot(index, front, count);
  const wave = WAVES[index % 2];
  const balance = card.balanceMinor;
  const balanceText = balance === null ? '—' : money(balance, card.currency);
  const hint = selected ? 'Нажмите, чтобы показать все счета' : 'Нажмите, чтобы открыть счёт';
  const sub =
    card.kind === 'deposit'
      ? 'Депозит'
      : card.kind === 'stocks'
        ? 'Брокерский счёт'
        : 'Расчётный счёт';
  const style = {
    '--ty': `${slot.offset}px`,
    '--s': slot.scale,
    '--br': slot.dim,
    zIndex: slot.layer,
  } as CSSProperties;
  return (
    <button
      type="button"
      className={`fin-card is-${tone}${selected ? ' is-sel' : ''}${index === front ? ' is-front' : ''}`}
      style={style}
      aria-pressed={selected}
      aria-label={`${label}, ${balanceText}. ${t(hint)}`}
      onClick={onSelect}
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
  if (!cards.length) return null;
  const tones = cardTones(cards);
  const selectedIndex = cards.findIndex((card) => card.id === selectedId);
  const manyCurrencies = new Set(cards.map((card) => card.currency)).size > 1;
  const nameOf = (card: FinanceCard) =>
    card.kind === 'account'
      ? t('Основной счёт')
      : card.kind === 'stocks'
        ? t('Акции')
        : (card.name ?? t('Депозит'));
  return (
    <div
      className="fin-stack"
      role="group"
      aria-label={t('Счета и карты')}
      style={{ '--n': cards.length } as CSSProperties}
    >
      {cards.map((card, index) => (
        <StackCard
          key={card.id}
          card={card}
          index={index}
          front={Math.max(selectedIndex, 0)}
          count={cards.length}
          tone={tones.get(card.id)}
          selected={card.id === selectedId}
          name={nameOf(card)}
          label={nameOf(card) + (manyCurrencies ? ` · ${card.currency}` : '')}
          onSelect={() => onSelect(card.id === selectedId ? null : card.id)}
        />
      ))}
    </div>
  );
}
