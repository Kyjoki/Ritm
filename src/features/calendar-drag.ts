export interface DragGrid {
  left: number;
  top: number;
  width: number;
  timeColumn: number;
  days: number;
  hourHeight: number;
}

/** Keep the original grab point under the pointer and snap starts to 15 minutes. */
export function calendarDragTarget(
  x: number,
  y: number,
  grid: DragGrid,
  grabOffsetY: number,
  duration: number,
): { dayIndex: number; minutes: number } {
  const dayWidth = (grid.width - grid.timeColumn) / grid.days;
  const dayIndex = Math.max(
    0,
    Math.min(grid.days - 1, Math.floor((x - grid.left - grid.timeColumn) / dayWidth)),
  );
  const rawMinutes = ((y - grid.top - grabOffsetY) / grid.hourHeight) * 60;
  const latestStart = Math.max(0, Math.floor((1440 - duration) / 15) * 15);
  const minutes = Math.max(0, Math.min(latestStart, Math.round(rawMinutes / 15) * 15));
  return { dayIndex, minutes };
}

export function calendarDragWeekEdge(x: number, left: number, right: number): -1 | 0 | 1 {
  if (x < left + 24) return -1;
  if (x > right - 24) return 1;
  return 0;
}
