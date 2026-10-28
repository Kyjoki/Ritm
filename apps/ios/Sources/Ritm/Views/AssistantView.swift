import RitmCore
import SwiftUI
import UIKit

private struct NativeChatRequest {
  let id: String
  let conversationID: String?
  let text: String
  let mode: ChatMode
  let reviewMessageID: String?
}

struct AssistantView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedID: String?
  @State private var updatedConversation: Conversation?
  @State private var composer = ""
  @State private var mode: ChatMode = .assistant
  @State private var discussionID: String?
  @State private var pending: NativeChatRequest?
  @State private var lastAttempt: NativeChatRequest?
  @State private var sending = false
  @State private var showHistory = false
  @State private var deleteID: String?
  @State private var initialized = false
  @FocusState private var composerFocused: Bool

  private var conversations: [Conversation] { store.bootstrap?.conversations ?? [] }
  private var conversation: Conversation? {
    let stored = conversations.first { $0.id == selectedID }
    if let updatedConversation, updatedConversation.id == selectedID,
      stored == nil || updatedConversation.updatedAt >= (stored?.updatedAt ?? "")
    {
      return updatedConversation
    }
    return stored
  }
  private var messages: [ChatMessage] { conversation?.messages ?? [] }
  private var configured: Bool { store.bootstrap?.aiStatus.configured == true }
  private var selectedReview: ChatMessage? {
    guard let discussionID, let original = messages.first(where: { $0.id == discussionID }) else {
      return nil
    }
    let root = original.ideaReview?.discussion?.rootMessageId ?? original.id
    return messages.last {
      $0.ideaReview != nil && ($0.ideaReview?.discussion?.rootMessageId ?? $0.id) == root
    }
  }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            intro
            if let error = store.errorMessage { RitmErrorBanner(message: error) }
            MutationRecoveryView()
            if messages.isEmpty { suggestions }
            ForEach(messages) { message in
              AssistantMessageCard(
                message: message, conversationID: conversation?.id ?? "",
                onConversation: { updatedConversation = $0 }
              ) {
                discussionID = message.id
                mode = .ideaReview
                composerFocused = true
              }
              .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if sending {
              HStack(spacing: 12) {
                ProgressView()
                Text(
                  store.text(
                    mode == .ideaReview ? "Эксперты разбирают идею…" : "Ritm обдумывает ответ…",
                    mode == .ideaReview ? "Experts are reviewing the idea…" : "Ritm is thinking…"))
              }
              .font(.subheadline).padding().accessibilityAddTraits(.updatesFrequently)
            }
            if let pending, !sending { retryCard(pending) }
            Color.clear.frame(height: 1).id("composer-end")
          }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: messages.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
        .onChange(of: messages.count) { _, _ in
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("composer-end", anchor: .bottom)
          }
        }
        .onChange(of: sending) { _, value in
          if value { proxy.scrollTo("composer-end", anchor: .bottom) }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { composerBar }
    .navigationTitle(store.text("ИИ-помощник", "AI assistant"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showHistory = true
        } label: {
          Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44)
        }
        .accessibilityLabel(store.text("История диалогов", "Conversation history")).disabled(
          sending)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await createConversation() }
        } label: {
          Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
        }
        .accessibilityLabel(store.text("Новый диалог", "New conversation")).disabled(
          !store.canWrite || sending || pending != nil)
      }
    }
    .sheet(isPresented: $showHistory) { history }
    .task {
      if !initialized {
        initialized = true
        selectedID = conversations.first?.id
      }
      consumePrompt()
    }
    .onChange(of: navigation.assistantPrompt) { _, _ in consumePrompt() }
    .onChange(of: navigation.section) { _, section in if section == .assistant { consumePrompt() } }
    .onChange(of: store.lastSyncedAt) { _, _ in
      // A successful bootstrap is authoritative, including deletions on another device.
      // A failed refresh does not change lastSyncedAt. Keep unsent input in either case.
      if let selectedID, !conversations.contains(where: { $0.id == selectedID }) {
        self.selectedID = nil
        updatedConversation = nil
        discussionID = nil
      } else if let updatedConversation,
        let stored = conversations.first(where: { $0.id == updatedConversation.id }),
        stored.updatedAt >= updatedConversation.updatedAt
      {
        self.updatedConversation = nil
      }
    }
    .confirmationDialog(
      store.text("Удалить диалог?", "Delete conversation?"),
      isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }),
      titleVisibility: .visible
    ) {
      Button(store.text("Удалить", "Delete"), role: .destructive) {
        guard let id = deleteID else { return }
        Task {
          if await store.performMutation({ try await $0.deleteConversation(id: id) }) {
            if selectedID == id {
              selectedID = nil
              updatedConversation = nil
              discussionID = nil
            }
          }
        }
      }
    } message: {
      Text(
        store.text(
          "История и ответы этого диалога будут удалены.",
          "The conversation and its replies will be removed."))
    }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(conversation?.title ?? store.text("Спокойно разберёмся", "Let's make a clear plan"))
        .font(.title.bold())
      Label(
        store.text(
          "Изменения расписания — только после подтверждения",
          "Schedule changes require your confirmation"), systemImage: "checkmark.shield"
      )
      .font(.caption).foregroundStyle(.secondary)
      if !configured {
        RitmCard {
          VStack(alignment: .leading, spacing: 12) {
            Text(store.text("Подключите модель в настройках", "Connect a model in settings")).font(
              .headline)
            Button(store.text("Открыть настройки", "Open settings")) {
              navigation.section = .settings
            }.frame(minHeight: 44)
          }
        }
      }
    }
  }
  private var suggestions: some View {
    VStack(spacing: 10) {
      ForEach(
        store.language == .ru
          ? [
            "Что у меня сегодня?", "Спланируй неделю", "Разбей задачу на шаги",
            "Подготовь отчёт о выполненном",
          ]
          : [
            "What is on my schedule today?", "Plan my week", "Break a task into steps",
            "Summarize my completed work",
          ], id: \.self
      ) { prompt in
        Button {
          composer = prompt
          mode = .assistant
          composerFocused = true
        } label: {
          RitmCard {
            HStack {
              Image(systemName: "sparkles").foregroundStyle(.tint)
              Text(prompt)
              Spacer()
              Image(systemName: "arrow.up.left").font(.caption)
            }
          }
        }.buttonStyle(RitmPressStyle()).disabled(pending != nil || sending)
      }
    }
  }
  private var composerBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(store.text("Режим", "Mode"), selection: $mode) {
        Text(store.text("Помощник", "Assistant")).tag(ChatMode.assistant)
        Text(store.text("Разбор идеи", "Idea review")).tag(ChatMode.ideaReview)
      }.pickerStyle(.segmented).disabled(sending || pending != nil)
      if mode == .ideaReview {
        HStack(alignment: .top) {
          Text(
            selectedReview == nil
              ? store.text(
                "Новая идея: четыре роли и общий вывод",
                "New idea: four expert roles and a synthesis")
              : store.text(
                "Продолжение обсуждения выбранной идеи", "Continue discussing the selected idea")
          )
          .font(.caption).foregroundStyle(.secondary)
          Spacer()
          if selectedReview != nil {
            Button(store.text("Новая идея", "New idea")) { discussionID = nil }.font(.caption)
              .disabled(sending || pending != nil)
          }
        }
      }
      HStack(alignment: .bottom, spacing: 10) {
        TextField(
          store.text(
            mode == .ideaReview ? "Опишите идею или уточнение…" : "Напишите Ritm…",
            mode == .ideaReview ? "Describe an idea or follow-up…" : "Message Ritm…"),
          text: $composer, axis: .vertical
        )
        .lineLimit(1...5).font(.body).focused($composerFocused)
        .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .disabled(sending || pending != nil)
        Button {
          Task { await send() }
        } label: {
          Image(systemName: "arrow.up").font(.headline).frame(width: 48, height: 48)
            .background(RitmTheme.lavender, in: Circle()).foregroundStyle(RitmTheme.ink)
        }.buttonStyle(RitmPressStyle())
          .accessibilityLabel(store.text("Отправить", "Send"))
          .disabled(
            !configured || !store.canWrite || sending || pending != nil
              || composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || composer.utf16.count > 6000)
      }
      if composer.utf16.count > 6000 {
        Text(store.text("Максимум 6000 символов.", "Maximum 6000 characters.")).font(.caption)
          .foregroundStyle(.red)
      }
    }.padding(.horizontal, 16).padding(.vertical, 12).background(.regularMaterial)
  }
  private func retryCard(_ request: NativeChatRequest) -> some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(store.text("Ответ ещё не подтверждён", "The reply is not confirmed yet")).font(
          .headline)
        Text(request.text).font(.subheadline).textSelection(.enabled)
        Text(
          store.text(
            "Обновите диалог. При повторе используется тот же идентификатор запроса, чтобы не запускать анализ заново.",
            "Refresh the conversation. Retrying uses the same request ID to avoid starting another analysis."
          )
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button(store.text("Обновить", "Refresh")) { Task { await store.refresh() } }
          Button(store.text("Повторить запрос", "Retry request")) { Task { await submit(request) } }
            .disabled(!store.canWrite)
        }.buttonStyle(.bordered)
        Button(store.text("Вернуть текст в черновик", "Return text to draft")) {
          composer = request.text
          pending = nil
        }
        .font(.subheadline)
      }
    }
  }
  private var history: some View {
    NavigationStack {
      List {
        if conversations.isEmpty {
          Text(store.text("Диалогов пока нет", "No conversations yet")).foregroundStyle(.secondary)
        }
        ForEach(conversations) { item in
          HStack {
            Button {
              guard pending == nil else { return }
              selectedID = item.id
              discussionID = nil
              updatedConversation = nil
              showHistory = false
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline)
                Text("\(item.messages.count) " + store.text("сообщений", "messages")).font(.caption)
                  .foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).disabled(pending != nil)
            if selectedID == item.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            Button(role: .destructive) {
              deleteID = item.id
              showHistory = false
            } label: {
              Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .disabled(!store.canWrite || pending != nil)
          }
        }
      }
      .navigationTitle(store.text("Диалоги", "Conversations"))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Готово", "Done")) { showHistory = false }
        }
      }
    }
  }
  private func consumePrompt() {
    guard navigation.section == .assistant, let prompt = navigation.assistantPrompt, pending == nil,
      !sending
    else { return }
    composer = prompt
    mode = .assistant
    discussionID = nil
    navigation.assistantPrompt = nil
  }
  private func createConversation() async {
    guard let created = await store.write({ try await $0.createConversation() }) else { return }
    selectedID = created.id
    updatedConversation = created
    discussionID = nil
    composer = ""
  }
  private func send() async {
    let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.utf16.count <= 6000, pending == nil, configured else { return }
    let parentID = mode == .ideaReview ? selectedReview?.id : nil
    let previousMatches =
      lastAttempt.map {
        $0.text == text && $0.conversationID == conversation?.id && $0.mode == mode
          && $0.reviewMessageID == parentID
      } == true
    let request = NativeChatRequest(
      id: previousMatches ? lastAttempt!.id : UUID().uuidString, conversationID: conversation?.id,
      text: text, mode: mode, reviewMessageID: parentID)
    pending = request
    lastAttempt = request
    await submit(request)
  }
  private func submit(_ request: NativeChatRequest) async {
    guard !sending, store.canWrite else { return }
    sending = true
    composerFocused = false
    let result = await store.write {
      try await $0.chat(
        conversationId: request.conversationID, message: request.text, requestId: request.id,
        mode: request.mode, reviewMessageId: request.reviewMessageID)
    }
    sending = false
    if let result {
      selectedID = result.id
      updatedConversation = result
      pending = nil
      lastAttempt = nil
      composer = ""
      if request.mode == .ideaReview {
        if let parentID = request.reviewMessageID,
          let parent = result.messages.first(where: { $0.id == parentID })
        {
          let root = parent.ideaReview?.discussion?.rootMessageId ?? parent.id
          discussionID =
            result.messages.last(where: {
              $0.ideaReview != nil && ($0.ideaReview?.discussion?.rootMessageId ?? $0.id) == root
            })?.id
        } else {
          discussionID = result.messages.last(where: { $0.ideaReview != nil })?.id
        }
      }
    }
  }
}

private struct AssistantMessageCard: View {
  @Environment(RitmStore.self) private var store
  let message: ChatMessage
  let conversationID: String
  let onConversation: (Conversation) -> Void
  let onDiscuss: () -> Void
  @State private var copied = false

  var body: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 16) {
        Label(
          message.role == "user" ? store.text("Вы", "You") : "Ritm",
          systemImage: message.role == "user" ? "person.crop.circle" : "sparkles"
        )
        .font(.caption.weight(.semibold)).foregroundStyle(.tint)
        Text(message.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        if !message.steps.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text(store.text("Понятные шаги", "Clear next steps")).font(.headline)
            ForEach(Array(message.steps.enumerated()), id: \.offset) { index, step in
              Text("\(index + 1). \(step)").textSelection(.enabled)
            }
          }
        }
        if !message.proposals.isEmpty {
          ScheduleProposalList(
            message: message, conversationID: conversationID, onConversation: onConversation)
        }
        if let report = message.ideaReview {
          NativeIdeaReport(report: report, onDiscuss: onDiscuss)
        }
        if message.role != "user" {
          Button {
            UIPasteboard.general.string = copyText
            copied = true
          } label: {
            Label(
              store.text(
                copied ? "Скопировано" : "Копировать ответ", copied ? "Copied" : "Copy answer"),
              systemImage: copied ? "checkmark" : "doc.on.doc")
          }
          .font(.caption).frame(minHeight: 44)
        }
      }
    }
  }
  private var copyText: String {
    var parts = [message.text]
    parts += message.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
    parts += message.proposals.map {
      "\($0.title): \($0.before.date ?? "—") \($0.before.time ?? "—") → \($0.after.date ?? "—") \($0.after.time ?? "—") (\($0.after.duration) min)\n\($0.reason)"
    }
    if let report = message.ideaReview {
      parts +=
        [report.synthesis.verdict.rawValue, report.synthesis.summary] + report.synthesis.agreements
        + report.synthesis.disagreements + report.synthesis.questions + report.synthesis.nextSteps
      for expert in report.experts {
        parts +=
          [expert.id.rawValue, expert.summary] + expert.strengths + expert.concerns
          + expert.assumptions + [expert.firstTest]
      }
      if let discussion = report.discussion {
        parts +=
          discussion.changes
          + discussion.verdictChanges.map {
            "\($0.id.rawValue): \($0.before.rawValue) → \($0.after.rawValue)"
          }
      }
    }
    return parts.joined(separator: "\n\n")
  }
}

private struct ScheduleProposalList: View {
  @Environment(RitmStore.self) private var store
  let message: ChatMessage
  let conversationID: String
  let onConversation: (Conversation) -> Void
  @State private var selected: Set<String> = []
  @State private var confirmation: ProposalAction?
  @State private var busy = false

  private var selectedPending: [String] {
    message.proposals.filter { $0.status == .pending && selected.contains($0.id) }.map(\.id)
  }
  private var selectedApplied: [String] {
    message.proposals.filter { $0.status == .applied && selected.contains($0.id) }.map(\.id)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()
      Text(store.text("Предлагаемые изменения", "Proposed changes")).font(.headline)
      ForEach(message.proposals) { proposal in
        VStack(alignment: .leading, spacing: 8) {
          if proposal.status == .pending || proposal.status == .applied {
            Toggle(
              proposal.title,
              isOn: Binding(
                get: { selected.contains(proposal.id) },
                set: {
                  if $0 { selected.insert(proposal.id) } else { selected.remove(proposal.id) }
                })
            )
            .toggleStyle(.switch).font(.headline).disabled(busy)
          } else {
            Text(proposal.title).font(.headline)
          }
          Text(status(proposal.status)).font(.caption).foregroundStyle(.tint)
          Text(store.text("Было: ", "Before: ") + schedule(proposal.before)).font(.subheadline)
            .foregroundStyle(.secondary)
          Text(store.text("Станет: ", "After: ") + schedule(proposal.after)).font(.subheadline)
          Text(proposal.reason).font(.subheadline).textSelection(.enabled)
        }.padding(12).background(
          RitmTheme.lavender.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
      }
      if !selectedPending.isEmpty {
        Button(store.text("Применить выбранное", "Apply selected")) { confirmation = .apply }
          .buttonStyle(.borderedProminent).disabled(!store.canWrite || busy)
        Button(store.text("Отклонить выбранное", "Reject selected")) {
          Task {
            busy = true
            let result = await store.write {
              try await $0.reject(
                conversationId: conversationID, messageId: message.id, proposalIds: selectedPending)
            }
            busy = false
            if let result {
              selected = []
              onConversation(result)
            }
          }
        }.buttonStyle(.bordered).disabled(!store.canWrite || busy)
      }
      if !selectedApplied.isEmpty {
        Button(store.text("Отменить применённое", "Undo applied changes")) { confirmation = .undo }
          .buttonStyle(.bordered).disabled(!store.canWrite || busy)
      }
      Text(
        store.text(
          "Выберите изменения переключателями. Ritm ничего не применяет автоматически.",
          "Select changes using the switches. Ritm never applies them automatically.")
      ).font(.caption).foregroundStyle(.secondary)
    }
    .confirmationDialog(
      store.text(
        confirmation == .undo ? "Отменить выбранные изменения?" : "Применить выбранные изменения?",
        confirmation == .undo ? "Undo selected changes?" : "Apply selected changes?"),
      isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
      titleVisibility: .visible
    ) {
      if let action = confirmation {
        Button(store.text("Подтвердить", "Confirm")) {
          let ids = action == .apply ? selectedPending : selectedApplied
          Task {
            busy = true
            let result = await store.write {
              try await $0.proposals(
                action: action, conversationId: conversationID, messageId: message.id,
                proposalIds: ids)
            }
            busy = false
            if let result {
              selected = []
              onConversation(result.conversation)
            }
          }
        }
      }
    } message: {
      Text(
        store.text(
          "Изменится реальное расписание. При конфликте с другой версией сервер отклонит изменение.",
          "Your real schedule will change. Conflicting edits are rejected by the server."))
    }
  }
  private func status(_ status: ProposalStatus) -> String {
    switch status {
    case .pending: store.text("На рассмотрении", "Pending")
    case .applied: store.text("Применено", "Applied")
    case .rejected: store.text("Отклонено", "Rejected")
    case .undone: store.text("Изменение отменено", "Undone")
    }
  }
  private func schedule(_ value: ScheduleTime) -> String {
    (value.date.map { FeatureDate.label($0, zone: store.timeZone, language: store.language) }
      ?? store.text("Без даты", "No date")) + ", " + FeatureDate.clock(value.time)
      + ", \(value.duration) " + store.text("мин", "min")
  }
}

private struct NativeIdeaReport: View {
  @Environment(RitmStore.self) private var store
  let report: IdeaReviewReport
  let onDiscuss: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Divider()
      Label(store.text("Разбор идеи", "Idea review"), systemImage: "lightbulb").font(.title3.bold())
      Text(verdict(report.synthesis.verdict)).font(.headline).foregroundStyle(.tint)
      Text(report.synthesis.summary).textSelection(.enabled)
      if let discussion = report.discussion {
        Text(store.text("Раунд ", "Round ") + "\(discussion.round)").font(.caption).foregroundStyle(
          .secondary)
        bullets(store.text("Что изменилось", "What changed"), discussion.changes)
        ForEach(discussion.verdictChanges) { change in
          Text(
            expertName(change.id) + ": " + verdict(change.before) + " → " + verdict(change.after)
          ).font(.caption)
        }
      }
      ForEach(report.experts) { expert in
        DisclosureGroup {
          VStack(alignment: .leading, spacing: 12) {
            Text(verdict(expert.verdict)).font(.subheadline.bold()).foregroundStyle(.tint)
            Text(expert.summary).textSelection(.enabled)
            bullets(store.text("Сильные стороны", "Strengths"), expert.strengths)
            bullets(store.text("Опасения", "Concerns"), expert.concerns)
            bullets(store.text("Допущения", "Assumptions"), expert.assumptions)
            Text(store.text("Первый тест", "First test")).font(.headline)
            Text(expert.firstTest).textSelection(.enabled)
          }.padding(.top, 12)
        } label: {
          Text(expertName(expert.id)).font(.headline).frame(minHeight: 44)
        }
      }
      bullets(store.text("В чём согласны", "Agreement"), report.synthesis.agreements)
      bullets(store.text("В чём расходятся", "Disagreement"), report.synthesis.disagreements)
      bullets(store.text("Открытые вопросы", "Open questions"), report.synthesis.questions)
      bullets(store.text("Следующие шаги", "Next steps"), report.synthesis.nextSteps)
      Button(store.text("Обсудить эту идею", "Discuss this idea"), action: onDiscuss).buttonStyle(
        .bordered
      ).frame(minHeight: 44)
      Text(report.model).font(.caption2).foregroundStyle(.secondary)
    }
  }
  @ViewBuilder private func bullets(_ title: String, _ values: [String]) -> some View {
    if !values.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.headline)
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Text("• " + value).textSelection(.enabled)
        }
      }
    }
  }
  private func verdict(_ value: IdeaVerdict) -> String {
    switch value {
    case .promising: store.text("Перспективно", "Promising")
    case .needsTesting: store.text("Нужна проверка", "Needs testing")
    case .weak: store.text("Слабая идея", "Weak idea")
    }
  }
  private func expertName(_ id: IdeaExpertID) -> String {
    switch id {
    case .value: store.text("Ценность", "Value")
    case .feasibility: store.text("Реализуемость", "Feasibility")
    case .resources: store.text("Ресурсы", "Resources")
    case .risks: store.text("Риски", "Risks")
    }
  }
}
