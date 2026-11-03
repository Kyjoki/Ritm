// Generated from the prototype's icon dictionaries (shell.html sprite and the section files).
// Do not edit by hand. Geometry is SVG data on a 24 × 24 grid; stroke widths are in grid units.

/// Every glyph of the prototype icon set. `source` says where it was defined.
enum RitmIconName: String, CaseIterable, Sendable {
  case wallet
  case bell
  case sun
  case moon
  case back
  case chev
  case cart
  case cup
  case bus
  case home
  case pulse
  case bag
  case ticket
  case briefcase
  case laptop
  case gift
  case percent
  case swap
  case plus
  case check
  case check2
  case circle
  case half
  case close
  case sliders
  case coins
  case shield
  case chart
  case dollar
  case cal
  case habit
  case ai
  case down
  case up
  case info
  case dots
  case star
  case dumbbell
  case lock
  case heart
  case bolt
  case camera
  case music
  case grid
  case mark
  case sparkles
  case book
  case activity
  case droplet
  case moonHabits
  case target
  case dumbbellHabits
  case footprints
  case plusCircle
  case minus
  case checkHabits
  case chevL
  case arrowUR
  case pencil
  case archive
  case undo
  case trash
  case flame
  case clock
  case checklist
  case calendar
  case hist
  case chevAssistant
  case bubble
  case trashAssistant
  case sparklesAssistant
  case shieldAssistant
  case upAssistant
  case copy
  case checkAssistant
  case x
  case undoAssistant
  case bulb
  case calendarAssistant
  case checklistAssistant
  case arrow
  case refresh
  case square
  case checksq
  case alert
  case globe
  case user
  case palette
  case bellSettings
  case plane
  case network
  case logout
  case walletSettings
  case sunSettings
  case moonSettings
  case folder
  case ok
  case chevSettings
  case grip
  case swapWorkouts
  case play
  case pause
  case leftIcon
  case rightIcon
  case refreshCalendar
  case stack
  case calCalendar
  case lockCalendar
  case catHealth
  case catShopping
  case catGifts
  case catSport
  case catTravel
  case catEdu
  case catTelecom
  case catClothes
  case catBeauty
  case catKids
  case catPets
  case catBills
  case catSalary
  case catRefund
  case catSale
  case catOther
}

struct RitmIconSource: Sendable {
  /// Stroke width on the 24-unit grid; 0 for a glyph that is only filled.
  let stroke: Double
  /// SVG elements: path, circle, rect, line, polyline.
  let body: String
}

enum RitmIconData {
  static func source(_ name: RitmIconName) -> RitmIconSource {
    switch name {
    case .wallet: RitmIconSource(stroke: 1.8, body: #"<rect x="3.5" y="6.5" width="17" height="13" rx="3"/><path d="M3.5 9.5V8A2.5 2.5 0 0 1 6 5.5h9.5"/><path d="M20.5 12.5h-4a1.8 1.8 0 0 0 0 3.6h4z"/>"#)  // sprite
    case .bell: RitmIconSource(stroke: 1.8, body: #"<path d="M6 16.5V11a6 6 0 1 1 12 0v5.5l1.5 1.5h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>"#)  // sprite
    case .sun: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M18.7 5.3l-1.6 1.6M6.9 17.1l-1.6 1.6"/>"#)  // sprite
    case .moon: RitmIconSource(stroke: 1.8, body: #"<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>"#)  // sprite
    case .back: RitmIconSource(stroke: 1.8, body: #"<path d="M19 12H5M11 6l-6 6 6 6"/>"#)  // sprite
    case .chev: RitmIconSource(stroke: 1.8, body: #"<path d="M9 6l6 6-6 6"/>"#)  // sprite
    case .cart: RitmIconSource(stroke: 1.8, body: #"<path d="M3 4h2.4l2.2 10.2a1.5 1.5 0 0 0 1.5 1.2h7.6a1.5 1.5 0 0 0 1.5-1.1L20 8H6.2"/><circle cx="9.5" cy="19" r="1.2"/><circle cx="16.5" cy="19" r="1.2"/>"#)  // sprite
    case .cup: RitmIconSource(stroke: 1.8, body: #"<path d="M5 8h11v5a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5z"/><path d="M16 9.5h1.5a2.5 2.5 0 0 1 0 5h-2"/><path d="M8 3.5V5M12 3.5V5"/>"#)  // sprite
    case .bus: RitmIconSource(stroke: 1.8, body: #"<rect x="5" y="3.5" width="14" height="14" rx="3"/><path d="M5 11h14M8.5 17.5V20M15.5 17.5V20"/><path d="M8.8 14.2h.01M15.2 14.2h.01"/>"#)  // sprite
    case .home: RitmIconSource(stroke: 1.8, body: #"<path d="M4 11l8-6.5 8 6.5"/><path d="M6 9.8V19h12V9.8"/><path d="M10 19v-5h4v5"/>"#)  // sprite
    case .pulse: RitmIconSource(stroke: 1.8, body: #"<path d="M3 12h4l2-5 4 10 2-5h6"/>"#)  // sprite
    case .bag: RitmIconSource(stroke: 1.8, body: #"<path d="M5.5 8h13l-1 11.5h-11z"/><path d="M9 10V7a3 3 0 0 1 6 0v3"/>"#)  // sprite
    case .ticket: RitmIconSource(stroke: 1.8, body: #"<path d="M4 7h16v3a2 2 0 0 0 0 4v3H4v-3a2 2 0 0 0 0-4z"/><path d="M14 8v8" stroke-dasharray="1.5 2.4"/>"#)  // sprite
    case .briefcase: RitmIconSource(stroke: 1.8, body: #"<rect x="3.5" y="7.5" width="17" height="12" rx="2.5"/><path d="M9 7.5V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v1.5M3.5 13h17"/>"#)  // sprite
    case .laptop: RitmIconSource(stroke: 1.8, body: #"<rect x="5" y="5.5" width="14" height="9.5" rx="1.8"/><path d="M3 19h18"/>"#)  // sprite
    case .gift: RitmIconSource(stroke: 1.8, body: #"<rect x="4" y="9" width="16" height="10.5" rx="2"/><path d="M12 9v10.5M3.5 9h17"/><path d="M12 9c-1.500-3.500-5-3.500-5-1.500S10 9 12 9zM12 9c1.500-3.500 5-3.500 5-1.500S14 9 12 9z"/>"#)  // sprite
    case .percent: RitmIconSource(stroke: 1.8, body: #"<path d="M18 6L6 18"/><circle cx="7.5" cy="7.5" r="2"/><circle cx="16.5" cy="16.5" r="2"/>"#)  // sprite
    case .swap: RitmIconSource(stroke: 1.8, body: #"<path d="M5 8h13l-3.500-3.500M19 16H6l3.500 3.500"/>"#)  // sprite
    case .plus: RitmIconSource(stroke: 1.8, body: #"<path d="M12 5v14M5 12h14"/>"#)  // sprite
    case .check: RitmIconSource(stroke: 1.8, body: #"<path d="M5 12.500l4.500 4.500L19 7.500"/>"#)  // sprite
    case .check2: RitmIconSource(stroke: 1.8, body: #"<path d="M2.500 12.500l4 4L14 8M10 15.500l1.500 1.500L21 7.500"/>"#)  // sprite
    case .circle: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="7.500"/>"#)  // sprite
    case .half: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="7.500"/><path d="M12 4.500a7.500 7.500 0 0 1 0 15z" fill="currentColor"/>"#)  // sprite
    case .close: RitmIconSource(stroke: 1.8, body: #"<path d="M6 6l12 12M18 6L6 18"/>"#)  // sprite
    case .sliders: RitmIconSource(stroke: 1.8, body: #"<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>"#)  // sprite
    case .coins: RitmIconSource(stroke: 1.8, body: #"<ellipse cx="12" cy="7" rx="7" ry="3"/><path d="M5 7v5c0 1.700 3.100 3 7 3s7-1.300 7-3V7M5 12v5c0 1.700 3.100 3 7 3s7-1.300 7-3v-5"/>"#)  // sprite
    case .shield: RitmIconSource(stroke: 1.8, body: #"<path d="M12 3.500l7 2.500v5.500c0 4.200-2.900 7.300-7 9-4.100-1.700-7-4.800-7-9V6z"/><path d="M9 12l2.200 2.200L15.500 10"/>"#)  // sprite
    case .chart: RitmIconSource(stroke: 1.8, body: #"<path d="M4 19V5M4 19h16"/><path d="M7.500 15l3.500-4.500 3 2.500 4.500-6"/>"#)  // sprite
    case .dollar: RitmIconSource(stroke: 1.8, body: #"<path d="M12 4v16M16 8.200c-.6-1.200-2-2-4-2-2.400 0-4 1.100-4 2.800 0 4.400 8.500 2 8.500 6.300 0 1.700-1.800 2.900-4.500 2.900-2.200 0-3.800-.9-4.500-2.300"/>"#)  // sprite
    case .cal: RitmIconSource(stroke: 1.8, body: #"<rect x="4" y="5.500" width="16" height="14.500" rx="3"/><path d="M4 10h16M8.500 3.500V7M15.500 3.500V7"/>"#)  // sprite
    case .habit: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="8"/><path d="M8.500 12.200l2.500 2.500 4.500-5"/>"#)  // sprite
    case .ai: RitmIconSource(stroke: 1.8, body: #"<path d="M11 3.500l1.800 5.200 5.200 1.800-5.200 1.800L11 17.500l-1.800-5.200L4 10.500l5.200-1.800z"/><path d="M18.500 16v3.500M16.750 17.750h3.500"/>"#)  // sprite
    case .down: RitmIconSource(stroke: 1.8, body: #"<path d="M12 5v14M6 13l6 6 6-6"/>"#)  // sprite
    case .up: RitmIconSource(stroke: 1.8, body: #"<path d="M12 19V5M6 11l6-6 6 6"/>"#)  // sprite
    case .info: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="8.500"/><path d="M12 11v5M12 8h.01"/>"#)  // sprite
    case .dots: RitmIconSource(stroke: 0, body: #"<circle fill="currentColor" cx="6" cy="12" r="1.500"/><circle fill="currentColor" cx="12" cy="12" r="1.500"/><circle fill="currentColor" cx="18" cy="12" r="1.500"/>"#)  // sprite
    case .star: RitmIconSource(stroke: 0, body: #"<path fill="currentColor" d="M12 2.600l2.200 6.400 6.400 2.200-6.400 2.200L12 19.800l-2.200-6.400-6.400-2.200 6.400-2.200z"/>"#)  // sprite
    case .dumbbell: RitmIconSource(stroke: 1.8, body: #"<path d="M6.5 6.5v11M17.5 6.5v11M3 9.5v5M21 9.5v5M6.5 12h11"/>"#)  // sprite
    case .lock: RitmIconSource(stroke: 1.8, body: #"<rect x="5" y="10.5" width="14" height="9.5" rx="2.5"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>"#)  // sprite
    case .heart: RitmIconSource(stroke: 1.8, body: #"<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/>"#)  // sprite
    case .bolt: RitmIconSource(stroke: 1.8, body: #"<path d="M13 3L6 13.5h5L10 21l7-10.5h-5z"/>"#)  // sprite
    case .camera: RitmIconSource(stroke: 1.8, body: #"<path d="M4 8.5h3l1.5-2h7l1.5 2h3V19H4z"/><circle cx="12" cy="13.5" r="3.2"/>"#)  // sprite
    case .music: RitmIconSource(stroke: 1.8, body: #"<path d="M9 18V6l10-2v12"/><circle cx="7" cy="18" r="2.2"/><circle cx="17" cy="16" r="2.2"/>"#)  // sprite
    case .grid: RitmIconSource(stroke: 1.8, body: #"<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>"#)  // sprite
    case .mark: RitmIconSource(stroke: 2.4, body: #"<path d="M3.500 13c2.300-6.500 4.500-6.500 6.500 0s4.200 6.500 6.500 0c.8-2.200 1.800-3.200 3.500-3.200"/>"#)  // sprite
    case .sparkles: RitmIconSource(stroke: 1.8, body: #"<path d="M11 3.5l1.9 5.1 5.1 1.9-5.1 1.9L11 17.5l-1.9-5.1L4 10.5l5.1-1.9z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>"#)  // habits
    case .book: RitmIconSource(stroke: 1.8, body: #"<path d="M4 19.5V5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H19"/>"#)  // habits
    case .activity: RitmIconSource(stroke: 1.8, body: #"<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>"#)  // habits
    case .droplet: RitmIconSource(stroke: 1.8, body: #"<path d="M12 2.7s6 6.3 6 10.8a6 6 0 0 1-12 0c0-4.5 6-10.8 6-10.8z"/>"#)  // habits
    case .moonHabits: RitmIconSource(stroke: 1.8, body: #"<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>"#)  // habits
    case .target: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2"/>"#)  // habits
    case .dumbbellHabits: RitmIconSource(stroke: 1.8, body: #"<path d="M6.5 6.5v11M17.5 6.5v11M3 9v6M21 9v6M6.5 12h11"/>"#)  // habits
    case .footprints: RitmIconSource(stroke: 1.8, body: #"<path d="M4 16v-2.4C4 11.5 3 10.5 3 8c0-2.7 1.5-6 4.5-6C9.4 2 10 3.8 10 5.5c0 3.1-2 5.7-2 8.7V16a2 2 0 1 1-4 0z"/><path d="M20 20v-2.4c0-2.1 1-3.1 1-5.6 0-2.7-1.5-6-4.5-6C14.6 6 14 7.8 14 9.5c0 3.1 2 5.7 2 8.7V20a2 2 0 1 0 4 0z"/>"#)  // habits
    case .plusCircle: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>"#)  // habits
    case .minus: RitmIconSource(stroke: 1.8, body: #"<path d="M5 12h14"/>"#)  // habits
    case .checkHabits: RitmIconSource(stroke: 1.8, body: #"<path d="M5 12.5l4.5 4.5L19 7.5"/>"#)  // habits
    case .chevL: RitmIconSource(stroke: 1.8, body: #"<path d="M15 6l-6 6 6 6"/>"#)  // habits
    case .arrowUR: RitmIconSource(stroke: 1.8, body: #"<path d="M7 17L17 7M8 7h9v9"/>"#)  // habits
    case .pencil: RitmIconSource(stroke: 1.8, body: #"<path d="M4 20l1-4L16.5 4.5a2.1 2.1 0 0 1 3 3L8 19z"/><path d="M14.5 6.5l3 3"/>"#)  // habits
    case .archive: RitmIconSource(stroke: 1.8, body: #"<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8M10 12h4"/>"#)  // habits
    case .undo: RitmIconSource(stroke: 1.8, body: #"<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/>"#)  // habits
    case .trash: RitmIconSource(stroke: 1.8, body: #"<path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/>"#)  // habits
    case .flame: RitmIconSource(stroke: 1.8, body: #"<path d="M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 .3 1.2 1 2 2 2 0-3-1-5 1-8z"/>"#)  // habits
    case .clock: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>"#)  // habits
    case .checklist: RitmIconSource(stroke: 1.8, body: #"<path d="M4 6l1.5 1.5L8 5M4 12l1.5 1.5L8 11M4 18l1.5 1.5L8 17M11 6.5h9M11 12.5h9M11 18.5h9"/>"#)  // habits
    case .calendar: RitmIconSource(stroke: 1.8, body: #"<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>"#)  // habits
    case .hist: RitmIconSource(stroke: 1.8, body: #"<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l3 2"/>"#)  // assistant
    case .chevAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="m6 9 6 6 6-6"/>"#)  // assistant
    case .bubble: RitmIconSource(stroke: 1.8, body: #"<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.4A8 8 0 1 1 21 12z"/>"#)  // assistant
    case .trashAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>"#)  // assistant
    case .sparklesAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 3v4M17 5h4M5 17v4M3 19h4"/>"#)  // assistant
    case .shieldAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="m9 12 2 2 4-4"/>"#)  // assistant
    case .upAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="M12 19V5M5 12l7-7 7 7"/>"#)  // assistant
    case .copy: RitmIconSource(stroke: 1.8, body: #"<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>"#)  // assistant
    case .checkAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="m5 12 5 5 9-10"/>"#)  // assistant
    case .x: RitmIconSource(stroke: 1.8, body: #"<path d="M6 6l12 12M18 6 6 18"/>"#)  // assistant
    case .undoAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>"#)  // assistant
    case .bulb: RitmIconSource(stroke: 1.8, body: #"<path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0 0 12 3z"/>"#)  // assistant
    case .calendarAssistant: RitmIconSource(stroke: 1.8, body: #"<rect x="4" y="5" width="16" height="16" rx="2"/><path d="M4 10h16M8 3v4M16 3v4"/>"#)  // assistant
    case .checklistAssistant: RitmIconSource(stroke: 1.8, body: #"<path d="m4 6 1.5 1.5L8 5M4 12l1.5 1.5L8 11M4 18l1.5 1.5L8 17M11 6h9M11 12h9M11 18h9"/>"#)  // assistant
    case .arrow: RitmIconSource(stroke: 1.8, body: #"<path d="M5 12h14M13 6l6 6-6 6"/>"#)  // assistant
    case .refresh: RitmIconSource(stroke: 1.8, body: #"<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>"#)  // assistant
    case .square: RitmIconSource(stroke: 1.8, body: #"<rect x="4" y="4" width="16" height="16" rx="4"/>"#)  // assistant
    case .checksq: RitmIconSource(stroke: 1.8, body: #"<rect x="4" y="4" width="16" height="16" rx="4" fill="currentColor"/><path d="m8 12.4 2.8 2.8 5.2-6" stroke="var(--accent-ink)"/>"#)  // assistant
    case .alert: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16.5v.5"/>"#)  // assistant
    case .globe: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>"#)  // settings
    case .user: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/>"#)  // settings
    case .palette: RitmIconSource(stroke: 1.8, body: #"<path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-1 1.5-2-.5-1 0-2 1.3-2H17a4 4 0 0 0 4-4c0-5-4-10-9-10z"/><circle cx="8" cy="11" r="1"/><circle cx="12" cy="7.5" r="1"/><circle cx="16" cy="11" r="1"/>"#)  // settings
    case .bellSettings: RitmIconSource(stroke: 1.8, body: #"<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>"#)  // settings
    case .plane: RitmIconSource(stroke: 1.8, body: #"<path d="M21 3 10 14M21 3l-7 18-4-7-7-4z"/>"#)  // settings
    case .network: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><path d="M12 7v5M12 12l-6 5M12 12l6 5"/>"#)  // settings
    case .logout: RitmIconSource(stroke: 1.8, body: #"<path d="M10 4H5v16h5M15 8l4 4-4 4M19 12H9"/>"#)  // settings
    case .walletSettings: RitmIconSource(stroke: 1.8, body: #"<rect x="3" y="6" width="18" height="13" rx="3"/><path d="M3 10h18M16 14.5h2"/>"#)  // settings
    case .sunSettings: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M5 19l1.5-1.5M17.5 6.5 19 5"/>"#)  // settings
    case .moonSettings: RitmIconSource(stroke: 1.8, body: #"<path d="M20 14A8 8 0 0 1 10 4a8 8 0 1 0 10 10z"/>"#)  // settings
    case .folder: RitmIconSource(stroke: 1.8, body: #"<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>"#)  // settings
    case .ok: RitmIconSource(stroke: 1.8, body: #"<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>"#)  // settings
    case .chevSettings: RitmIconSource(stroke: 1.8, body: #"<path d="m7 9 5-4 5 4M7 15l5 4 5-4"/>"#)  // settings
    case .grip: RitmIconSource(stroke: 1.9, body: #"<circle cx="9" cy="6" r="1.4" fill="currentColor"/><circle cx="15" cy="6" r="1.4" fill="currentColor"/><circle cx="9" cy="12" r="1.4" fill="currentColor"/><circle cx="15" cy="12" r="1.4" fill="currentColor"/><circle cx="9" cy="18" r="1.4" fill="currentColor"/><circle cx="15" cy="18" r="1.4" fill="currentColor"/>"#)  // workouts
    case .swapWorkouts: RitmIconSource(stroke: 1.9, body: #"<path d="M5 8h13l-3.5-3.5M19 16H6l3.5 3.5"/>"#)  // workouts
    case .play: RitmIconSource(stroke: 1.9, body: #"<path d="M8 5.5v13l10-6.5z" fill="currentColor"/>"#)  // workouts
    case .pause: RitmIconSource(stroke: 1.9, body: #"<path d="M8 5.5v13M16 5.5v13"/>"#)  // workouts
    case .leftIcon: RitmIconSource(stroke: 2, body: #"<path d="m15 18-6-6 6-6"/>"#)  // calendar
    case .rightIcon: RitmIconSource(stroke: 2, body: #"<path d="m9 18 6-6-6-6"/>"#)  // calendar
    case .refreshCalendar: RitmIconSource(stroke: 2, body: #"<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>"#)  // calendar
    case .stack: RitmIconSource(stroke: 2, body: #"<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M4 16V6a2 2 0 0 1 2-2h10"/>"#)  // calendar
    case .calCalendar: RitmIconSource(stroke: 2, body: #"<rect x="3" y="4" width="18" height="17" rx="3"/><path d="M8 2v4M16 2v4M3 10h18"/>"#)  // calendar
    case .lockCalendar: RitmIconSource(stroke: 2, body: #"<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>"#)  // calendar
    case .catHealth: RitmIconSource(stroke: 1.6, body: #"<path d="M9.500 4h5v5.500H20v5h-5.500V20h-5v-5.500H4v-5h5.500z"/>"#)  // finance
    case .catShopping: RitmIconSource(stroke: 1.6, body: #"<path d="M5.500 8h13l-1 11.500h-11z"/><path d="M9 10V7a3 3 0 0 1 6 0v3"/>"#)  // finance
    case .catGifts: RitmIconSource(stroke: 1.6, body: #"<rect x="4" y="9" width="16" height="10.500" rx="2"/><path d="M12 9v10.500M3.500 9h17"/><path d="M12 9c-1.500-3.500-5-3.500-5-1.500S10 9 12 9zM12 9c1.500-3.500 5-3.500 5-1.500S14 9 12 9z"/>"#)  // finance
    case .catSport: RitmIconSource(stroke: 1.6, body: #"<path d="M6.500 8v8M17.500 8v8M3.500 10v4M20.500 10v4M6.500 12h11"/>"#)  // finance
    case .catTravel: RitmIconSource(stroke: 1.6, body: #"<rect x="3.500" y="8" width="17" height="11.500" rx="2.500"/><path d="M9 8V6.500A1.500 1.500 0 0 1 10.500 5h3A1.500 1.500 0 0 1 15 6.500V8M8.500 8v11.500M15.500 8v11.500"/>"#)  // finance
    case .catEdu: RitmIconSource(stroke: 1.6, body: #"<path d="M2.500 9.500L12 5l9.500 4.500L12 14z"/><path d="M6 11.800v3.700c0 1.300 2.700 2.500 6 2.500s6-1.200 6-2.500v-3.700M21.500 9.500v5"/>"#)  // finance
    case .catTelecom: RitmIconSource(stroke: 1.6, body: #"<rect x="6.500" y="3" width="11" height="18" rx="2.500"/><path d="M10.500 17.500h3"/>"#)  // finance
    case .catClothes: RitmIconSource(stroke: 1.6, body: #"<path d="M8.500 4L4 6.500l1.800 4 2.200-1V20h8V9.500l2.200 1 1.800-4L15.500 4a3.500 3.500 0 0 1-7 0z"/>"#)  // finance
    case .catBeauty: RitmIconSource(stroke: 1.6, body: #"<path d="M12 3.500s6 6.200 6 10.500a6 6 0 0 1-12 0c0-4.300 6-10.500 6-10.500z"/><path d="M9.500 14.500a2.500 2.500 0 0 0 2.500 2.500"/>"#)  // finance
    case .catKids: RitmIconSource(stroke: 1.6, body: #"<circle cx="12" cy="12" r="8.500"/><path d="M9 10h.01M15 10h.01M8.800 14a4 4 0 0 0 6.400 0"/>"#)  // finance
    case .catPets: RitmIconSource(stroke: 1.6, body: #"<path d="M12 12.500c-2.500 0-4.500 2.200-4.500 4.200 0 1.500 1.200 2.300 2.500 2.300.8 0 1.300-.3 2-.3s1.200.3 2 .3c1.300 0 2.500-.8 2.500-2.300 0-2-2-4.200-4.500-4.200z"/><circle cx="6.500" cy="10.500" r="1.500"/><circle cx="9.500" cy="6.500" r="1.500"/><circle cx="14.500" cy="6.500" r="1.500"/><circle cx="17.500" cy="10.500" r="1.500"/>"#)  // finance
    case .catBills: RitmIconSource(stroke: 1.6, body: #"<rect x="2.500" y="6" width="19" height="12.500" rx="2.500"/><path d="M2.500 10.500h19M6 15h3"/>"#)  // finance
    case .catSalary: RitmIconSource(stroke: 1.6, body: #"<rect x="3.500" y="7.500" width="17" height="12" rx="2.500"/><path d="M9 7.500V6a1.500 1.500 0 0 1 1.500-1.500h3A1.500 1.500 0 0 1 15 6v1.500M3.500 13h17"/>"#)  // finance
    case .catRefund: RitmIconSource(stroke: 1.6, body: #"<path d="M9.500 6.500l-5 5 5 5M5 11.500h9a5 5 0 0 1 5 5V17"/>"#)  // finance
    case .catSale: RitmIconSource(stroke: 1.6, body: #"<path d="M4 4h7.500L20 12.500 12.500 20 4 11.500z"/><circle cx="8.300" cy="8.300" r="1.200"/>"#)  // finance
    case .catOther: RitmIconSource(stroke: 1.6, body: #"<circle cx="6" cy="12" r="1.300"/><circle cx="12" cy="12" r="1.300"/><circle cx="18" cy="12" r="1.300"/>"#)  // finance
    }
  }
}
