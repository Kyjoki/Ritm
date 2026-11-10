import { flushSync } from 'react-dom';

/** Theme switch: the new theme grows as a circle from the toggle button (docs: MOTION.md, section 1). */
export const REVEAL_MS = 520;
export const REVEAL_EASING = 'cubic-bezier(.65, 0, .35, 1)';
export const FADE_MS = 250;
export const REDUCED_FADE_MS = 120;
const SAFETY_MS = REVEAL_MS + 1500;
const TOGGLE_SELECTOR = '[data-theme-toggle]';

export interface Point {
  x: number;
  y: number;
}
export interface Size {
  width: number;
  height: number;
}
export interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** Radius of the circle that, centred on `origin`, reaches the farthest corner of the viewport. */
export function revealRadius(origin: Point, size: Size): number {
  const dx = Math.max(origin.x, size.width - origin.x);
  const dy = Math.max(origin.y, size.height - origin.y);
  return Math.hypot(dx, dy);
}

/** Centre of the toggle button, kept inside the viewport; the viewport centre when there is no button. */
export function revealOrigin(box: Box | null, size: Size): Point {
  if (!box || (box.width <= 0 && box.height <= 0)) {
    return { x: size.width / 2, y: size.height / 2 };
  }
  const clamp = (value: number, max: number) => Math.min(Math.max(value, 0), max);
  return {
    x: clamp(box.left + box.width / 2, size.width),
    y: clamp(box.top + box.height / 2, size.height),
  };
}

/** The desktop shell sets zoom on the root; view-transition layers live in zoomed px, rects in screen px. */
export function unzoomBox(box: Box | null, zoom: number): Box | null {
  if (!box || !(zoom > 0) || zoom === 1) return box;
  return {
    left: box.left / zoom,
    top: box.top / zoom,
    width: box.width / zoom,
    height: box.height / zoom,
  };
}

export function revealClip(origin: Point, radius: number): [string, string] {
  const at = `at ${Math.round(origin.x)}px ${Math.round(origin.y)}px`;
  return [`circle(0px ${at})`, `circle(${Math.ceil(radius)}px ${at})`];
}

type Apply = () => void;
let generation = 0;

function rootZoom(): number {
  const zoom = Number.parseFloat(getComputedStyle(document.documentElement).zoom);
  return zoom > 0 ? zoom : 1;
}

function boxOf(element: Element | null): Box | null {
  return element ? element.getBoundingClientRect() : null;
}

const MODE_CLASSES = ['theme-reveal', 'theme-vt-fade', 'theme-fade'];

/** Marks the root with the mode class of this switch; a newer switch replaces an older one's class. */
function beginMode(className: string): number {
  const root = document.documentElement;
  root.classList.remove(...MODE_CLASSES);
  root.classList.add(className);
  return ++generation;
}

/** Clears the mode class unless a newer switch has taken over. */
function endMode(id: number) {
  if (id === generation) document.documentElement.classList.remove(...MODE_CLASSES);
}

/** Runs `apply` in a view transition and always releases the root class, whatever the outcome. */
function transitionWith(apply: Apply, id: number, safetyMs: number): ViewTransition {
  const release = () => endMode(id);
  const transition = document.startViewTransition(() => {
    flushSync(apply);
  });
  transition.updateCallbackDone.catch(release);
  transition.finished.then(release, release);
  window.setTimeout(release, safetyMs);
  return transition;
}

function circleReveal(apply: Apply, trigger: Element | null) {
  const root = document.documentElement;
  const zoom = rootZoom();
  const size = { width: window.innerWidth / zoom, height: window.innerHeight / zoom };
  const button = boxOf(trigger ?? document.querySelector(TOGGLE_SELECTOR));
  const origin = revealOrigin(unzoomBox(button, zoom), size);
  const id = beginMode('theme-reveal');
  const transition = transitionWith(apply, id, SAFETY_MS);
  transition.ready
    .then(() => {
      root.animate(
        { clipPath: revealClip(origin, revealRadius(origin, size)) },
        {
          duration: REVEAL_MS,
          easing: REVEAL_EASING,
          pseudoElement: '::view-transition-new(root)',
        },
      );
    })
    .catch(() => endMode(id));
}

/** A plain crossfade of the two themes: snapshot fade when possible, colour transitions otherwise. */
function crossfade(apply: Apply, ms: number) {
  document.documentElement.style.setProperty('--theme-fade-ms', `${ms}ms`);
  if (typeof document.startViewTransition === 'function') {
    const id = beginMode('theme-vt-fade');
    transitionWith(apply, id, ms + 1500).ready.catch(() => endMode(id));
    return;
  }
  const id = beginMode('theme-fade');
  apply();
  window.setTimeout(() => endMode(id), ms + 80);
}

/**
 * Applies a theme change through `apply` (state update plus the data-theme attribute) with the reveal.
 * `trigger` is the clicked button; without it the header toggle, then the viewport centre, is the origin.
 * Never blocks: without the View Transitions API or with Reduce Motion it falls back to a short fade.
 */
export function revealTheme(apply: Apply, trigger?: Element | null) {
  try {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) return crossfade(apply, REDUCED_FADE_MS);
    if (typeof document.startViewTransition !== 'function') return crossfade(apply, FADE_MS);
    circleReveal(apply, trigger ?? null);
  } catch {
    apply();
  }
}
