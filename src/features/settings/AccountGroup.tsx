import { LogOut, ShieldCheck } from 'lucide-react';
import { Dialog } from '../../components/Dialog';
import { SecurityCard } from '../../components/SecurityCard';
import { useI18n } from '../../lib/i18n';
import { Group, OpenRow } from './Rows';

interface AccountGroupProps {
  loggingOut: boolean;
  onOpenSecurity: () => void;
  onLogout: () => void;
}

/** Shown only when the server requires a sign-in. */
export function AccountGroup({ loggingOut, onOpenSecurity, onLogout }: AccountGroupProps) {
  const { t } = useI18n();
  return (
    <Group title={t('Безопасность')}>
      <OpenRow
        icon={ShieldCheck}
        tone={3}
        title={t('Двухфакторная защита')}
        status={t('Вход и устройства')}
        onOpen={onOpenSecurity}
      />
      <OpenRow
        icon={LogOut}
        tone={1}
        title={loggingOut ? t('Выходим…') : t('Выйти из аккаунта')}
        danger
        onOpen={() => !loggingOut && onLogout()}
      />
    </Group>
  );
}

export function SecurityDialog({ onClose }: { onClose: () => void }) {
  const { t } = useI18n();
  return (
    <Dialog title={t('Безопасность')} onClose={onClose} className="st-dialog st-dialog-wide">
      <SecurityCard />
    </Dialog>
  );
}
