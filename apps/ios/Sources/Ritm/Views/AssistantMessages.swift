import RitmCore
import SwiftUI
import UIKit

/// Names and verdicts of the idea experts (IdeaReviewPanel.tsx).
enum IdeaText {
  @MainActor static func role(_ id: IdeaExpertID, store: RitmStore) -> String {
    switch id {
    case .value: store.text("Польза", "Value")
    case .feasibility: store.text("Реализация", "Feasibility")
    case .resources: store.text("Ресурсы", "Resources")
    case .risks: store.text("Риски", "Risks")
    }
  }

  @MainActor static func roleDescription(_ id: IdeaExpertID, store: RitmStore) -> String {
    switch id {
    case .value: store.text("Кому нужна идея и какую проблему она решает", "Who needs the idea and what problem it solves")
    case .feasibility: store.text("Что потребуется, чтобы идея заработала", "What it takes to make the idea work")
    case .resources: store.text("Время, усилия и затраты", "Time, effort and cost")
    case .risks: store.text("Слабые места и возможные последствия", "Weak spots and possible consequences")
    }
  }

  @MainActor static func verdict(_ value: IdeaVerdict, store: RitmStore) -> String {
    switch value {
    case .promising: store.text("Есть потенциал", "Has potential")
    case .needsTesting: store.text("Нужна проверка", "Needs testing")
    case .weak: store.text("Слабая в текущем виде", "Weak as it stands")
    }
  }
}

/// `.a-urow` / `.a-arow`: the user's bubble on the right, Ritm's reply across the full width.
struct AssistantMessageView: View {
  let message: ChatMessage
  let conversationID: String
  let discussionSelected: Bool
  let discussionDisabled: Bool
  let superseded: Bool
  @Binding var openKeys: Set<String>
  let onConversation: (Conversation) -> Void
  let onDiscuss: (Bool) -> Void
  @Environment(RitmStore.self) private var store
  @State private var copied = false

  var body: some View {
    if message.role == "user" {
      UserMessageRow {
        VStack(alignment: .leading, spacing: 7) {
          author
          Text(message.text).ritmFont(13, lineSpacing: 6.5).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 0) {
        author.padding(.bottom, 7)
        if let report = message.ideaReview {
          IdeaReviewView(
            messageID: message.id, report: report, selected: discussionSelected,
            disabled: discussionDisabled, superseded: superseded, openKeys: $openKeys,
            onDiscuss: onDiscuss)
        } else {
          Text(message.text).ritmFont(13, lineSpacing: 6.5).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        }
        if !message.steps.isEmpty { steps.padding(.top, 10) }
        if message.ideaReview == nil && !message.proposals.isEmpty && !conversationID.isEmpty {
          ProposalCard(message: message, conversationID: conversationID, onConversation: onConversation)
            .padding(.top, 10)
        }
        copyButton
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var author: some View {
    Text(message.role == "user" ? store.text("Вы", "You") : "Ritm")
      .ritmFont(10, weight: .bold)
      .foregroundStyle(RitmTheme.accentColor)
  }

  /// `.a-copy`: 44 pt tall, 12 pt muted; the check stays for 1.8 s.
  private var copyButton: some View {
    Button {
      UIPasteboard.general.string = copyText
      copied = true
    } label: {
      HStack(spacing: 6) {
        RitmSymbol(copied ? "checkmark" : "doc.on.doc").font(.system(size: 14))
        Text(copied ? store.text("Скопировано", "Copied") : store.text("Копировать ответ", "Copy reply"))
      }
      .ritmFont(12)
      .foregroundStyle(RitmTheme.muted)
      .padding(.horizontal, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .padding(.top, 9)
    .task(id: copied) {
      guard copied else { return }
      try? await Task.sleep(for: .seconds(1.8))
      if !Task.isCancelled { copied = false }
    }
  }

  private var steps: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(store.text("Понятные шаги", "Clear steps")).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
        .padding(.bottom, 4)
      ForEach(Array(message.steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("\(index + 1).").ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
          Text(step).ritmFont(12, lineSpacing: 4.5).foregroundStyle(RitmTheme.text)
        }
      }
    }
    .padding(.vertical, 16)
    .padding(.horizontal, 17)
    .frame(maxWidth: .infinity, alignment: .leading)
    .assistantBox(RitmTheme.field, radius: 12)
  }

  private var copyText: String {
    var parts = [message.text]
    parts += message.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
    parts += message.proposals.map {
      "\($0.title): \($0.before.date ?? "—") \($0.before.time ?? "—") → \($0.after.date ?? "—") \($0.after.time ?? "—") (\($0.after.duration) min)\n\($0.reason)"
    }
    if let report = message.ideaReview {
      parts += [IdeaText.verdict(report.synthesis.verdict, store: store), report.synthesis.summary]
      parts += report.synthesis.agreements + report.synthesis.disagreements
      parts += report.synthesis.questions + report.synthesis.nextSteps
      for expert in report.experts {
        parts += [IdeaText.role(expert.id, store: store) + " — " + IdeaText.verdict(expert.verdict, store: store), expert.summary]
        parts += expert.strengths + expert.concerns + expert.assumptions + [expert.firstTest]
      }
    }
    return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
}

/// `.a-props`: select changes, confirm, apply, reject or undo; nothing is automatic.
private struct ProposalCard: View {
  let message: ChatMessage
  let conversationID: String
  let onConversation: (Conversation) -> Void
  @Environment(RitmStore.self) private var store
  @State private var selected: Set<String> = []
  @State private var confirmation: ProposalAction?
  @State private var busy = false

  private var pending: [ScheduleProposal] { message.proposals.filter { $0.status == .pending } }
  private var applied: [ScheduleProposal] { message.proposals.filter { $0.status == .applied } }
  private var selectedPending: [String] { pending.map(\.id).filter(selected.contains) }
  private var selectedApplied: [String] { applied.map(\.id).filter(selected.contains) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 7) {
        RitmIcon(.sparklesAssistant).font(.system(size: 14))
        Text(store.text("Предлагаемые изменения", "Proposed changes")).ritmFont(12, weight: .bold)
        Spacer()
        Text("\(message.proposals.count)")
          .ritmFont(10)
          .padding(.vertical, 3)
          .padding(.horizontal, 7)
          .assistantBox(RitmTheme.panel, radius: 7)
      }
      .foregroundStyle(RitmTheme.accentColor)
      Text(hint).ritmFont(11, lineSpacing: 3.5).foregroundStyle(RitmTheme.muted).padding(.top, 8).padding(.bottom, 15)
      VStack(spacing: 12) {
        ForEach(message.proposals) { proposal in row(proposal) }
      }
      // Every row keeps a 12 pt bottom margin, the last one too.
      .padding(.bottom, 12)
      if let confirmation {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            confirmation == .apply
              ? store.text("Применить выбранные изменения (\(selectedPending.count)) к вашему расписанию?", "Apply the selected changes (\(selectedPending.count)) to your schedule?")
              : store.text("Вернуть прежнее расписание для выбранных задач (\(selectedApplied.count))?", "Restore the previous schedule for the selected tasks (\(selectedApplied.count))?")
          )
          .ritmFont(12, lineSpacing: 3.5)
          .foregroundStyle(RitmTheme.text)
          buttonRow {
            Button {
              Task { await run(confirmation == .apply ? .apply : .undo) }
            } label: {
              AssistantButtonLabel(
                title: confirmation == .apply ? store.text("Подтвердить изменения", "Confirm changes") : store.text("Подтвердить отмену", "Confirm undo"),
                symbol: "checkmark")
            }
            .buttonStyle(AssistantButtonStyle(kind: .primary))
            .disabled(busy || !store.canWrite)
            Button(store.text("Назад", "Back")) { self.confirmation = nil }
              .buttonStyle(AssistantButtonStyle())
              .disabled(busy)
          }
        }
        .padding(.top, 15)
      } else if !pending.isEmpty || !applied.isEmpty {
        buttonRow {
          if !pending.isEmpty {
            Button {
              confirmation = .apply
            } label: {
              AssistantButtonLabel(
                title: store.text("Применить выбранные", "Apply selected") + (selectedPending.isEmpty ? "" : " (\(selectedPending.count))"),
                symbol: "checkmark")
            }
            .buttonStyle(AssistantButtonStyle(kind: .primary))
            .disabled(busy || selectedPending.isEmpty)
            Button {
              Task { await run(nil) }
            } label: {
              AssistantButtonLabel(title: store.text("Отклонить", "Reject"), symbol: "xmark")
            }
            .buttonStyle(AssistantButtonStyle())
            .disabled(busy || selectedPending.isEmpty || !store.canWrite)
          }
          if !applied.isEmpty {
            Button {
              confirmation = .undo
            } label: {
              AssistantButtonLabel(title: store.text("Отменить изменения", "Undo changes"), symbol: "arrow.uturn.backward")
            }
            .buttonStyle(AssistantButtonStyle())
            .disabled(busy || selectedApplied.isEmpty)
          }
        }
        .padding(.top, 15)
      }
    }
    .padding(12)
    .background(
      RitmTheme.linear([.init(color: RitmTheme.soft, location: 0), .init(color: RitmTheme.panel, location: 1)], cssAngle: 125),
      in: RoundedRectangle(cornerRadius: 13, style: .circular)
    )
    .overlay { RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Предлагаемые изменения расписания", "Proposed schedule changes"))
  }

  /// `.a-row`: buttons side by side, wrapping into full-width lines when they do not fit.
  private func buttonRow<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
    let content = buttons()
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { content }
      VStack(spacing: 8) { content }
    }
  }

  private var hint: String {
    if !pending.isEmpty {
      return store.text("Выберите подходящие изменения. Ritm применит их после вашего подтверждения.", "Choose the changes that fit. Ritm applies them after you confirm.")
    }
    if !applied.isEmpty {
      return store.text("Выберите применённые изменения, чтобы вернуть прежнее расписание.", "Choose applied changes to restore the previous schedule.")
    }
    return store.text("Этот план сохранён в истории диалога.", "This plan is saved in the conversation history.")
  }

  private func row(_ proposal: ScheduleProposal) -> some View {
    let selectable = proposal.status == .pending || proposal.status == .applied
    let isSelected = selected.contains(proposal.id)
    return VStack(alignment: .leading, spacing: 0) {
      if selectable {
        Button {
          if isSelected { selected.remove(proposal.id) } else { selected.insert(proposal.id) }
          confirmation = nil
        } label: {
          HStack(spacing: 9) {
            RitmSymbol(isSelected ? "checkmark.square.fill" : "square")
              .font(.system(size: 20))
              .foregroundStyle(RitmTheme.accentColor)
            Text(proposal.title).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.text)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(store.text("Выбрать изменение: ", "Select change: ") + proposal.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      } else {
        Text(proposal.title).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.text)
      }
      HStack(spacing: 3) {
        if proposal.status == .applied { RitmSymbol("checkmark").font(.system(size: 9, weight: .bold)) }
        Text(status(proposal.status))
      }
      .ritmFont(9)
      .foregroundStyle(proposal.status == .applied ? RitmTheme.accentColor : RitmTheme.muted)
      .padding(.vertical, 3)
      .padding(.horizontal, 5)
      .background(proposal.status == .applied ? RitmTheme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .circular))
      .overlay { RoundedRectangle(cornerRadius: 6, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
      .padding(.leading, selectable ? 29 : 0)
      HStack(spacing: 10) {
        schedule(store.text("Было", "Before"), proposal.before)
        RitmSymbol("arrow.right").font(.system(size: 15)).foregroundStyle(RitmTheme.muted)
          .accessibilityHidden(true)
        schedule(store.text("Станет", "After"), proposal.after, highlighted: true)
      }
      .padding(.top, 12)
      if !proposal.reason.isEmpty {
        Text(proposal.reason).ritmFont(11, lineSpacing: 4.5).foregroundStyle(RitmTheme.muted).padding(.top, 10)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .assistantBox(proposal.status == .rejected || proposal.status == .undone ? RitmTheme.field : RitmTheme.panel, radius: 11)
  }

  private func schedule(_ label: String, _ value: ScheduleTime, highlighted: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).ritmFont(10).foregroundStyle(RitmTheme.muted)
      Text(value.time.map { FeatureDate.clock($0) } ?? store.text("Время не выбрано", "No time chosen"))
        .ritmFont(13, weight: .semibold)
        .foregroundStyle(highlighted ? RitmTheme.accentColor : RitmTheme.text)
      Text(
        (value.date.map { FeatureDate.label($0, zone: store.timeZone, language: store.language) } ?? store.text("Без даты", "No date"))
          + " · \(value.duration) " + store.text("мин", "min")
      )
      .ritmFont(10)
      .foregroundStyle(RitmTheme.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func status(_ value: ProposalStatus) -> String {
    switch value {
    case .pending: store.text("На рассмотрении", "Pending")
    case .applied: store.text("Применено", "Applied")
    case .rejected: store.text("Отклонено", "Rejected")
    case .undone: store.text("Изменение отменено", "Undone")
    }
  }

  /// nil rejects the selected pending changes.
  private func run(_ action: ProposalAction?) async {
    let ids = action == .undo ? selectedApplied : selectedPending
    guard !ids.isEmpty, !busy else { return }
    busy = true
    defer { busy = false }
    let updated: Conversation?
    if let action {
      updated = await store.write {
        try await $0.proposals(action: action, conversationId: conversationID, messageId: message.id, proposalIds: ids)
      }?.conversation
    } else {
      updated = await store.write {
        try await $0.reject(conversationId: conversationID, messageId: message.id, proposalIds: ids)
      }
    }
    confirmation = nil
    if let updated {
      selected.subtract(ids)
      onConversation(updated)
    }
  }
}
