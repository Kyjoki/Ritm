import { createHmac, randomBytes } from 'node:crypto';
import { AppError } from './errors.ts';
import type { RuntimeState } from './runtime-state.ts';
import type { SecretStore } from './secrets.ts';
import { generateTotpSecret, otpauthUrl, verifyTotp } from './totp.ts';

const ACTIVE = 'totp:active';
const PENDING = 'totp:pending';
export const RECOVERY_CODE_COUNT = 10;
const STEP_CLAIM_MS = 3 * 30_000;
const RECOVERY_CLAIM_MS = 10 * 365 * 24 * 3_600_000;
const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

interface ActiveRecord {
  secret: string;
  recovery: string[];
  enabledAt: number;
}

export type TwoFactorInput = { code?: string; recoveryCode?: string };

const invalid = () => new AppError(401, 'TOTP_INVALID', 'Неверный код. Проверьте код и повторите.');
const required = () =>
  new AppError(401, 'TOTP_REQUIRED', 'Введите код из приложения для двухфакторной защиты.');

/** Opt-in TOTP second factor; secret and recovery hashes live in the encrypted secret store. */
export class TwoFactor {
  constructor(
    private secrets: SecretStore,
    private state: RuntimeState,
    private key: Buffer,
    private now: () => number = Date.now,
  ) {}
  private async active(): Promise<ActiveRecord | null> {
    const text = await this.secrets.getSecret(ACTIVE);
    return text ? (JSON.parse(text) as ActiveRecord) : null;
  }
  private hashRecovery(code: string) {
    const normalized = code.toUpperCase().replace(/[^A-Z0-9]/g, '');
    return createHmac('sha256', this.key)
      .update('ritm:recovery:' + normalized)
      .digest('hex');
  }
  private newRecoveryCodes() {
    return Array.from({ length: RECOVERY_CODE_COUNT }, () => {
      const bytes = randomBytes(10);
      const raw = Array.from(bytes, (byte) => codeAlphabet[byte % codeAlphabet.length]).join('');
      return raw.slice(0, 5) + '-' + raw.slice(5);
    });
  }
  private async saveRecovery(record: ActiveRecord, codes: string[]) {
    await this.secrets.saveSecret(
      ACTIVE,
      JSON.stringify({ ...record, recovery: codes.map((code) => this.hashRecovery(code)) }),
    );
  }
  async status() {
    const record = await this.active();
    return { totpEnabled: Boolean(record), recoveryCodesLeft: record?.recovery.length ?? 0 };
  }
  async enabled() {
    return Boolean(await this.active());
  }
  async setup(account: string) {
    if (await this.active())
      throw new AppError(409, 'TOTP_ALREADY_ENABLED', 'Двухфакторная защита уже включена.');
    const secret = generateTotpSecret();
    await this.secrets.saveSecret(PENDING, JSON.stringify({ secret }));
    return { secret, otpauthUrl: otpauthUrl(secret, account) };
  }
  /** Accepts each time step once; a replayed code is refused. */
  private async acceptTotp(secret: string, code: string) {
    const step = verifyTotp(secret, code, this.now());
    if (step === null) return false;
    return (await this.state.consumeRateLimit(`totp-step:${step}`, 1, STEP_CLAIM_MS)).allowed;
  }
  async confirm(code: string) {
    const pendingText = await this.secrets.getSecret(PENDING);
    if (!pendingText)
      throw new AppError(
        409,
        'TOTP_NOT_STARTED',
        'Сначала начните настройку двухфакторной защиты.',
      );
    const { secret } = JSON.parse(pendingText) as { secret: string };
    if (!(await this.acceptTotp(secret, code))) throw invalid();
    const codes = this.newRecoveryCodes();
    await this.saveRecovery({ secret, recovery: [], enabledAt: this.now() }, codes);
    await this.secrets.removeSecret(PENDING);
    return codes;
  }
  /** True when the second factor is satisfied. Missing input while enabled is TOTP_REQUIRED. */
  async verify(input: TwoFactorInput): Promise<void> {
    const record = await this.active();
    if (!record) return;
    if (input.recoveryCode) return this.useRecovery(record, input.recoveryCode);
    if (!input.code) throw required();
    if (!(await this.acceptTotp(record.secret, input.code))) throw invalid();
  }
  private async useRecovery(record: ActiveRecord, recoveryCode: string) {
    const hash = this.hashRecovery(recoveryCode);
    if (!record.recovery.includes(hash)) throw invalid();
    // The claim makes a code single-use even if two requests race.
    if (!(await this.state.consumeRateLimit(`recovery:${hash}`, 1, RECOVERY_CLAIM_MS)).allowed)
      throw invalid();
    await this.secrets.saveSecret(
      ACTIVE,
      JSON.stringify({ ...record, recovery: record.recovery.filter((item) => item !== hash) }),
    );
  }
  async regenerate(code: string) {
    const record = await this.active();
    if (!record) throw new AppError(409, 'TOTP_NOT_ENABLED', 'Двухфакторная защита не включена.');
    if (!(await this.acceptTotp(record.secret, code))) throw invalid();
    const codes = this.newRecoveryCodes();
    await this.saveRecovery(record, codes);
    return codes;
  }
  async disable() {
    await this.secrets.removeSecret(ACTIVE);
    await this.secrets.removeSecret(PENDING);
  }
}
