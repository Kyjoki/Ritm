const sizes = {
  narrow: { width: 320, height: 640 },
  small: { width: 360, height: 740 },
  compact: { width: 375, height: 667 },
  wideCompact: { width: 390, height: 844 },
  standard: { width: 393, height: 852 },
  large: { width: 430, height: 932 },
} as const;

type Device = keyof typeof sizes;
type Orientation = 'portrait' | 'landscape';
type PreviewState = { device: Device; orientation: Orientation };

const storageKey = 'ritm-live-mobile-preview';
const deviceSelect = document.querySelector<HTMLSelectElement>('#device')!;
const phoneShell = document.querySelector<HTMLElement>('#phone-shell')!;
const viewportLabel = document.querySelector<HTMLElement>('#viewport-label')!;
const orientationButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-orientation]'),
);

function readState(): PreviewState {
  try {
    const value = JSON.parse(localStorage.getItem(storageKey) ?? '{}') as Partial<PreviewState>;
    return {
      device: value.device && value.device in sizes ? value.device : 'standard',
      orientation: value.orientation === 'landscape' ? 'landscape' : 'portrait',
    };
  } catch {
    return { device: 'standard', orientation: 'portrait' };
  }
}

let state = readState();

function applyState() {
  const { width, height } = sizes[state.device];
  const screenWidth = state.orientation === 'portrait' ? width : height;
  const screenHeight = state.orientation === 'portrait' ? height : width;

  phoneShell.style.setProperty('--screen-width', `${screenWidth}px`);
  phoneShell.style.setProperty('--screen-height', `${screenHeight}px`);
  phoneShell.dataset.orientation = state.orientation;
  deviceSelect.value = state.device;
  viewportLabel.textContent = `${screenWidth} × ${screenHeight - 53} CSS px · ${state.orientation === 'portrait' ? 'вертикально' : 'горизонтально'}`;

  for (const button of orientationButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.orientation === state.orientation));
  }

  try {
    localStorage.setItem(storageKey, JSON.stringify(state));
  } catch {
    // Resizing still works if this browser does not allow persistent storage.
  }
}

deviceSelect.addEventListener('change', () => {
  if (deviceSelect.value in sizes) {
    state = { ...state, device: deviceSelect.value as Device };
    applyState();
  }
});

for (const button of orientationButtons) {
  button.addEventListener('click', () => {
    const orientation = button.dataset.orientation;
    if (orientation === 'portrait' || orientation === 'landscape') {
      state = { ...state, orientation };
      applyState();
    }
  });
}

applyState();
