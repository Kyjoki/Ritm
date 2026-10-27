// Pure interpolation shared by charts and counters. Endpoints stay exact.
export const easeOut = (t: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3);
export function sampleValues(values: readonly number[], length: number): number[] {
  if (!length) return [];
  if (!values.length) return Array(length).fill(0);
  if (values.length === length) return [...values];
  return Array.from({ length }, (_, index) => {
    const at = length === 1 ? 0 : (index / (length - 1)) * (values.length - 1);
    const left = Math.floor(at),
      right = Math.min(values.length - 1, left + 1);
    return values[left] + (values[right] - values[left]) * (at - left);
  });
}
export function interpolateValues(
  from: readonly number[],
  to: readonly number[],
  progress: number,
) {
  if (progress >= 1) return [...to];
  const start = sampleValues(from, to.length);
  const amount = easeOut(progress);
  return to.map((value, index) => start[index] + (value - start[index]) * amount);
}
