export interface SwipePoint {
  x: number;
  y: number;
  time: number;
}

/** A deliberate horizontal gesture; taps, scrolling, and long presses stay unchanged. */
export function calendarWeekSwipe(start: SwipePoint, end: SwipePoint, width: number): -1 | 0 | 1 {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const elapsed = end.time - start.time;
  if (
    elapsed < 0 ||
    elapsed > 1_200 ||
    (Math.abs(dx) < Math.max(56, width * 0.16) &&
      !(Math.abs(dx) >= 32 && Math.abs(dx / Math.max(elapsed, 1)) >= 0.55)) ||
    Math.abs(dx) < Math.abs(dy) * 1.8
  )
    return 0;
  return dx < 0 ? 1 : -1;
}
