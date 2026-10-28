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
}
struct RitmRootView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @AppStorage("ritm.appearance") private var appearance = "system"
  @State private var navigation = RitmNavigation()
  @State private var showingMore = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Namespace private var indicator
  private var effectiveScheme: ColorScheme {
    appearance == "dark" ? .dark : appearance == "light" ? .light : scheme
  }
  private let mainSections: [RitmSection] = [.day, .calendar, .habits, .assistant]

  var body: some View {
    Group {
      if store.isSignedIn {
        VStack(spacing: 0) {
          header
          ZStack {
            ForEach(RitmSection.allCases.filter { navigation.visited.contains($0) }, id: \.self) {
              section in
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
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        .sheet(isPresented: $showingMore) { moreSheet }
        .environment(navigation)
      } else {
        LoginView()
      }
    }
    .tint(RitmTheme.accent(effectiveScheme))
    .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
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

  private var header: some View {
    HStack(spacing: 10) {
      RitmMark()
        .frame(width: 24, height: 24)
        .foregroundStyle(RitmTheme.ink)
        .frame(width: 36, height: 36)
        .background(RitmTheme.lavender.gradient, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
      Text("Ritm").font(.title2.bold())
      Spacer()
      Button {
        appearance = effectiveScheme == .dark ? "light" : "dark"
      } label: {
        Image(systemName: effectiveScheme == .dark ? "sun.max" : "moon")
          .font(.system(size: 20)).frame(width: 44, height: 44)
          .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityLabel(store.text("Переключить тему", "Switch appearance"))
    }
    .padding(.horizontal, 16).padding(.vertical, 6)
  }

  private var navigationBar: some View {
    HStack(spacing: 0) {
      ForEach(mainSections, id: \.self) { section in
        navButton(
          title: title(section), symbol: section.symbol,
          selected: navigation.section == section
        ) { navigation.section = section }
      }
      navButton(
        title: store.text("Ещё", "More"), symbol: "ellipsis",
        selected: [.finance, .settings].contains(navigation.section)
      ) { showingMore = true }
    }
    .padding(6)
    .background {
      Capsule()
        .fill(
          reduceTransparency
            ? AnyShapeStyle(RitmTheme.surface(effectiveScheme))
            : AnyShapeStyle(.ultraThinMaterial)
        )
        .overlay {
          Capsule().fill(RitmTheme.lavender.opacity(effectiveScheme == .dark ? 0.10 : 0.06))
        }
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
    .padding(.horizontal, 8).padding(.bottom, 8)
    .modifier(RitmEntrance(delay: 0.08))
  }

  private func navButton(
    title: String, symbol: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button {
      withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.95)) {
        action()
      }
    } label: {
      VStack(spacing: 3) {
        Image(systemName: symbol).font(.system(size: 21, weight: .regular)).frame(height: 23)
        if !dynamicTypeSize.isAccessibilitySize {
          Text(title).font(.system(size: 10, weight: .medium))
            .multilineTextAlignment(.center).lineLimit(2).frame(height: 24)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 60)
      .foregroundStyle(selected ? RitmTheme.accent(effectiveScheme) : Color.secondary)
      .background {
        if selected {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(RitmTheme.lavender.opacity(effectiveScheme == .dark ? 0.19 : 0.16))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                Color.primary.opacity(0.12), lineWidth: 1)
            }
            .matchedGeometryEffect(id: "active", in: indicator)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(title.replacingOccurrences(of: "\n", with: ""))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var moreSheet: some View {
    NavigationStack {
      VStack(spacing: 12) {
        ForEach([RitmSection.finance, .settings], id: \.self) { section in
          Button {
            navigation.section = section
            showingMore = false
          } label: {
            HStack(spacing: 14) {
              Image(systemName: section.symbol).frame(width: 26)
              Text(title(section)).font(.headline)
              Spacer()
              Image(systemName: "chevron.right").font(.caption)
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: 56)
            .background(RitmTheme.lavender.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
          }.buttonStyle(RitmPressStyle())
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      .navigationTitle(store.text("Ещё", "More"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Готово", "Done")) { showingMore = false }
        }
      }
      .background { RitmBackground() }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func title(_ section: RitmSection) -> String {
    switch section {
    case .day: store.text("Мой день", "My day")
    case .calendar: store.text("Календарь", "Calendar")
    case .habits: store.text("Привычки", "Habits")
    case .assistant: store.text("ИИ-\nпомощник", "AI assistant")
    case .finance: store.text("Финансы", "Finance")
    case .settings: store.text("Настройки", "Settings")
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
        .font(.footnote).foregroundStyle(.secondary)
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
        Text(store.text("Обновлено", "Updated"))
        Text(date, style: .time)
      } else {
        Image(systemName: "arrow.triangle.2.circlepath")
        Text(store.text("Ожидаем обновления", "Waiting to refresh"))
      }
    }
    .font(.caption).foregroundStyle(.secondary).accessibilityElement(children: .combine)
  }
}
