# Glass contours and Day layout — 28 October 2026

The shared material now has one native border. Lighting comes from background
gradients rather than sharp inset shadows or concentric decorative outlines.
Navigation owns the indicator material; its pseudo-element uses border-box sizing.
Press feedback affects icon/label contents, leaving the measured hit area stable.
Indicator measurement retains fractional layout sizes and accounts for CSS zoom.

The weekly dashboard tracker uses the same opaque lavender base for the card and
sticky names. Scrolling cells cannot show through the text. The Day page alone
uses the available desktop width; other page containers and global scale are unchanged.

## Local verification

- Node 24: production build, 270 tests, Prettier, and diff whitespace check passed.
- Dependency audit: no vulnerabilities.
- Chromium desktop viewports 1280, 1440, 1920 CSS px: navigation/content gap
  about 24 px, right gap about 28 px, no horizontal page overflow.
- Mobile 320, 360, 375, 390, 430 CSS px: all five active cells checked;
  indicator follows measured cells, 60 px hit height, no horizontal page overflow.
- All six desktop destinations and both light/dark materials inspected.
- Mobile tracker horizontal scrolling: names remain pinned to the scroll viewport;
  computed card/name colors match in both themes.
- Independent review covered CSS cascade, measured geometry, accessibility names,
  reduced motion, scoped layout, and preservation of existing data behavior.

Screenshots are actual browser captures. Local content is the existing isolated
demo fixture; screenshots of the published site use the owner's authenticated view.
No physical iPhone, Safari, or installed iOS PWA was available for this check.
