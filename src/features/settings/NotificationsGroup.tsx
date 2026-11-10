import { Bell, Clock, Monitor, Send } from 'lucide-react';
import type { Settings } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { DEFAULT_TELEGRAM_LEAD } from './settings-logic';
import { leadLabel } from './settings-summaries';
import { FlatRow, Group, StatusText, Switch } from './Rows';
import type { NotificationPermission } from './useNotificationPermission';
import type { SaveFeedback } from './useSaveFeedback';
import type { SaveSetting } from './useSettingsSaver';
import type { TelegramConnection } from './useTelegramConnection';

interface NotificationsGroupProps {
  settings: Settings;
  save: SaveSetting;
  permission: NotificationPermission;
  telegram: TelegramConnection;
  feedback: SaveFeedback;
  onOpenTelegram: () => void;
}

export function NotificationsGroup({
  settings,
  save,
  permission,
  telegram,
  feedback,
  onOpenTelegram,
}: NotificationsGroupProps) {
  const { t } = useI18n();

  async function toggleReminders(enabled: boolean) {
    if (!enabled) {
      await save({ notifications: false });
      return;
    }
    try {
      const result = await permission.ensure();
      if (result === 'granted') await save({ notifications: true });
      else
        feedback.showError(
          result === 'unsupported'
            ? t('Этот браузер не поддерживает уведомления.')
            : t('Разреши уведомления для Ritm в настройках браузера.'),
        );
    } catch {
      feedback.showError(t('Не удалось запросить разрешение. Проверь настройки браузера.'));
    }
  }

  async function allowBrowser() {
    try {
      const result = await permission.ensure();
      if (result === 'granted') feedback.showSaved(t('Уведомления в браузере включены'));
      else feedback.showError(t('Разреши уведомления для Ritm в настройках браузера.'));
    } catch {
      feedback.showError(t('Не удалось запросить разрешение. Проверь настройки браузера.'));
    }
  }

  return (
    <Group title={t('Уведомления')}>
      <FlatRow icon={Bell} tone={1} title={t('Напоминать о задачах')}>
        <span className="st-value st-value-aux">{t('за 15 мин')}</span>
        <Switch
          checked={settings.notifications}
          label={t('Напоминания о задачах')}
          disabled={permission.busy}
          onChange={(enabled) => void toggleReminders(enabled)}
        />
      </FlatRow>
      <FlatRow icon={Clock} tone={4} title={t('Утренний план')}>
        <span className="st-value st-value-aux">{settings.workDayStart}</span>
        <Switch
          checked={settings.dailyBriefing}
          label={t('Утренний план')}
          disabled={!settings.notifications}
          onChange={(dailyBriefing) => void save({ dailyBriefing })}
        />
      </FlatRow>
      <FlatRow icon={Monitor} tone={2} title={t('В браузере')}>
        <BrowserStatus permission={permission} onAllow={() => void allowBrowser()} />
      </FlatRow>
      <FlatRow icon={Send} tone={3} title={t('В Telegram')}>
        <TelegramControl telegram={telegram} onOpen={onOpenTelegram} />
      </FlatRow>
    </Group>
  );
}

function BrowserStatus({
  permission,
  onAllow,
}: {
  permission: NotificationPermission;
  onAllow: () => void;
}) {
  const { t } = useI18n();
  if (permission.permission === 'granted')
    return <StatusText tone="ok">{t('Разрешены')}</StatusText>;
  if (permission.permission === 'denied')
    return <StatusText tone="warn">{t('Запрещены в браузере')}</StatusText>;
  if (permission.permission === 'unsupported')
    return <StatusText tone="idle">{t('Не поддерживаются')}</StatusText>;
  return (
    <button type="button" className="st-pill-button" disabled={permission.busy} onClick={onAllow}>
      {t('Разрешить')}
    </button>
  );
}

function TelegramControl({
  telegram,
  onOpen,
}: {
  telegram: TelegramConnection;
  onOpen: () => void;
}) {
  const { t } = useI18n();
  const reminders = telegram.status?.reminders;
  if (!telegram.status?.linked)
    return (
      <button type="button" className="st-pill-button" onClick={onOpen}>
        {t('Настроить')}
      </button>
    );
  const lead = leadLabel(reminders?.leadMinutes ?? DEFAULT_TELEGRAM_LEAD);
  return (
    <>
      <span className="st-value st-value-aux">{t(lead.source, lead.values)}</span>
      <Switch
        checked={reminders?.enabled ?? false}
        label={t('Напоминания в Telegram')}
        disabled={telegram.busy}
        onChange={(enabled) =>
          void telegram.setReminders(enabled, reminders?.leadMinutes ?? DEFAULT_TELEGRAM_LEAD)
        }
      />
    </>
  );
}
