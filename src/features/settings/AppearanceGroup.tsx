import type { CSSProperties } from 'react';
import { Contrast, PanelLeft } from 'lucide-react';
import type { Settings } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { ChoiceGroup, type Choice } from './ChoiceGroup';
import { SIDEBAR_LABELS, THEME_LABELS } from './settings-summaries';
import { ExpandItem, Group, type Accordion } from './Rows';
import type { SaveSetting } from './useSettingsSaver';

interface AppearanceGroupProps {
  settings: Settings;
  accordion: Accordion;
  save: SaveSetting;
}

/** Miniature app screens. `half` draws the dark one cut diagonally for the system theme. */
function Preview({ variants }: { variants: readonly string[] }) {
  return (
    <span className="st-sw-ui" aria-hidden="true">
      {variants.map((variant) => (
        <span
          key={variant}
          className={`st-sw-page ${variant
            .split(' ')
            .map((part) => `st-sw-${part}`)
            .join(' ')}`}
        >
          <i />
          <u />
        </span>
      ))}
    </span>
  );
}

function swatch<V extends string>(value: V, label: string, variants: readonly string[]): Choice<V> {
  return {
    value,
    label,
    content: (
      <>
        <Preview variants={variants} />
        <span>{label}</span>
      </>
    ),
  };
}

export function AppearanceGroup({ settings, accordion, save }: AppearanceGroupProps) {
  const { t } = useI18n();
  const themes: Choice<Settings['theme']>[] = [
    swatch('light', t(THEME_LABELS.light), ['light']),
    swatch('dark', t(THEME_LABELS.dark), ['dark']),
    swatch('system', t(THEME_LABELS.system), ['light', 'dark half']),
  ];
  const sidebars: Choice<Settings['sidebar']>[] = [
    swatch('dark', t(SIDEBAR_LABELS.dark), ['graphite']),
    swatch('light', t(SIDEBAR_LABELS.light), ['pale']),
  ];
  return (
    <Group title={t('Оформление')}>
      <ExpandItem
        id="theme"
        accordion={accordion}
        icon={Contrast}
        tone={0}
        title={t('Тема')}
        value={t(THEME_LABELS[settings.theme])}
      >
        <ChoiceGroup
          label={t('Тема приложения')}
          className="st-swatches"
          choiceClassName="st-swatch"
          style={{ '--cols': 3 } as CSSProperties}
          value={settings.theme}
          choices={themes}
          onChange={(theme, trigger) => void save({ theme }, trigger)}
        />
      </ExpandItem>
      <ExpandItem
        id="sidebar"
        accordion={accordion}
        icon={PanelLeft}
        tone={5}
        title={t('Боковая панель')}
        value={t(SIDEBAR_LABELS[settings.sidebar])}
      >
        <ChoiceGroup
          label={t('Боковая панель')}
          className="st-swatches"
          choiceClassName="st-swatch"
          style={{ '--cols': 2 } as CSSProperties}
          value={settings.sidebar}
          choices={sidebars}
          onChange={(sidebar) => void save({ sidebar })}
        />
      </ExpandItem>
    </Group>
  );
}
