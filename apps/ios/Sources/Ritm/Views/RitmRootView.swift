import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class RitmNavigation {
  var section: RitmSection = .day { didSet { visited.insert(section) } }
  private(set) var visited: Set<RitmSection> = [.day]
  var assistantPrompt: String?
  var habitCelebration: String?
}
enum RitmSection: String, CaseIterable, Hashable {
  case day, calendar, habits, assistant, finance, settings
  var symbol: String {
    switch self {
    case .day: "square.grid.2x2"
    case .calendar: "calendar"
    case .habits: "checklist"
    case .assistant: "sparkles"
    case .finance: "wallet.pass"
    case .settings: "slider.horizontal.3"
    }
  }
  /// Pages whose header scrolls with the content, as on the web. The other pages still keep
  /// their actions in the navigation bar, so their header stays pinned for now.
  var embedsHeader: Bool { [.day, .habits, .settings].contains(self) }
}
struct RitmRootView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.colorScheme) private var scheme
  @State private var navigation = RitmNavigation()
  @State private var showingMore = false
  private let mainSections: [RitmSection] = [.day, .calendar, .habits, .assistant]
  private var visitedSections: [RitmSection] {
    RitmSection.allCases.filter { navigation.visited.contains($0) }
  }

  private var preferredScheme: ColorScheme? {
    switch store.theme {
    case .dark: .dark
    case .light: .light
    case .system: nil
    }
  }

  var body: some View {
    Group {
      if store.isSignedIn {
        ZStack {
          VStack(spacing: 0) {
            if !navigation.section.embedsHeader { RitmShellHeader().padding(.horizontal, 16) }
            ZStack {
              ForEach(visitedSections, id: \.self) { section in
                // The web switches pages instantly; only the nav indicator moves.
                NavigationStack { sectionView(section) }
                  .opacity(navigation.section == section ? 1 : 0)
                  .allowsHitTesting(navigation.section == section)
                  .accessibilityHidden(navigation.section != section)
                  .environment(\.ritmPageActive, navigation.section == section)
                  .zIndex(navigation.section == section ? 1 : 0)
                  .toolbarBackground(.hidden, for: .navigationBar)
              }
            }
          }
          .background { RitmBackground() }
          .safeAreaInset(edge: .bottom, spacing: 0) {
            RitmNavigationBar(
              sections: mainSections, current: navigation.section,
              select: { navigation.section = $0 }, openMore: { showingMore = true })
          }
          if showingMore {
            RitmMoreDialog(current: navigation.section) { section in
              if let section { navigation.section = section }
              showingMore = false
            }
            .zIndex(2)
          }
        }
        .environment(navigation)
      } else {
        LoginView()
      }
    }
    .tint(RitmTheme.accentColor)
    .foregroundStyle(RitmTheme.text)
    .preferredColorScheme(preferredScheme)
    .environment(\.locale, Locale(identifier: store.language.rawValue))
    .onChange(of: navigation.section) { _, _ in
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
  }

  @ViewBuilder private func sectionView(_ section: RitmSection) -> some View {
    switch section {
    case .day: DayView()
    case .calendar: CalendarView()
    case .habits: HabitsView()
    case .assistant: AssistantView()
    case .finance: FinanceView()
    case .settings: AccountView()
    }
  }
}

extension RitmSection {
  @MainActor func title(_ store: RitmStore) -> String {
    switch self {
    case .day: store.text("Мой день", "My day")
    case .calendar: store.text("Календарь", "Calendar")
    case .habits: store.text("Привычки", "Habits")
    case .assistant: store.text("ИИ-помощник", "AI assistant")
    case .finance: store.text("Финансы", "Finance")
    case .settings: store.text("Настройки", "Settings")
    }
  }
}

/// Web `.app-header`: 62 pt, 29 pt brand mark, wordmark and the 44 pt theme toggle.
struct RitmShellHeader: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.colorScheme) private var scheme

  private var showingDark: Bool {
    store.theme == .system ? scheme == .dark : store.theme == .dark
  }

  var body: some View {
    HStack(spacing: 8) {
      RitmMark()
        .fill(Color(rgb: 0x34234C))
        .frame(width: 18, height: 18)
        .frame(width: 29, height: 29)
        .background(
          RitmTheme.linear(
            [.init(color: Color(rgb: 0xE5D7FF), location: 0),
             .init(color: Color(rgb: 0xC4ABEB), location: 1)], cssAngle: 130),
          in: RoundedRectangle(cornerRadius: 10, style: .circular)
        )
        .shadow(color: Color(rgb: 0xB98DEB, opacity: 0.13), radius: 12)
        .accessibilityHidden(true)
      Text("Ritm")
        .ritmText(.brand)
        .foregroundStyle(RitmTheme.text)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      Button {
        Task { await store.toggleTheme(showingDark: showingDark) }
      } label: {
        Image(systemName: showingDark ? "sun.max" : "moon")
          .font(.system(size: 18))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 44, height: 44)
          .background {
            let shape = RoundedRectangle(cornerRadius: 13, style: .circular)
            shape
              .fill(
                RitmTheme.linear(
                  [.init(color: RitmTheme.glassRaised, location: 0),
                   .init(color: RitmTheme.panel, location: 1)], cssAngle: 150))
              .overlay { shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
              .shadow(color: Color(rgb: 0x583882, opacity: 0.11), radius: 10, y: 6)
          }
      }
      .buttonStyle(RitmPressStyle(scale: 0.9))
      .disabled(store.pendingTheme != nil)
      .accessibilityLabel(store.text("Переключить тему", "Switch appearance"))
    }
    .frame(height: 62)
  }
}

/// Web mobile navigation (navigation-glass.css): a 374 × 74 capsule 8 pt from the edges,
/// five 72 pt columns and one 52 pt indicator that slides between them.
private struct RitmNavigationBar: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Namespace private var indicator
  let sections: [RitmSection]
  let current: RitmSection
  let select: (RitmSection) -> Void
  let openMore: () -> Void

  private var moreSelected: Bool { [.finance, .settings].contains(current) }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(sections, id: \.self) { section in
        item(title: section.title(store), symbol: section.symbol, selected: current == section) {
          select(section)
        }
      }
      // «Ещё» takes the name of the open page behind it (App.tsx).
      item(
        title: moreSelected ? current.title(store) : store.text("Ещё", "More"),
        symbol: "ellipsis", selected: moreSelected, action: openMore)
    }
    .padding(7)
    .background { capsule }
    .padding(.horizontal, 8)
    .padding(.bottom, 8)
    .animation(reduceMotion ? nil : RitmMotion.indicator, value: current)
  }

  private var capsule: some View {
    Capsule()
      .fill(reduceTransparency ? AnyShapeStyle(RitmTheme.panel) : AnyShapeStyle(.ultraThinMaterial))
      .overlay {
        if !reduceTransparency {
          Capsule().fill(
            RitmTheme.linear(
              [
                .init(
                  color: Color(
                    light: 0xFFFCFF, dark: 0x3B2D51, lightOpacity: 0.82, darkOpacity: 0.85),
                  location: 0),
                .init(
                  color: Color(
                    light: 0xE1D3F4, dark: 0x1F182D, lightOpacity: 0.65, darkOpacity: 0.76),
                  location: 1),
              ], cssAngle: 150))
          Capsule().fill(
            RitmTheme.linear(
              [.init(color: .white.opacity(0.16), location: 0), .init(color: .clear, location: 0.42)],
              cssAngle: 175))
        }
      }
      .overlay {
        Capsule().strokeBorder(
          contrast == .increased
            ? RitmTheme.text
            : Color(light: 0xFFFFFF, dark: 0xE5D3FC, lightOpacity: 0.76, darkOpacity: 0.3),
          lineWidth: 1)
      }
      .shadow(color: Color(rgb: 0x2C1848, opacity: 0.2), radius: 15, y: 12)
  }

  private func item(
    title: String, symbol: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: symbol)
          .font(.system(size: 21, weight: .regular))
          .frame(height: 22)
          .modifier(RitmIconSettle(active: selected))
        if !dynamicTypeSize.isAccessibilitySize {
          Text(title)
            .ritmText(.navLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: 22)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 60)
      .foregroundStyle(
        contrast == .increased
          ? RitmTheme.text
          : selected
            ? Color(light: 0x643B96, dark: 0xE2CAFF) : Color(light: 0x645275, dark: 0xC1B3D4)
      )
      .background {
        if selected {
          activeIndicator.padding(.vertical, 4)
            .matchedGeometryEffect(id: "active", in: indicator)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.95))
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var activeIndicator: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
    return shape
      .fill(
        RitmTheme.linear(
          [
            .init(
              color: Color(light: 0xA574DF, dark: 0xC299F1, lightOpacity: 0.24, darkOpacity: 0.28),
              location: 0),
            .init(
              color: Color(light: 0xC1A4E8, dark: 0x805CB1, lightOpacity: 0.14, darkOpacity: 0.2),
              location: 1),
          ], cssAngle: 145)
      )
      .overlay {
        shape.strokeBorder(
          Color(light: 0xFFFFFF, dark: 0xE5CDFF, lightOpacity: 0.64, darkOpacity: 0.24),
          lineWidth: 1)
      }
      .shadow(color: Color(rgb: 0x553086, opacity: 0.12), radius: 6, y: 4)
  }
}

/// The active nav icon settles from .88 to 1 over 210 ms.
private struct RitmIconSettle: ViewModifier {
  let active: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scale: CGFloat = 1

  func body(content: Content) -> some View {
    content
      .scaleEffect(scale)
      .onChange(of: active) { _, isActive in
        guard isActive, !reduceMotion else { return }
        scale = 0.88
        Task { @MainActor in withAnimation(RitmMotion.ease(0.21)) { scale = 1 } }
      }
  }
}

/// Web «Ещё разделы»: a centred 358 pt dialog over a dimmed backdrop.
private struct RitmMoreDialog: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false
  let current: RitmSection
  let close: (RitmSection?) -> Void

  var body: some View {
    ZStack {
      Color(rgb: 0x190E2D, opacity: 0.5)
        .ignoresSafeArea()
        .opacity(shown ? 1 : 0)
        .onTapGesture { dismiss(nil) }
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(store.text("Ещё разделы", "More sections"))
            .ritmText(.sectionTitle)
            .foregroundStyle(RitmTheme.text)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button {
            dismiss(nil)
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 17))
              .foregroundStyle(RitmTheme.muted)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(RitmPressStyle())
          .accessibilityLabel(store.text("Закрыть", "Close"))
        }
        .padding(.bottom, 12)
        VStack(spacing: 10) {
          ForEach([RitmSection.finance, .settings], id: \.self) { section in
            row(section)
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
      }
      .padding(20)
      .frame(maxWidth: 358)
      .background {
        let shape = RoundedRectangle(cornerRadius: 22, style: .circular)
        shape.fill(RitmTheme.glassDense)
          .overlay { shape.strokeBorder(RitmTheme.panelBorder, lineWidth: 1) }
          .shadow(color: Color(rgb: 0x1A0D2D, opacity: 0.3), radius: 45, y: 32)
      }
      .padding(.horizontal, 16)
      .scaleEffect(shown || reduceMotion ? 1 : 0.955)
      .opacity(shown ? 1 : 0)
      .accessibilityAddTraits(.isModal)
    }
    .onAppear {
      withAnimation(reduceMotion ? nil : RitmMotion.dialogIn) { shown = true }
    }
  }

  private func row(_ section: RitmSection) -> some View {
    let selected = section == current
    return Button {
      dismiss(section)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: section.symbol).font(.system(size: 22)).frame(width: 26)
        Text(section.title(store)).font(.system(size: 16))
        Spacer()
        if selected {
          Image(systemName: "checkmark").font(.system(size: 18)).accessibilityHidden(true)
        }
      }
      .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.text)
      .padding(.vertical, 12).padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 56)
      .background {
        let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
        shape.fill(RitmTheme.soft)
          .overlay {
            shape.strokeBorder(selected ? RitmTheme.accentColor : RitmTheme.line, lineWidth: 1)
          }
      }
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func dismiss(_ section: RitmSection?) {
    withAnimation(reduceMotion ? nil : RitmMotion.dialogOut) { shown = false }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 180))
      close(section)
    }
  }
}

struct MutationRecoveryView: View {
  @Environment(RitmStore.self) private var store
  var body: some View {
    if store.uncertainWrite {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          store.text(
            "Предыдущая операция могла сохраниться. Проверьте данные перед повтором.",
            "The previous action may have been saved. Check your data before trying again.")
        )
        .ritmText(.body).foregroundStyle(RitmTheme.muted)
        Button {
          Task { await store.refresh() }
        } label: {
          Label(store.text("Обновить данные", "Refresh data"), systemImage: "arrow.clockwise")
            .frame(minHeight: 44)
        }.disabled(store.isLoading || store.isMutating)
        Button {
          store.acknowledgeUncertainWrite()
        } label: {
          Text(store.text("Я проверил данные", "I have checked the data")).frame(minHeight: 44)
        }
      }
    }
  }
}
struct SyncStatusView: View {
  @Environment(RitmStore.self) private var store

  /// Times use AM/PM in both languages (AGENTS.md).
  private func clock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: store.timeZone)
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
  }

  var body: some View {
    HStack(spacing: 8) {
      if store.isLoading || store.isMutating {
        ProgressView().controlSize(.small)
        Text(
          store.isMutating
            ? store.text("Сохраняем…", "Saving…") : store.text("Обновляем…", "Refreshing…"))
      } else if store.isOffline {
        Image(systemName: "wifi.slash")
        Text(
          store.text(
            "Нет связи · данные могут быть устаревшими", "Offline · data may be out of date"))
      } else if let date = store.lastSyncedAt {
        Image(systemName: "checkmark.circle")
        Text(store.text("Обновлено", "Updated") + " " + clock(date))
      } else {
        Image(systemName: "arrow.triangle.2.circlepath")
        Text(store.text("Ожидаем обновления", "Waiting to refresh"))
      }
    }
    .ritmText(.cardCaption).foregroundStyle(RitmTheme.muted).accessibilityElement(children: .combine)
  }
}
