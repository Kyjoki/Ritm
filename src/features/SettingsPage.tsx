import { useState } from 'react';
import type {
  AiStatus,
  GoogleCalendarStatus,
  GoogleOAuthSetup,
  Settings,
} from '../../shared/types';
import { GoogleSetupDialog } from '../components/GoogleSetupDialog';
import { useI18n } from '../lib/i18n';
import { AccountGroup, SecurityDialog } from './settings/AccountGroup';
import { AppearanceGroup } from './settings/AppearanceGroup';
import { ConnectionsGroup, type ConnectionDialog } from './settings/ConnectionsGroup';
import { GoogleDialog, GoogleDisconnectDialog } from './settings/GoogleDialog';
import { NotificationsGroup } from './settings/NotificationsGroup';
import { OpenAiDialog } from './settings/OpenAiDialog';
import { ProfileGroup } from './settings/ProfileGroup';
import { useAccordion } from './settings/Rows';
import { SaveToast } from './settings/SaveToast';
import { TelegramDialog } from './settings/TelegramDialog';
import { TimeGroup } from './settings/TimeGroup';
import { useGoogleConnection } from './settings/useGoogleConnection';
import { useNotificationPermission } from './settings/useNotificationPermission';
import { useSaveFeedback } from './settings/useSaveFeedback';
import { useSettingsSaver, type SaveSettingsPatch } from './settings/useSettingsSaver';
import { useTelegramConnection } from './settings/useTelegramConnection';
import '../styles/settings-choices.css';
import '../styles/settings.css';

interface SettingsPageProps {
  active?: boolean;
  settings: Settings;
  aiStatus: AiStatus;
  googleStatus: GoogleCalendarStatus;
  onConnectGoogle: (extendedColors?: boolean) => Promise<void>;
  onConnectGoogleTasks?: () => Promise<void>;
  googleTasksMessage?: string;
  onDisconnectGoogle: () => Promise<void>;
  onGoogleConfigured?: () => Promise<void>;
  /** Applies a settings patch right away and rejects if the server refuses it. */
  onSave: SaveSettingsPatch;
  onConfigureAI: (apiKey: string, model: string) => Promise<void>;
  onDisconnectAI: () => Promise<void>;
  onLogout?: () => Promise<void>;
}

type OpenDialog = ConnectionDialog | 'google-disconnect' | 'security' | null;

export function SettingsPage({
  active = true,
  settings,
  aiStatus,
  googleStatus,
  onConnectGoogle,
  onConnectGoogleTasks,
  googleTasksMessage,
  onDisconnectGoogle,
  onGoogleConfigured,
  onSave,
  onConfigureAI,
  onDisconnectAI,
  onLogout,
}: SettingsPageProps) {
  const { t } = useI18n();
  const feedback = useSaveFeedback();
  const save = useSettingsSaver(settings, onSave, feedback);
  const accordion = useAccordion();
  const permission = useNotificationPermission();
  const telegram = useTelegramConnection(feedback);
  const google = useGoogleConnection(
    googleStatus,
    {
      onConnect: onConnectGoogle,
      onConnectTasks: onConnectGoogleTasks,
      onDisconnect: onDisconnectGoogle,
      onConfigured: onGoogleConfigured,
    },
    feedback,
  );
  const [dialog, setDialog] = useState<OpenDialog>(null);
  const [loggingOut, setLoggingOut] = useState(false);
  const closeDialog = () => setDialog(null);

  function open(next: OpenDialog) {
    google.clearMessages();
    setDialog(next);
  }

  async function connectGoogleFromRow() {
    const failure = await google.connect();
    if (failure) feedback.showError(t(failure));
  }

  async function logout() {
    if (!onLogout || loggingOut) return;
    setLoggingOut(true);
    try {
      await onLogout();
    } catch (failure) {
      feedback.showError(failure instanceof Error ? t(failure.message) : t('Не удалось выйти.'));
    } finally {
      setLoggingOut(false);
    }
  }

  return (
    <div className="settings-page st-page" data-motion-active={active}>
      <header className="page-heading">
        <div>
          <p className="page-eyebrow">{t('Ritm под твой образ жизни')}</p>
          <h1>{t('Настройки')}</h1>
          <p className="page-description">{t('Твоё пространство. Твои правила.')}</p>
        </div>
      </header>
      <div className="st-column">
        <ProfileGroup settings={settings} accordion={accordion} save={save} />
        <TimeGroup settings={settings} accordion={accordion} save={save} />
        <AppearanceGroup settings={settings} accordion={accordion} save={save} />
        <NotificationsGroup
          settings={settings}
          save={save}
          permission={permission}
          telegram={telegram}
          feedback={feedback}
          onOpenTelegram={() => open('telegram')}
        />
        <ConnectionsGroup
          aiStatus={aiStatus}
          googleStatus={googleStatus}
          google={google}
          telegram={telegram}
          onOpen={open}
          onConnectGoogle={() => void connectGoogleFromRow()}
        />
        {onLogout ? (
          <AccountGroup
            loggingOut={loggingOut}
            onOpenSecurity={() => open('security')}
            onLogout={() => void logout()}
          />
        ) : null}
      </div>
      <SaveToast feedback={feedback} />
      {dialog === 'openai' ? (
        <OpenAiDialog
          status={aiStatus}
          onConfigure={onConfigureAI}
          onDisconnect={onDisconnectAI}
          onClose={closeDialog}
          feedback={feedback}
        />
      ) : null}
      {dialog === 'google' ? (
        <GoogleDialog
          status={googleStatus}
          google={google}
          tasksMessage={googleTasksMessage}
          canConnectTasks={Boolean(onConnectGoogleTasks)}
          onSetup={() => open('google-setup')}
          onAskDisconnect={() => open('google-disconnect')}
          onClose={closeDialog}
        />
      ) : null}
      {dialog === 'google-setup' ? (
        <GoogleSetupDialog
          onClose={closeDialog}
          onChanged={(configuration: GoogleOAuthSetup, message: string) =>
            google.handleConfigured(configuration, message)
          }
        />
      ) : null}
      {dialog === 'google-disconnect' ? (
        <GoogleDisconnectDialog google={google} onBack={() => open('google')} />
      ) : null}
      {dialog === 'telegram' ? <TelegramDialog telegram={telegram} onClose={closeDialog} /> : null}
      {dialog === 'security' ? <SecurityDialog onClose={closeDialog} /> : null}
    </div>
  );
}
