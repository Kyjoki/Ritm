import { useId } from 'react';
import type { Settings } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import {
  EMAIL_MAX_LENGTH,
  ISSUE_MESSAGES,
  NAME_MAX_LENGTH,
  isValidEmail,
  profileInitials,
} from './settings-logic';
import { ExpandItem, FieldError, Group, type Accordion } from './Rows';
import type { SaveSetting } from './useSettingsSaver';
import { useAutosaveText } from './useAutosaveText';

interface ProfileGroupProps {
  settings: Settings;
  accordion: Accordion;
  save: SaveSetting;
}

export function ProfileGroup({ settings, accordion, save }: ProfileGroupProps) {
  const { t } = useI18n();
  const nameId = useId();
  const emailId = useId();
  const name = useAutosaveText({
    value: settings.displayName,
    validate: (text) => (text.trim() ? null : t(ISSUE_MESSAGES['name-required'])),
    commit: (text) => save({ displayName: text }),
  });
  const email = useAutosaveText({
    value: settings.email,
    validate: (text) => (isValidEmail(text.trim()) ? null : t(ISSUE_MESSAGES['email-invalid'])),
    commit: (text) => save({ email: text }),
  });
  const shownName = name.text.trim() || settings.displayName;
  return (
    <Group label={t('Аккаунт')}>
      <ExpandItem
        id="profile"
        accordion={accordion}
        title={t('Аккаунт')}
        className="st-profile"
        lead={
          <>
            <span className="st-avatar" aria-hidden="true">
              {profileInitials(shownName, t('Р'))}
            </span>
            <span className="st-profile-text">
              <strong>{shownName || t('Твоё имя')}</strong>
              <span>{email.text.trim() || t('Почта не указана')}</span>
            </span>
          </>
        }
      >
        <div className="st-fields">
          <div className="st-field">
            <label htmlFor={nameId}>{t('Имя')}</label>
            <input
              id={nameId}
              className="st-input"
              name="displayName"
              autoComplete="name"
              maxLength={NAME_MAX_LENGTH}
              required
              value={name.text}
              aria-invalid={name.error ? true : undefined}
              aria-describedby={name.error ? `${nameId}-error` : undefined}
              onChange={(event) => name.onChange(event.target.value)}
              onBlur={name.onBlur}
            />
            {name.error ? <FieldError id={`${nameId}-error`}>{name.error}</FieldError> : null}
          </div>
          <div className="st-field">
            <label htmlFor={emailId}>{t('Электронная почта')}</label>
            <input
              id={emailId}
              className="st-input"
              name="email"
              type="email"
              autoComplete="email"
              maxLength={EMAIL_MAX_LENGTH}
              placeholder={t('Твоя почта')}
              value={email.text}
              aria-invalid={email.error ? true : undefined}
              aria-describedby={email.error ? `${emailId}-error` : `${emailId}-hint`}
              onChange={(event) => email.onChange(event.target.value)}
              onBlur={email.onBlur}
            />
            {email.error ? (
              <FieldError id={`${emailId}-error`}>{email.error}</FieldError>
            ) : (
              <small id={`${emailId}-hint`}>
                {t('Для профиля. Почтовые уведомления пока не подключены.')}
              </small>
            )}
          </div>
        </div>
      </ExpandItem>
    </Group>
  );
}
