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

/// `.assistant-message`: the user's bubble on the right, Ritm's reply across the full width.
struct AssistantMessageView: View {
  let message: ChatMessage
  let conversationID: String
  let discussionSelected: Bool
  let discussionDisabled: Bool
  let superseded: Bool
  let onConversation: (Conversation) -> Void
  let onDiscuss: (Bool) -> Void
  @Environment(RitmStore.self) private var store
  @State private var copied = false

  var body: some View {
    if message.role == "user" {
      UserMessageRow {
        VStack(alignment: .leading, spacing: 7) {
          author
          Text(message.text).ritmFont(13, lineSpacing: 9).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 0) {
        author.padding(.bottom, 7)
        if let report = message.ideaReview {
          IdeaReviewView(
            report: report, selected: discussionSelected, disabled: discussionDisabled,
            superseded: superseded, onDiscuss: onDiscuss)
        } else {
          Text(message.text).ritmFont(13, lineSpacing: 9).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        }
        if !message.steps.isEmpty { steps.padding(.top, 17) }
        if message.ideaReview == nil && !message.proposals.isEmpty && !conversationID.isEmpty {
          ProposalCard(message: message, conversationID: conversationID, onConversation: onConversation)
            .padding(.top, 17)
        }
        Button {
          UIPasteboard.general.string = copyText
          copied = true
        } label: {
          Label(
            copied ? store.text("Скопировано", "Copied") : store.text("Копировать ответ", "Copy reply"),
            systemImage: copied ? "checkmark" : "doc.on.doc")
            .ritmFont(12)
            .foregroundStyle(RitmTheme.muted)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .padding(.top, 9)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var author: some View {
    Text(message.role == "user" ? store.text("Вы", "You") : "Ritm")
      .ritmFont(10, weight: .bold)
      .foregroundStyle(RitmTheme.accentColor)
  }

  private var steps: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(store.text("Понятные шаги", "Clear steps")).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
        .padding(.bottom, 4)
      ForEach(Array(message.steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("\(index + 1).").ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.accentColor)
          Text(step).ritmFont(12, lineSpacing: 8).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        }
      }
    }
    .padding(.vertical, 16)
    .padding(.horizontal, 17)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .circular))
    .overlay { RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
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

/// `.assistant-proposals`: select changes, confirm, apply, reject or undo; nothing is automatic.
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
        Image(systemName: "sparkles").font(.system(size: 14))
        Text(store.text("Предлагаемые изменения", "Proposed changes")).ritmFont(12, weight: .bold)
        Spacer()
        Text("\(message.proposals.count)")
          .ritmFont(10)
          .padding(.vertical, 3)
          .padding(.horizontal, 6)
          .background(RitmTheme.panel, in: RoundedRectangle(cornerRadius: 7, style: .circular))
          .overlay { RoundedRectangle(cornerRadius: 7, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
      }
      .foregroundStyle(RitmTheme.accentColor)
      Text(hint).ritmFont(11, lineSpacing: 6).foregroundStyle(RitmTheme.muted).padding(.top, 8).padding(.bottom, 15)
      VStack(spacing: 12) {
        ForEach(message.proposals) { proposal in row(proposal) }
      }
      if let confirmation {
        VStack(alignment: .leading, spacing: 11) {
          Text(
            confirmation == .apply
              ? store.text("Применить выбранные изменения (\(selectedPending.count)) к вашему расписанию?", "Apply the selected changes (\(selectedPending.count)) to your schedule?")
              : store.text("Вернуть прежнее расписание для выбранных задач (\(selectedApplied.count))?", "Restore the previous schedule for the selected tasks (\(selectedApplied.count))?")
          )
          .ritmFont(12, lineSpacing: 4)
          .foregroundStyle(RitmTheme.text)
          HStack(spacing: 8) {
            Button {
              Task { await run(confirmation == .apply ? .apply : .undo) }
            } label: {
              Label(confirmation == .apply ? store.text("Подтвердить изменения", "Confirm changes") : store.text("Подтвердить отмену", "Confirm undo"), systemImage: "checkmark")
            }
            .buttonStyle(RitmPrimaryButtonStyle())
            .disabled(busy || !store.canWrite)
            Button(store.text("Назад", "Back")) { self.confirmation = nil }
              .buttonStyle(RitmSecondaryButtonStyle())
              .disabled(busy)
          }
        }
        .padding(.top, 15)
      } else if !pending.isEmpty || !applied.isEmpty {
        HStack(spacing: 8) {
          if !pending.isEmpty {
            Button {
              confirmation = .apply
            } label: {
              Label(store.text("Применить выбранные", "Apply selected") + (selectedPending.isEmpty ? "" : " (\(selectedPending.count))"), systemImage: "checkmark")
            }
            .buttonStyle(RitmPrimaryButtonStyle())
            .disabled(busy || selectedPending.isEmpty)
            Button {
              Task { await run(nil) }
            } label: {
              Label(store.text("Отклонить", "Reject"), systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(RitmSecondaryButtonStyle())
            .disabled(busy || selectedPending.isEmpty || !store.canWrite)
          }
          if !applied.isEmpty {
            Button {
              confirmation = .undo
            } label: {
              Label(store.text("Отменить изменения", "Undo changes"), systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
            .buttonStyle(RitmSecondaryButtonStyle())
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
      HStack(alignment: .center, spacing: 9) {
        if selectable {
          Button {
            if isSelected { selected.remove(proposal.id) } else { selected.insert(proposal.id) }
            confirmation = nil
          } label: {
            HStack(spacing: 9) {
              Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundStyle(RitmTheme.accentColor)
              Text(proposal.title).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.text)
                .multilineTextAlignment(.leading)
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
        Spacer(minLength: 0)
      }
      HStack(spacing: 3) {
        if proposal.status == .applied { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
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
        Image(systemName: "arrow.right").font(.system(size: 15)).foregroundStyle(RitmTheme.muted)
          .accessibilityHidden(true)
        schedule(store.text("Станет", "After"), proposal.after, highlighted: true)
      }
      .padding(.top, 12)
      if !proposal.reason.isEmpty {
        Text(proposal.reason).ritmFont(11, lineSpacing: 7).foregroundStyle(RitmTheme.muted).padding(.top, 10)
          .textSelection(.enabled)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      proposal.status == .rejected || proposal.status == .undone ? RitmTheme.field : RitmTheme.panel,
      in: RoundedRectangle(cornerRadius: 11, style: .circular)
    )
    .overlay { RoundedRectangle(cornerRadius: 11, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
  }

  private func schedule(_ label: String, _ value: ScheduleTime, highlighted: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).ritmFont(10).foregroundStyle(RitmTheme.muted)
      Text(value.time.map { FeatureDate.clock($0) } ?? store.text("Время не выбрано", "No time chosen"))
        .ritmFont(13, weight: .semibold)
        .foregroundStyle(highlighted ? RitmTheme.accentColor : RitmTheme.text)
      Text(
        (value.date.map { FeatureDate.label($0, zone: store.timeZone, language: store.language) } ?? store.text("Без даты", "No date"))
          + " · \(value.duration) " + store.text("мин", "min"))
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

/// `.idea-review`: the joint view first, then each expert behind a disclosure.
private struct IdeaReviewView: View {
  let report: IdeaReviewReport
  let selected: Bool
  let disabled: Bool
  let superseded: Bool
  let onDiscuss: (Bool) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    let synthesis = report.synthesis
    return VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "lightbulb").font(.system(size: 16)).foregroundStyle(RitmTheme.accentColor)
          Text(store.text("Общее мнение", "Overall view")).ritmFont(14, weight: .bold).foregroundStyle(RitmTheme.text)
          Spacer(minLength: 0)
          if let discussion = report.discussion {
            Text(store.text("Оценка №\(discussion.round)", "Review #\(discussion.round)"))
              .ritmFont(10, weight: .semibold)
              .foregroundStyle(RitmTheme.accentColor)
              .padding(.vertical, 3)
              .padding(.horizontal, 7)
              .background(RitmTheme.soft, in: Capsule())
          }
        }
        verdictChip(synthesis.verdict)
        Text(synthesis.summary).ritmFont(13, lineSpacing: 7).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        if let discussion = report.discussion {
          list(store.text("Что изменилось после ваших ответов", "What changed after your answers"), discussion.changes)
          if discussion.verdictChanges.isEmpty {
            Text(store.text("Итоговые оценки экспертов остались прежними; аргументы обновлены выше.", "The experts' verdicts stayed the same; the arguments above were updated."))
              .ritmFont(10, lineSpacing: 3)
              .foregroundStyle(RitmTheme.muted)
          } else {
            VStack(alignment: .leading, spacing: 4) {
              Text(store.text("Пересмотренные оценки", "Revised verdicts")).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.text)
              ForEach(discussion.verdictChanges) { change in
                Text(IdeaText.role(change.id, store: store) + ": " + IdeaText.verdict(change.before, store: store) + " → " + IdeaText.verdict(change.after, store: store))
                  .ritmFont(11)
                  .foregroundStyle(RitmTheme.muted)
              }
            }
          }
        }
        list(store.text("В чём согласны", "Where they agree"), synthesis.agreements)
        list(store.text("Где мнения расходятся", "Where they disagree"), synthesis.disagreements)
        list(store.text("Что нужно уточнить", "What to clarify"), synthesis.questions, numbered: true)
        if !synthesis.questions.isEmpty && !superseded {
          Button(store.text("Ответить на вопросы", "Answer the questions")) { onDiscuss(true) }
            .buttonStyle(RitmTextButtonStyle(size: 12))
            .disabled(disabled)
        }
        list(store.text("Следующие шаги", "Next steps"), synthesis.nextSteps)
      }
      .padding(14)
      .background(RitmTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .circular))
      .overlay { RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
      ForEach(report.experts) { expert in
        DisclosureGroup {
          VStack(alignment: .leading, spacing: 10) {
            Text(expert.summary).ritmFont(12, lineSpacing: 6).foregroundStyle(RitmTheme.text).textSelection(.enabled)
            list(store.text("Сильные стороны", "Strengths"), expert.strengths)
            list(store.text("Сомнения", "Concerns"), expert.concerns)
            list(store.text("Предположения", "Assumptions"), expert.assumptions)
            VStack(alignment: .leading, spacing: 4) {
              Text(store.text("Первая проверка", "First test")).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.text)
              Text(expert.firstTest).ritmFont(12, lineSpacing: 5).foregroundStyle(RitmTheme.muted).textSelection(.enabled)
            }
          }
          .padding(.top, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
          HStack(spacing: 8) {
            Text(IdeaText.role(expert.id, store: store)).ritmFont(12, weight: .bold).foregroundStyle(RitmTheme.text)
            Text(IdeaText.verdict(expert.verdict, store: store)).ritmFont(11).foregroundStyle(RitmTheme.muted)
          }
          .frame(minHeight: 44)
        }
        .tint(RitmTheme.accentColor)
        .padding(.horizontal, 12)
        .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 12, style: .circular))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
      }
      Text(
        report.discussion != nil
          ? store.text("Модель: \(report.model). Каждый эксперт учитывает исходную идею, ваши уточнения и только свои прежние оценки. Общий вывод собирается после их ответов. Факты в интернете не проверяются.", "Model: \(report.model). Each expert considers the original idea, your clarifications and only their own earlier assessments. The joint view is built after their answers. Facts are not checked on the internet.")
          : store.text("Модель: \(report.model). Каждый эксперт получает исходную идею отдельным запросом, без ответов остальных. Общий вывод собирается после их оценок. Факты в интернете не проверяются.", "Model: \(report.model). Each expert gets the original idea in a separate request, without the others' answers. The joint view is built after their assessments. Facts are not checked on the internet.")
      )
      .ritmFont(10, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      VStack(alignment: .leading, spacing: 6) {
        Button {
          onDiscuss(false)
        } label: {
          Label(selected ? store.text("Обсуждение выбрано", "Discussion selected") : store.text("Обсудить с экспертами", "Discuss with the experts"), systemImage: "bubble.left")
        }
        .buttonStyle(RitmSecondaryButtonStyle())
        .disabled(disabled || superseded)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if superseded {
          Text(store.text("Есть более новая оценка этой идеи — продолжите обсуждение под ней.", "There is a newer review of this idea — continue the discussion under it."))
            .ritmFont(11).foregroundStyle(RitmTheme.muted)
        } else if (report.discussion?.round ?? 1) >= AssistantPlan.discussionRounds {
          Text(store.text("Достигнуто 8 оценок этой идеи. Начните новый разбор с её обновлённым описанием.", "This idea has reached 8 reviews. Start a new review with its updated description."))
            .ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Разбор идеи независимыми ИИ-экспертами", "Idea review by independent AI experts"))
  }

  private func verdictChip(_ verdict: IdeaVerdict) -> some View {
    Text(IdeaText.verdict(verdict, store: store))
      .ritmFont(11, weight: .semibold)
      .foregroundStyle(verdict == .weak ? RitmTheme.danger : RitmTheme.accentColor)
      .padding(.vertical, 4)
      .padding(.horizontal, 9)
      .background(verdict == .weak ? RitmTheme.dangerSoft : RitmTheme.soft, in: Capsule())
  }

  @ViewBuilder private func list(_ title: String, _ items: [String], numbered: Bool = false) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.text)
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          Text((numbered ? "\(index + 1). " : "• ") + item)
            .ritmFont(12, lineSpacing: 5)
            .foregroundStyle(RitmTheme.muted)
            .textSelection(.enabled)
        }
      }
    }
  }
}
