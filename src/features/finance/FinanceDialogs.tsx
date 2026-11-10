import type { FinanceEntry } from '../../../shared/types';
import { EntryDialog } from './FinanceEntryForm';
import { PriceDialog } from './FinancePriceDialog';
import { localDate } from './finance-form';
import type { useFinanceDialogs } from './useFinanceDialogs';

type Dialogs = ReturnType<typeof useFinanceDialogs>;

/** Renders whichever dialog is open; all state lives in useFinanceDialogs. */
export function FinanceDialogs({
  dialogs,
  entries,
  saving,
  today,
  accountName,
}: {
  dialogs: Dialogs;
  entries: FinanceEntry[];
  saving: boolean;
  today: string;
  accountName: (id: string) => string;
}) {
  const { dialog, price, formError } = dialogs;
  return (
    <>
      {dialog && (
        <EntryDialog
          {...dialog}
          entries={entries}
          transferAccounts={dialogs.transferAccounts}
          accountName={accountName}
          today={today}
          saving={saving}
          error={formError}
          onChange={(form) => dialogs.setDialog({ ...dialog, form })}
          onSubmit={(event) => void dialogs.submit(event)}
          onClose={() => dialogs.setDialog(null)}
        />
      )}
      {price && (
        <PriceDialog
          stock={price.stock}
          price={price.price}
          date={price.date}
          today={localDate()}
          saving={saving}
          error={formError}
          onPrice={(value) => dialogs.setPrice({ ...price, price: value })}
          onDate={(value) => dialogs.setPrice({ ...price, date: value })}
          onSubmit={(event) => void dialogs.submitPrice(event)}
          onClose={() => dialogs.setPrice(null)}
        />
      )}
    </>
  );
}
