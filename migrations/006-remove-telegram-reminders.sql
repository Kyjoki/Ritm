-- Telegram reminders were removed; drop their leftover settings, heartbeat and lease rows.
DELETE FROM ritm_server_secrets
WHERE name IN (
    'telegram-reminder-settings',
    'telegram-reminder-cursor',
    'telegram-reminder-heartbeat',
    'telegram-reminder-failure'
  )
  OR name LIKE 'telegram-reminder:%';
DELETE FROM ritm_leases
WHERE name = 'telegram-reminder-run'
  OR name LIKE 'telegram-reminder:%';
