import { useCallback, useRef } from 'react';
import type { Settings } from '../../../shared/types';
import { useI18n } from '../../lib/i18n';
import { ISSUE_MESSAGES, prepareSettingsPatch, type SettingsPatch } from './settings-logic';
import type { SaveFeedback } from './useSaveFeedback';

/** Applies the patch optimistically and sends it; rejects when the server refuses it. */
export type SaveSettingsPatch = (patch: SettingsPatch, trigger?: Element | null) => Promise<void>;

export type SaveSetting = (changes: SettingsPatch, trigger?: Element | null) => Promise<boolean>;

/**
 * Autosave entry point for every settings control. Only the changed fields are sent,
 * values that fail validation are never sent, and the outcome is reported through the toast.
 */
export function useSettingsSaver(
  settings: Settings,
  onSave: SaveSettingsPatch,
  feedback: SaveFeedback,
): SaveSetting {
  const { t } = useI18n();
  const latest = useRef(settings);
  latest.current = settings;
  const { showSaved, showError } = feedback;
  return useCallback(
    async (changes, trigger) => {
      const { patch, issue } = prepareSettingsPatch(latest.current, changes);
      if (issue) {
        showError(t(ISSUE_MESSAGES[issue]));
        return false;
      }
      if (Object.keys(patch).length === 0) return true;
      try {
        await onSave(patch, trigger);
        showSaved();
        return true;
      } catch (failure) {
        showError(
          failure instanceof Error
            ? t(failure.message)
            : t('Не удалось сохранить изменения. Попробуй ещё раз.'),
        );
        return false;
      }
    },
    [onSave, showSaved, showError, t],
  );
}
