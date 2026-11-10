import { useEffect, useId, useMemo, useState, type CSSProperties, type FocusEvent } from 'react';
import { CalendarDays, Clock, Globe2 } from 'lucide-react';
import type { Settings } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { ChoiceGroup, type Choice } from './ChoiceGroup';
import {
  ISSUE_MESSAGES,
  TIME_ZONES,
  dayRangeIssue,
  timeZoneName,
  utcOffsetLabel,
  zoneClock,
  type SettingsIssue,
} from './settings-logic';
import { LANGUAGE_LABELS, workDaySummary } from './settings-summaries';
import { ExpandItem, FieldError, Group, type Accordion } from './Rows';
import type { SaveSetting } from './useSettingsSaver';
import { useNow } from './useNow';

interface TimeGroupProps {
  settings: Settings;
  accordion: Accordion;
  save: SaveSetting;
}

const LANGUAGE_CHOICES: readonly Choice<Settings['language']>[] = [
  { value: 'ru', label: LANGUAGE_LABELS.ru },
  { value: 'en', label: LANGUAGE_LABELS.en },
];

export function TimeGroup({ settings, accordion, save }: TimeGroupProps) {
  const { t } = useI18n();
  return (
    <Group title={t('Язык и время')}>
      <ExpandItem
        id="language"
        accordion={accordion}
        icon={Globe2}
        tone={2}
        title={t('Язык интерфейса')}
        value={t(LANGUAGE_LABELS[settings.language])}
      >
        <ChoiceGroup
          label={t('Язык интерфейса')}
          className="st-seg"
          choiceClassName="st-seg-option"
          style={{ '--n': 2, '--i': settings.language === 'en' ? 1 : 0 } as CSSProperties}
          value={settings.language}
          choices={LANGUAGE_CHOICES}
          onChange={(language) => void save({ language })}
        />
      </ExpandItem>
      <TimeZoneItem settings={settings} accordion={accordion} save={save} />
      <WorkDayItem settings={settings} accordion={accordion} save={save} />
    </Group>
  );
}

function TimeZoneItem({ settings, accordion, save }: TimeGroupProps) {
  const { t } = useI18n();
  const now = useNow();
  const choices = useMemo<Choice<string>[]>(() => {
    const known = TIME_ZONES.some((zone) => zone.id === settings.timeZone);
    const zones = known
      ? TIME_ZONES
      : [{ id: settings.timeZone, name: settings.timeZone }, ...TIME_ZONES];
    return zones.map((zone) => ({
      value: zone.id,
      label: zone.name,
      content: (
        <>
          <span className="st-zone-name">{t(zone.name)}</span>
          <span className="st-zone-offset">{utcOffsetLabel(zone.id, now)}</span>
        </>
      ),
    }));
  }, [settings.timeZone, now, t]);
  const name = t(timeZoneName(settings.timeZone)).split(',')[0];
  return (
    <ExpandItem
      id="timeZone"
      accordion={accordion}
      icon={Clock}
      tone={3}
      title={t('Часовой пояс')}
      value={`${name} · ${zoneClock(settings.timeZone, now)}`}
    >
      <ChoiceGroup
        label={t('Часовой пояс')}
        className="st-zones"
        choiceClassName="st-zone"
        value={settings.timeZone}
        choices={choices}
        onChange={(timeZone) => void save({ timeZone })}
      />
    </ExpandItem>
  );
}

function WorkDayItem({ settings, accordion, save }: TimeGroupProps) {
  const { t } = useI18n();
  const startId = useId();
  const endId = useId();
  const [start, setStart] = useState(settings.workDayStart);
  const [end, setEnd] = useState(settings.workDayEnd);
  const [issue, setIssue] = useState<SettingsIssue | null>(null);

  useEffect(() => {
    setStart(settings.workDayStart);
    setEnd(settings.workDayEnd);
    setIssue(null);
  }, [settings.workDayStart, settings.workDayEnd]);

  function change(field: 'workDayStart' | 'workDayEnd', value: string) {
    const next = {
      workDayStart: field === 'workDayStart' ? value : start,
      workDayEnd: field === 'workDayEnd' ? value : end,
    };
    setStart(next.workDayStart);
    setEnd(next.workDayEnd);
    // An empty value is a half-typed time: wait for the rest instead of complaining.
    if (value === '') return setIssue(null);
    const problem = dayRangeIssue(next.workDayStart, next.workDayEnd);
    setIssue(problem);
    if (!problem) void save(next);
  }

  function leave(event: FocusEvent<HTMLDivElement>) {
    if (event.currentTarget.contains(event.relatedTarget)) return;
    if (!issue && start && end) return;
    setStart(settings.workDayStart);
    setEnd(settings.workDayEnd);
    setIssue(null);
  }

  return (
    <ExpandItem
      id="workDay"
      accordion={accordion}
      icon={CalendarDays}
      tone={4}
      title={t('Рабочий день')}
      value={workDaySummary(settings)}
    >
      <div className="st-fields st-fields-time" onBlur={leave}>
        <div className="st-field">
          <label htmlFor={startId}>{t('Начало дня')}</label>
          <input
            id={startId}
            className="st-input st-time"
            type="time"
            required
            value={start}
            aria-invalid={issue ? true : undefined}
            onChange={(event) => change('workDayStart', event.target.value)}
          />
        </div>
        <div className="st-field">
          <label htmlFor={endId}>{t('Конец дня')}</label>
          <input
            id={endId}
            className="st-input st-time"
            type="time"
            required
            value={end}
            aria-invalid={issue ? true : undefined}
            aria-describedby={issue ? `${endId}-error` : undefined}
            onChange={(event) => change('workDayEnd', event.target.value)}
          />
        </div>
      </div>
      {issue ? (
        <FieldError id={`${endId}-error`}>{t(ISSUE_MESSAGES[issue])}</FieldError>
      ) : (
        <small className="st-hint">{t('Помощник учитывает эти часы при планировании.')}</small>
      )}
    </ExpandItem>
  );
}
