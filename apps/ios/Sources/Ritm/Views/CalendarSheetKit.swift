import RitmCore
import SwiftUI

// The prototype's calendar sheets (calendar.js `.sec-calendar-sheet`, shell.html `.sheet`): a
// title row with a round close button, small muted labels over 44 pt inputs, side-by-side time
// fields, a switch row, a destructive row and the Cancel / Save pair. Shared by the event
// editor, the event detail and the Ritm task editor.

/// `.sheet` + `.sh-head`: the dense surface, a 20 pt title row with the close button, and the
/// form's rows 14 pt apart.
struct CalendarSheetFrame<Content: View>: View {
  let title: String
  var detents: Set<PresentationDetent> = [.large]
  var busy = false
  private let content: Content
  @Environment(\.dismiss) private var dismiss
  @Environment(RitmStore.self) private var store

  init(
    title: String, detents: Set<PresentationDetent> = [.large], busy: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.detents = detents
    self.busy = busy
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Text(title)
            .ritmFont(20, weight: .semibold, tracking: -0.045)
            .foregroundStyle(RitmTheme.text)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
          Button {
            dismiss()
          } label: {
            RitmSymbol("xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(RitmTheme.muted)
              .frame(width: 44, height: 44)
              .ritmGlass(in: Circle(), interactive: true)
              .contentShape(Circle())
          }
          .buttonStyle(RitmGlassButtonStyle())
          .disabled(busy)
          .accessibilityLabel(store.text("Закрыть", "Close"))
        }
        VStack(alignment: .leading, spacing: 14) { content }
          .padding(.top, 4)
          .padding(.bottom, 8)
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 40)
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.interactively)
    .background(RitmTheme.glassDense.ignoresSafeArea())
    .presentationDetents(detents)
    .presentationBackground(RitmTheme.glassDense)
    .presentationCornerRadius(22)
    .ritmSheetGrabber()
    .interactiveDismissDisabled(busy)
  }
}

/// `label.f`: a 12 pt muted label and its control, 6 pt apart.
struct CalendarSheetField<Content: View>: View {
  let label: String
  private let content: Content

  init(_ label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).ritmFont(12).foregroundStyle(RitmTheme.muted)
      content
    }
  }
}

extension View {
  /// The sheet's input surface: 44 pt tall, 12 pt radius, a hairline on the field fill, 15 pt text.
  func calendarInput(minHeight: CGFloat = 44) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
    return self
      .ritmFont(15)
      .foregroundStyle(RitmTheme.text)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
      .background(RitmTheme.field, in: shape)
      .overlay { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
  }
}

/// A single- or multi-line text input.
struct CalendarTextInput: View {
  let placeholder: String
  @Binding var text: String
  var lines: ClosedRange<Int> = 1...4
  var minHeight: CGFloat = 44

  var body: some View {
    TextField(placeholder, text: $text, axis: .vertical)
      .lineLimit(lines)
      .calendarInput(minHeight: minHeight)
  }
}

/// `input[type=date]`: «dd.mm.yyyy» with a calendar glyph; a tap opens the month grid below.
struct CalendarDateField: View {
  @Binding var value: String
  let zone: String
  @State private var open = false
  @Environment(RitmStore.self) private var store

  private var text: String {
    let parts = value.split(separator: "-")
    return parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : value
  }

  var body: some View {
    VStack(spacing: 8) {
      Button {
        withAnimation(RitmMotion.ease(0.2)) { open.toggle() }
      } label: {
        HStack {
          Text(text).monospacedDigit()
          Spacer(minLength: 8)
          RitmIcon(.calCalendar).font(.system(size: 16)).foregroundStyle(RitmTheme.text)
        }
        .calendarInput()
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.98))
      .accessibilityLabel(store.text("Дата", "Date") + ", " + text)
      if open {
        DatePicker(
          "",
          selection: Binding(
            get: { FeatureDate.date(value, zone: zone) },
            set: {
              value = HabitSchedule.dateKey($0, timeZone: zone)
              withAnimation(RitmMotion.ease(0.2)) { open = false }
            }), displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(RitmTheme.accentColor)
        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
        .environment(\.calendar, FeatureDate.calendar(zone))
        .padding(8)
        .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .circular))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1)
        }
      }
    }
  }
}

/// `input[type=time]`: «HH:mm» typed in, with a clock glyph.
struct CalendarTimeField: View {
  @Binding var text: String
  var focus: FocusState<Bool>.Binding?

  var body: some View {
    HStack {
      field
      RitmSymbol("clock").font(.system(size: 16)).foregroundStyle(RitmTheme.text)
        .accessibilityHidden(true)
    }
    .calendarInput()
  }

  @ViewBuilder private var field: some View {
    let input = TextField("HH:mm", text: $text)
      .keyboardType(.numbersAndPunctuation)
      .monospacedDigit()
    if let focus { input.focused(focus) } else { input }
  }
}

/// `.cs-sw`: a label and a switch, 44 pt tall.
struct CalendarSwitchRow: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(title, isOn: $isOn)
      .ritmFont(15)
      .foregroundStyle(RitmTheme.text)
      .tint(RitmTheme.accentColor)
      .frame(minHeight: 44)
  }
}

/// `select`: the chosen option and a chevron pair; the options open as a menu.
struct CalendarSelect<Value: Hashable>: View {
  let options: [(value: Value, title: String)]
  @Binding var selection: Value

  var body: some View {
    Menu {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Button {
          selection = option.value
        } label: {
          if option.value == selection {
            Label { Text(option.title) } icon: { RitmSymbol("checkmark") }
          } else {
            Text(option.title)
          }
        }
      }
    } label: {
      HStack(spacing: 8) {
        Text(options.first { $0.value == selection }?.title ?? "").lineLimit(1)
        Spacer(minLength: 0)
        RitmSymbol("chevron.up.chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
      }
      .calendarInput()
      .contentShape(Rectangle())
    }
  }
}

/// `.cs-err`: a danger line on the soft danger fill.
struct CalendarSheetError: View {
  let message: String

  var body: some View {
    Text(message)
      .ritmFont(13, lineSpacing: 3)
      .foregroundStyle(RitmTheme.danger)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RitmTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .circular))
      .accessibilityAddTraits(.updatesFrequently)
  }
}

/// `.cs-note`: 13 pt muted text.
struct CalendarSheetNote: View {
  let text: String
  var size: CGFloat = 13

  var body: some View {
    Text(text)
      .ritmFont(size, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// `.cs-btn`: 48 pt tall, 14 pt radius; soft with an accent label, primary, or destructive.
struct CalendarSheetButtonStyle: ButtonStyle {
  enum Kind { case soft, primary, danger }
  var kind: Kind = .soft
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    configuration.label
      .ritmFont(15, weight: .semibold)
      .lineLimit(1)
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background { background(shape) }
      .overlay {
        if kind == .soft { shape.strokeBorder(RitmTheme.line, lineWidth: 1) }
      }
      .scaleEffect(configuration.isPressed && !reduceMotion ? RitmMotion.pressScale : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
      .opacity(isEnabled ? 1 : 0.5)
  }

  private var foreground: Color {
    switch kind {
    case .soft: RitmTheme.accentColor
    case .primary: RitmTheme.ctaInk
    case .danger: RitmTheme.danger
    }
  }

  @ViewBuilder private func background(_ shape: RoundedRectangle) -> some View {
    switch kind {
    case .soft: shape.fill(RitmTheme.soft)
    case .primary: shape.fill(RitmTheme.ctaGradient).shadow(color: RitmTheme.ctaShadow, radius: 10, y: 6)
    case .danger: shape.fill(RitmTheme.dangerSoft)
    }
  }
}

/// `.cs-btns`: «Отмена» and the primary action, 10 pt apart.
struct CalendarSheetButtons: View {
  let cancelTitle: String
  let saveTitle: String
  var canSave = true
  let cancel: () -> Void
  let save: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Button(cancelTitle, action: cancel).buttonStyle(CalendarSheetButtonStyle())
      Button(saveTitle, action: save).buttonStyle(CalendarSheetButtonStyle(kind: .primary))
        .disabled(!canSave)
    }
  }
}

/// «Начало» / «Конец» side by side. The end is derived from the start and the duration; a valid
/// end typed in sets the duration (the entry must end after it starts and by midnight).
struct CalendarTimeRange: View {
  @Binding var start: String
  @Binding var duration: Int
  @Environment(RitmStore.self) private var store
  @State private var endText = ""
  @FocusState private var endFocused: Bool

  private var startMinutes: Int? { TaskSchedule.timeMinutes(start) }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      CalendarSheetField(store.text("Начало", "Start")) { CalendarTimeField(text: $start) }
      CalendarSheetField(store.text("Конец", "End")) {
        CalendarTimeField(text: $endText, focus: $endFocused)
      }
    }
    .onAppear { syncEnd() }
    .onChange(of: start) { _, _ in if !endFocused { syncEnd() } }
    .onChange(of: duration) { _, _ in if !endFocused { syncEnd() } }
    .onChange(of: endFocused) { _, focused in if !focused { syncEnd() } }
    .onChange(of: endText) { _, text in
      guard endFocused, let from = startMinutes, let end = TaskSchedule.timeMinutes(text),
        end > from
      else { return }
      duration = end - from
    }
  }

  private func syncEnd() {
    guard let from = startMinutes else { return }
    endText = TaskSchedule.minuteTime(min(1439, from + duration))
  }
}
