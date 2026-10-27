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

  const update = () => {
    const viewport = window.visualViewport;
    const top = Math.max(0, viewport?.offsetTop ?? 0);
    const left = Math.max(0, viewport?.offsetLeft ?? 0);
    const width = viewport?.width ?? window.innerWidth;
    const height = viewport?.height ?? window.innerHeight;
    // The desktop app uses CSS zoom; top-layer dialog coordinates inherit that zoom.
    const zoom = Number.parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
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
  update();
  window.visualViewport?.addEventListener('resize', update);
  window.visualViewport?.addEventListener('scroll', update);
  window.addEventListener('resize', update);

  let released = false;
  return () => {
    if (released) return;
    released = true;
    window.visualViewport?.removeEventListener('resize', update);
    window.visualViewport?.removeEventListener('scroll', update);
    window.removeEventListener('resize', update);
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
