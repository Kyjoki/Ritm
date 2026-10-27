let openDialogs = 0;
let bodyState: {
  position: string;
  top: string;
  width: string;
  overflow: string;
  rootOverflow: string;
  scrollY: number;
} | null = null;

/** Keep a native top-layer dialog inside the visible viewport, including when a keyboard opens. */
export function activateDialogViewport(dialog: HTMLDialogElement): () => void {
  if (openDialogs++ === 0) {
    const body = document.body;
    bodyState = {
      position: body.style.position,
      top: body.style.top,
      width: body.style.width,
      overflow: body.style.overflow,
      rootOverflow: document.documentElement.style.overflow,
      scrollY: window.scrollY,
    };
    body.style.position = 'fixed';
    body.style.top = `-${bodyState.scrollY}px`;
    body.style.width = '100%';
    body.style.overflow = 'hidden';
    document.documentElement.style.overflow = 'hidden';
  }

  let frame = 0;
  let previous = '';
  const update = () => {
    frame = 0;
    const viewport = window.visualViewport;
    const top = Math.max(0, viewport?.offsetTop ?? 0);
    const left = Math.max(0, viewport?.offsetLeft ?? 0);
    const width = viewport?.width ?? window.innerWidth;
    const height = viewport?.height ?? window.innerHeight;
    // The desktop app uses CSS zoom; top-layer dialog coordinates inherit that zoom.
    const zoom = Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    const signature = [top, left, width, height, window.innerWidth, window.innerHeight, zoom].join(
      ',',
    );
    if (signature === previous) return;
    previous = signature;
    dialog.style.setProperty('--dialog-vv-top', `${top / zoom}px`);
    dialog.style.setProperty('--dialog-vv-left', `${left / zoom}px`);
    dialog.style.setProperty(
      '--dialog-vv-right',
      `${Math.max(0, window.innerWidth - left - width) / zoom}px`,
    );
    dialog.style.setProperty(
      '--dialog-vv-bottom',
      `${Math.max(0, window.innerHeight - top - height) / zoom}px`,
    );
    dialog.style.setProperty('--dialog-vv-width', `${width / zoom}px`);
    dialog.style.setProperty('--dialog-vv-height', `${height / zoom}px`);
  };
  const schedule = () => {
    if (!frame) frame = window.requestAnimationFrame(update);
  };
  // Initial top-layer geometry is synchronous; keyboard/scroll event bursts share one frame.
  update();
  window.visualViewport?.addEventListener('resize', schedule);
  window.visualViewport?.addEventListener('scroll', schedule);
  window.addEventListener('resize', schedule);

  let released = false;
  return () => {
    if (released) return;
    released = true;
    window.cancelAnimationFrame(frame);
    window.visualViewport?.removeEventListener('resize', schedule);
    window.visualViewport?.removeEventListener('scroll', schedule);
    window.removeEventListener('resize', schedule);
    if (--openDialogs === 0 && bodyState) {
      const state = bodyState;
      bodyState = null;
      document.body.style.position = state.position;
      document.body.style.top = state.top;
      document.body.style.width = state.width;
      document.body.style.overflow = state.overflow;
      document.documentElement.style.overflow = state.rootOverflow;
      window.scrollTo(0, state.scrollY);
    }
  };
}
