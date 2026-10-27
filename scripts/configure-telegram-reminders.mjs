/** Create/update the free-tier two-minute QStash schedule without printing credentials. */
const origin = process.env.APP_ORIGIN;
const qstashUrl = process.env.QSTASH_URL;
const token = process.env.QSTASH_TOKEN;
const secret = process.env.REMINDER_SCHEDULER_SECRET;
if (
  !origin?.startsWith('https://') ||
  !qstashUrl?.startsWith('https://') ||
  !token ||
  !secret ||
  secret.length < 32
) {
  console.error(
    'Set APP_ORIGIN, QSTASH_URL, QSTASH_TOKEN and REMINDER_SCHEDULER_SECRET in your private environment.',
  );
  process.exitCode = 1;
} else {
  const destination = `${origin.replace(/\/$/, '')}/api/integrations/telegram/reminders/run`;
  const endpoint = `${qstashUrl.replace(/\/$/, '')}/v2/schedules/${encodeURIComponent(destination)}`;
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Upstash-Cron': '*/2 * * * *',
        'Upstash-Schedule-Id': 'ritm-telegram-reminders',
        'Upstash-Method': 'POST',
        'Upstash-Retries': '0',
        'Upstash-Forward-X-Ritm-Reminder-Secret': secret,
        'Content-Type': 'application/json',
      },
      body: '{}',
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`QStash returned ${response.status}`);
    const result = await response.json();
    console.log(`QStash schedule configured: ${result.scheduleId || 'ritm-telegram-reminders'}`);
  } catch (error) {
    console.error(
      `Schedule setup failed: ${error instanceof Error ? error.message : 'unknown error'}`,
    );
    process.exitCode = 1;
  }
}
