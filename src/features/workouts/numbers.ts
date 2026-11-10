/** Weight and reps as typed (WorkoutNumber / WorkoutFormat / WorkoutStepper of RitmCore). */
export const MAX_WEIGHT = 9999;
export const WEIGHT_STEP = 2.5;

/** «22,» becomes «22», «.5» becomes «0.5», «2,50» stays. Null for anything that is not a weight. */
export function normalizedWeight(raw: string): string | null {
  const text = raw.trim();
  let integer = '';
  let separator = '';
  let fraction = '';
  for (const character of text) {
    if (character >= '0' && character <= '9') {
      if (separator) fraction += character;
      else integer += character;
    } else if ((character === '.' || character === ',') && !separator) separator = character;
    else return null;
  }
  if (integer.length > 4 || fraction.length > 2) return null;
  if (!integer) {
    if (!separator || !fraction) return null;
    integer = '0';
  }
  return separator && fraction ? `${integer}${separator}${fraction}` : integer;
}
export function parseWeight(raw: string): number | null {
  const normalized = normalizedWeight(raw);
  return normalized === null ? null : Number(normalized.replace(',', '.'));
}
export function parseReps(raw: string): number | null {
  const text = raw.trim();
  return /^\d{1,3}$/.test(text) && Number(text) > 0 ? Number(text) : null;
}
export const isBlank = (raw: string) => raw.trim() === '';

/** «62,5» or «62.5»: whole numbers without a fraction, two decimals at most. */
export function formatWeight(value: number, comma = true): string {
  const text = String(Math.round(value * 100) / 100);
  return comma ? text.replace('.', ',') : text;
}
export const stepWeight = (text: string, delta: number, comma = true): string =>
  formatWeight(
    Math.min(MAX_WEIGHT, Math.max(0, Math.round(((parseWeight(text) ?? 0) + delta) * 100) / 100)),
    comma,
  );
export const stepReps = (text: string, delta: number): string =>
  String(Math.min(999, Math.max(1, (parseReps(text) ?? 0) + delta)));
