import RitmCore
import SwiftUI

/// «Часовой пояс»: the zones in one group, the chosen one ticked. A tap saves it and goes back.
struct SettingsTimeZonePage: View {
  @Environment(SettingsModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let zones = SettingsTimeZones.zones(including: model.state.server.timeZone)
    SettingsPage(title: model.text("Часовой пояс", "Time zone")) {
      SettingsGroup {
        ForEach(zones, id: \.id) { zone in row(zone) }
      }
    }
  }

  private func row(_ zone: SettingsTimeZones.Zone) -> some View {
    let selected = zone.id == model.draft.timeZone
    return Button {
      model.commit(AccountSettingsPatch(timeZone: zone.id))
      Task {
        try? await Task.sleep(for: reduceMotion ? .zero : .milliseconds(260))
        dismiss()
      }
    } label: {
      SettingsListRow(title: zone.name(model.language)) {
        HStack(spacing: 7) {
          Text(SettingsTimeZones.offsetLabel(zone.id, at: Date()))
            .ritmFont(14).foregroundStyle(RitmTheme.muted)
          RitmSymbol("checkmark").font(.system(size: 18, weight: .semibold))
            .foregroundStyle(RitmTheme.accentColor).opacity(selected ? 1 : 0)
            .accessibilityHidden(true)
        }
      }
    }
    .buttonStyle(SettingsRowButtonStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// «Границы дня»: two wheels, start and end. The pair always stays valid: moving one end past the
/// other drags the other along, so an invalid day is never sent.
struct SettingsWorkDayPage: View {
  @Environment(SettingsModel.self) private var model

  var body: some View {
    SettingsPage(title: model.text("Границы дня", "Day bounds")) {
      HStack(alignment: .top, spacing: 12) {
        SettingsTimeWheel(
          title: model.text("Начало", "Start"),
          time: Binding(get: { model.draft.workDayStart }, set: { model.setWorkDayStart($0) }))
        SettingsTimeWheel(
          title: model.text("Конец", "End"),
          time: Binding(get: { model.draft.workDayEnd }, set: { model.setWorkDayEnd($0) }))
      }
      .padding(.top, 6)
      SettingsFootnote(
        text: model.text(
          "Помощник учитывает эти часы при планировании.", "The assistant uses these hours when planning."))
    }
  }
}

/// `.wheels`: hours and minutes (in steps of five) as two wheels.
private struct SettingsTimeWheel: View {
  let title: String
  @Binding var time: String
  private static let step = 5

  private var parts: (hour: Int, minute: Int) {
    let total = TaskSchedule.timeMinutes(time) ?? 0
    return (total / 60, total % 60)
  }

  private var minutes: [Int] {
    Array(Set(Array(stride(from: 0, to: 60, by: Self.step)) + [parts.minute])).sorted()
  }

  var body: some View {
    VStack(spacing: 2) {
      Text(title).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.muted)
      HStack(spacing: 0) {
        wheel(values: Array(0..<24), selection: Binding(
          get: { parts.hour }, set: { time = TaskSchedule.minuteTime($0 * 60 + parts.minute) }))
        Text(":").ritmFont(21, weight: .semibold).foregroundStyle(RitmTheme.text).padding(.bottom, 3)
        wheel(values: minutes, selection: Binding(
          get: { parts.minute }, set: { time = TaskSchedule.minuteTime(parts.hour * 60 + $0) }))
      }
      .frame(height: 200)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }

  private func wheel(values: [Int], selection: Binding<Int>) -> some View {
    Picker(title, selection: selection) {
      ForEach(values, id: \.self) { value in
        Text(String(format: "%02d", value)).monospacedDigit().tag(value)
      }
    }
    .pickerStyle(.wheel)
    .labelsHidden()
    .frame(width: 66)
  }
}
