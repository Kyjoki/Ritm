import type { GoogleCalendarStatus } from '../../../shared/types';
import { Dialog } from '../../components/Dialog';
import { useI18n } from '../../lib/i18n';
import { googleSummary } from './settings-summaries';
import { DialogError, InfoRow } from './DialogParts';
import { StatusText } from './Rows';
import type { GoogleConnection } from './useGoogleConnection';

interface GoogleDialogProps {
  status: GoogleCalendarStatus;
  google: GoogleConnection;
  tasksMessage?: string;
  canConnectTasks: boolean;
  onSetup: () => void;
  onAskDisconnect: () => void;
  onClose: () => void;
}

export function GoogleDialog({
  status,
  google,
  tasksMessage,
  canConnectTasks,
  onSetup,
  onAskDisconnect,
  onClose,
}: GoogleDialogProps) {
  const { t } = useI18n();
  const summary = googleSummary(status, google.configured, google.statusUnknown);
  const connected = google.configured && status.status === 'connected';
  const signedIn = google.configured && ['connected', 'reauth_required'].includes(status.status);
  return (
    <Dialog
      title={t('Google Календарь')}
      onClose={onClose}
      busy={google.busy}
      className="st-dialog"
    >
      <InfoRow label={t('Состояние')}>
        <StatusText tone={summary.tone}>{t(summary.label)}</StatusText>
      </InfoRow>
      <p className="st-note">
        {google.configured
          ? t('Основной календарь · просмотр, создание и редактирование событий')
          : t('Добавьте Client ID и Client Secret из Google Cloud')}
      </p>
      {connected ? (
        <>
          <InfoRow label={t('Google Задачи')}>
            {status.tasksEnabled ? (
              t('Подключены')
            ) : canConnectTasks ? (
              <button
                type="button"
                className="button button-secondary"
                disabled={google.busy}
                onClick={() => void google.connectTasks()}
              >
                {t('Подключить Google Tasks')}
              </button>
            ) : (
              t('Не подключены')
            )}
          </InfoRow>
          <InfoRow label={t('Вся палитра цветов')}>
            {status.extendedColors ? (
              t('Включена')
            ) : (
              <button
                type="button"
                className="button button-secondary"
                disabled={google.busy}
                onClick={() => void google.connect(true)}
              >
                {t('Разрешить новые цвета')}
              </button>
            )}
          </InfoRow>
          {!status.extendedColors ? (
            <p className="st-note">
              {t('Для новых оттенков Google попросит разрешение на управление календарями.')}
            </p>
          ) : null}
        </>
      ) : null}
      {tasksMessage ? <p className="st-note">{t(tasksMessage)}</p> : null}
      {google.error ? <DialogError>{google.error}</DialogError> : null}
      <div className="dialog-actions st-actions">
        {signedIn ? (
          <button
            type="button"
            className="button button-danger"
            disabled={google.busy}
            onClick={onAskDisconnect}
          >
            {t('Отключить')}
          </button>
        ) : null}
        <button
          type="button"
          className="button button-secondary"
          disabled={google.busy}
          onClick={onSetup}
        >
          {google.configured ? t('Сменить клиент') : t('Указать клиент')}
        </button>
        {google.configured ? (
          <button
            type="button"
            className="button button-primary"
            disabled={google.busy}
            onClick={() => void google.connect()}
          >
            {google.busy ? t('Подождите…') : signedIn ? t('Переподключить') : t('Подключить')}
          </button>
        ) : null}
      </div>
    </Dialog>
  );
}

export function GoogleDisconnectDialog({
  google,
  onBack,
}: {
  google: GoogleConnection;
  onBack: () => void;
}) {
  const { t } = useI18n();
  async function confirm() {
    if (await google.disconnect()) onBack();
  }
  return (
    <Dialog
      title={t('Отключить Google Calendar?')}
      onClose={onBack}
      busy={google.busy}
      className="st-dialog"
    >
      <p className="dialog-copy">
        {t(
          'Ritm перестанет получать и изменять события. События в Google и подключение другого приложения сохранятся.',
        )}
      </p>
      {google.error ? <DialogError>{google.error}</DialogError> : null}
      <div className="dialog-actions">
        <button
          type="button"
          className="button button-secondary"
          disabled={google.busy}
          data-dialog-dismiss
        >
          {t('Отмена')}
        </button>
        <button
          type="button"
          className="button button-primary"
          disabled={google.busy}
          onClick={() => void confirm()}
        >
          {google.busy ? t('Отключаем…') : t('Отключить')}
        </button>
      </div>
    </Dialog>
  );
}
