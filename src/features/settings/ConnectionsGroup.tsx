import { CalendarDays, KeyRound, Send } from 'lucide-react';
import type { AiStatus, GoogleCalendarStatus } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { googleSummary, openAiSummary, telegramSummary } from './settings-summaries';
import { Group, OpenRow, StatusText } from './Rows';
import type { GoogleConnection } from './useGoogleConnection';
import type { TelegramConnection } from './useTelegramConnection';

export type ConnectionDialog = 'openai' | 'google' | 'google-setup' | 'telegram';

interface ConnectionsGroupProps {
  aiStatus: AiStatus;
  googleStatus: GoogleCalendarStatus;
  google: GoogleConnection;
  telegram: TelegramConnection;
  onOpen: (dialog: ConnectionDialog) => void;
  /** Starts the Google sign-in straight from the row, reporting failures itself. */
  onConnectGoogle: () => void;
}

export function ConnectionsGroup({
  aiStatus,
  googleStatus,
  google,
  telegram,
  onOpen,
  onConnectGoogle,
}: ConnectionsGroupProps) {
  const { t } = useI18n();
  const ai = openAiSummary(aiStatus);
  const calendar = googleSummary(googleStatus, google.configured, google.statusUnknown);
  const chat = telegramSummary(telegram.status, telegram.loadFailed);
  return (
    <Group title={t('Подключения')}>
      <OpenRow
        icon={KeyRound}
        tone={0}
        title="OpenAI"
        ariaLabel={`OpenAI: ${t(ai.label)}`}
        status={<StatusText tone={ai.tone}>{t(ai.label)}</StatusText>}
        quickLabel={ai.cta ? t(ai.cta) : null}
        quickTone={ai.tone}
        onOpen={() => onOpen('openai')}
        onQuick={() => onOpen('openai')}
      />
      <OpenRow
        icon={CalendarDays}
        tone={2}
        title={t('Google Календарь')}
        ariaLabel={`${t('Google Календарь')}: ${t(calendar.label)}`}
        attention={calendar.tone === 'warn'}
        status={<StatusText tone={calendar.tone}>{t(calendar.label)}</StatusText>}
        quickLabel={calendar.cta ? t(calendar.cta) : null}
        quickTone={calendar.tone}
        quickBusy={google.busy}
        onOpen={() => onOpen('google')}
        onQuick={() => (calendar.action === 'setup' ? onOpen('google-setup') : onConnectGoogle())}
      />
      <OpenRow
        icon={Send}
        tone={3}
        title="Telegram"
        ariaLabel={`Telegram: ${t(chat.label)}`}
        attention={chat.tone === 'warn'}
        status={<StatusText tone={chat.tone}>{t(chat.label)}</StatusText>}
        quickLabel={chat.cta ? t(chat.cta) : null}
        quickTone={chat.tone}
        onOpen={() => onOpen('telegram')}
        onQuick={() => onOpen('telegram')}
      />
    </Group>
  );
}
