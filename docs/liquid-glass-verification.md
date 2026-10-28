# Liquid Glass integration verification — 2026-10-28

Integrated against `origin/main` at `5b4c6a3`. That revision reverts the two preceding
interaction commits and has the same source tree as `a15c74b`; the existing habits,
finance, calendar and mobile-behaviour implementations are retained.

## Scope

- Shared lavender glass materials for Day, Calendar, Habits, Assistant, Finance,
  Settings, login and portalled dialogs; dense surfaces for text, inputs and tables.
- A 72 px desktop navigation capsule with six sections, keyboard tooltips and profile.
- Five mobile cells: Day, Calendar, Habits, Assistant, More. More opens Finance and
  Settings through the shared dialog. The active indicator uses measured geometry.
- Short desktop windows scroll the section list while retaining the logo and profile.
- Mobile cards avoid nested backdrop blurs; reduced motion/transparency and unsupported
  backdrop-filter receive fallbacks. No changes to stored data or business calculations.
- Live Mobile Preview is a Vite development-only route. The isolated preview uses a
  temporary demo database and does not load project environment files.

## Local verification

- Node 24: 270 tests passed; production build/typecheck and Prettier passed.
- Dependency audit: no vulnerabilities. Existing build warning: main JS chunk exceeds
  500 kB; this verification does not establish performance on physical devices.
- Browser: all six sections, light/dark materials, desktop capsule, mobile labels and
  equal tap areas across 320, 360, 375, 390 and 430 px frames. No document horizontal
  overflow; Windows scrollbars reduce available content width by 17 px.
- Habits: completing IELTS changed progress from 1/3 (33%) to 2/3 (67%); undo restored
  1/3. Creation/edit forms opened; Escape/cancel closed them without changing data.
- More: after closing a form at scrollY ~1037, navigation to Finance opened it at
  scrollY 0 with the body unlocked. Ordinary dialog close retained the previous scroll.
- Short desktop viewports (900 and 1200 px wide, 360 px high): active Settings and profile
  stayed inside the viewport; tap targets remained approximately 48 px.

Browser checks use an embedded Chromium browser and real iframe layout dimensions.
They are not Safari, installed iOS PWA, touch hardware, keyboard or physical iPhone
performance tests. Live provider/OAuth/notification integrations were not exercised
against the isolated demo server.
