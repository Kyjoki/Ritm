import RitmCore
import SwiftUI

struct NativeChatRequest {
  let id: String
  let conversationID: String?
  let text: String
  let mode: ChatMode
  let reviewMessageID: String?
  var failure: String?
  var retryAt: Date?
  var retryBlocked = false
}

/// «ИИ-помощник» (proto/sections/assistant.js): one scrolling page with the title, the history
/// panel and the chat panel; the composer is the last block of the chat panel.
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
  @State private var sending = false
  @State private var historyOpen = false
  @State private var deleteTarget: Conversation?
  @State private var initialized = false
  @State private var questionsOpen = false
  @State private var openExperts: Set<String> = []
  @FocusState private var composerFocused: Bool

  private static let endID = "chat-end"

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
    discussionID.flatMap { AssistantPlan.latestReview(messages, from: $0) }
  }
  private var discussionStale: Bool {
    guard let discussionID, let review = selectedReview else { return false }
    return review.id != discussionID
  }
  private var discussionLimit: Bool { selectedReview.map(AssistantPlan.discussionLimitReached) ?? false }
  private var failed: Bool { pending?.failure != nil }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            heading.ritmPageReveal(index: 0)
            if let error = store.errorMessage, pending == nil {
              RitmErrorBanner(message: error).padding(.bottom, 12)
            }
            MutationRecoveryView()
            if historyOpen { history.padding(.bottom, 12) }
            chat.ritmPageReveal(index: 1)
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 24)
          .frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: messages.count) { _, _ in
          withAnimation(reduceMotion ? nil : RitmMotion.ease(0.28)) { proxy.scrollTo(Self.endID, anchor: .bottom) }
        }
        .onChange(of: sending) { _, value in if value { proxy.scrollTo(Self.endID, anchor: .bottom) } }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
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
  }

  // MARK: Heading and history

  private var heading: some View {
    VStack(alignment: .leading, spacing: 0) {
      RitmPageHeading(title: store.text("ИИ-помощник", "AI assistant"))
      HStack(spacing: 9) {
        Button {
          withAnimation(reduceMotion ? nil : RitmMotion.ease(0.24)) { historyOpen.toggle() }
        } label: {
          HStack(spacing: 7) {
            RitmSymbol("clock.arrow.circlepath").font(.system(size: 15))
            Text(store.text("История", "History"))
            RitmSymbol("chevron.down").font(.system(size: 12, weight: .semibold))
              .rotationEffect(.degrees(historyOpen ? 180 : 0))
          }
        }
        .buttonStyle(AssistantButtonStyle())
        .accessibilityAddTraits(historyOpen ? .isSelected : [])
        Button {
          Task { await createConversation() }
        } label: {
          AssistantButtonLabel(title: store.text("Новый диалог", "New conversation"), symbol: "plus", iconSize: 14)
        }
        .buttonStyle(AssistantButtonStyle())
        .disabled(!store.canWrite || sending)
      }
      .padding(.bottom, 14)
    }
  }

  private var history: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(store.text("Диалоги", "Conversations")).ritmFont(15, weight: .bold).foregroundStyle(RitmTheme.text)
        Spacer()
        Text("\(conversations.count)")
          .ritmFont(11, weight: .medium)
          .foregroundStyle(RitmTheme.muted)
          .padding(.vertical, 3)
          .padding(.horizontal, 7)
          .assistantBox(RitmTheme.panel, radius: 7)
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 12)
      if conversations.isEmpty {
        VStack(spacing: 8) {
          RitmSymbol("bubble.left").font(.system(size: 20))
          Text(store.text("Ваши диалоги появятся здесь.", "Your conversations will appear here.")).ritmFont(12)
        }
        .foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(12)
      } else {
        LazyVStack(spacing: 5) {
          ForEach(conversations) { item in conversationRow(item) }
        }
      }
      if let target = deleteTarget { deleteConfirmation(target) }
      HStack(spacing: 8) {
        RitmSymbol("checkmark.shield").font(.system(size: 15)).accessibilityHidden(true)
        Text(store.text("Расписание меняется только с вашего согласия.", "Your schedule changes only with your consent."))
          .ritmFont(11, lineSpacing: 3)
      }
      .foregroundStyle(RitmTheme.muted)
      .padding(.top, 16)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      .padding(.top, 16)
    }
    .padding(.vertical, 17)
    .padding(.horizontal, 11)
    .background { RitmPanelBackground(radius: 24) }
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private func conversationRow(_ item: Conversation) -> some View {
    let active = item.id == selectedID
    let title = item.title.isEmpty ? store.text("Новый диалог", "New conversation") : item.title
    return HStack(spacing: 0) {
      Button {
        selectedID = item.id
        discussionID = nil
        updatedConversation = nil
        withAnimation(reduceMotion ? nil : RitmMotion.ease(0.24)) { historyOpen = false }
      } label: {
        HStack(spacing: 9) {
          RitmSymbol("bubble.left").font(.system(size: 14))
          Text(title).lineLimit(1).truncationMode(.tail)
          Spacer(minLength: 0)
        }
        .ritmFont(13, weight: active ? .semibold : .regular)
        .foregroundStyle(active ? RitmTheme.accentColor : RitmTheme.muted)
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.98))
      .disabled(sending)
      .accessibilityAddTraits(active ? .isSelected : [])
      Button {
        deleteTarget = item
      } label: {
        RitmSymbol("trash").font(.system(size: 14)).foregroundStyle(RitmTheme.muted)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .disabled(sending)
      .accessibilityLabel(store.text("Удалить диалог «\(title)»", "Delete conversation “\(title)”"))
    }
    .background(active ? RitmTheme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .circular)
        .strokeBorder(active ? RitmTheme.line : Color.clear, lineWidth: 1)
    }
  }

  private func deleteConfirmation(_ target: Conversation) -> some View {
    let title = target.title.isEmpty ? store.text("Новый диалог", "New conversation") : target.title
    return VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Удалить диалог?", "Delete conversation?")).ritmFont(12, weight: .bold)
        .foregroundStyle(RitmTheme.text)
      Text(store.text("«\(title)» и его сообщения будут удалены.", "“\(title)” and its messages will be deleted."))
        .ritmFont(11, lineSpacing: 3)
        .foregroundStyle(RitmTheme.muted)
        .padding(.top, 6)
      HStack(spacing: 8) {
        Button(store.text("Оставить", "Keep")) { deleteTarget = nil }
          .buttonStyle(AssistantButtonStyle())
        Button(store.text("Удалить", "Delete")) { Task { await deleteConversation(target.id) } }
          .buttonStyle(AssistantButtonStyle())
          .disabled(!store.canWrite)
      }
      .padding(.top, 10)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .assistantBox(RitmTheme.soft, radius: 11)
    .padding(.vertical, 12)
  }

  // MARK: Chat panel

  private var chat: some View {
    let list = messages
    return VStack(spacing: 0) {
      chatHeader
      LazyVStack(alignment: .leading, spacing: 20) {
        if list.isEmpty && pending == nil { welcome }
        ForEach(list) { message in messageRow(message, in: list) }
        if let pending { pendingRequest(pending) }
        if mode == .ideaReview { discussionContext }
        Color.clear.frame(height: 1).id(Self.endID)
      }
      .padding(.vertical, 18)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RitmTheme.glassDense)
      .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
      composerArea
    }
    .background { RitmPanelBackground(radius: 24) }
  }

  private func messageRow(_ message: ChatMessage, in list: [ChatMessage]) -> some View {
    let review = message.ideaReview != nil
    return AssistantMessageView(
      message: message, conversationID: conversation?.id ?? "",
      discussionSelected: mode == .ideaReview && discussionID == message.id,
      discussionDisabled: sending || failed || (review && AssistantPlan.discussionLimitReached(message)),
      superseded: review && AssistantPlan.latestReview(list, from: message.id)?.id != message.id,
      openKeys: $openExperts,
      onConversation: { updatedConversation = $0 },
      onDiscuss: { showQuestions in discuss(message.id, showQuestions: showQuestions) })
  }

  private var chatHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        AssistantOrb(size: 51)
        VStack(alignment: .leading, spacing: 3) {
          Text(mode == .ideaReview ? store.text("Разбор идей", "Idea review") : store.text("Помощник Ritm", "Ritm assistant"))
            .ritmFont(14, weight: .bold)
            .foregroundStyle(RitmTheme.text)
          Text(
            configured
              ? store.text("Знает ваши задачи и привычки", "Knows your tasks and habits")
              : store.text("Настройте OpenAI для начала диалога", "Set up OpenAI to start a conversation")
          )
          .ritmFont(10)
          .foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 0)
        Circle()
          .fill(configured ? RitmTheme.accentColor : RitmTheme.muted.opacity(0.6))
          .frame(width: 7, height: 7)
          .accessibilityLabel(configured ? store.text("Ключ настроен", "Key configured") : store.text("Не настроен", "Not configured"))
      }
      RitmSegmentedControl(
        label: store.text("Режим ИИ", "AI mode"), values: [ChatMode.assistant, .ideaReview],
        title: { $0 == .ideaReview ? store.text("Разбор идей", "Idea review") : store.text("Помощник", "Assistant") },
        selection: modeBinding
      )
      .disabled(sending || failed)
    }
    .padding(.vertical, 17)
    .padding(.horizontal, 16)
  }

  /// Switching to the assistant leaves a discussion.
  private var modeBinding: Binding<ChatMode> {
    Binding(
      get: { mode },
      set: { value in
        mode = value
        if value == .assistant { discussionID = nil }
      })
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 0) {
      RitmIcon(.sparklesAssistant)
        .font(.system(size: 22))
        .foregroundStyle(RitmTheme.accentColor)
        .frame(width: 52, height: 52)
        .assistantBox(RitmTheme.soft, radius: 17)
        .accessibilityHidden(true)
      Text(mode == .ideaReview ? store.text("Посмотрим на идею с четырёх сторон", "Let's look at the idea from four sides") : store.text("С чего начнём?", "Where shall we start?"))
        .ritmFont(24, weight: .bold, tracking: -0.04)
        .foregroundStyle(RitmTheme.text)
        .padding(.top, 16)
        .accessibilityAddTraits(.isHeader)
      Text(
        mode == .ideaReview
          ? store.text(
            "Опишите идею, для кого она и чего вы хотите добиться. Получите отдельные оценки экспертов и общий вывод, включая разногласия.",
            "Describe the idea, who it is for and what you want to achieve. You get separate expert assessments and a joint conclusion, including disagreements.")
          : store.text(
            "Помогу распределить дела, найти свободное время и сделать первый шаг.",
            "I'll help spread your tasks, find free time and take the first step.")
      )
      .ritmFont(12, lineSpacing: 4.5)
      .foregroundStyle(RitmTheme.muted)
      .padding(.top, 8)
      if mode == .ideaReview {
        VStack(spacing: 8) {
          ForEach(IdeaExpertID.allCases, id: \.self) { role in
            VStack(alignment: .leading, spacing: 4) {
              Text(IdeaText.role(role, store: store)).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.text)
              Text(IdeaText.roleDescription(role, store: store)).ritmFont(11).foregroundStyle(RitmTheme.muted)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .assistantBox(RitmTheme.panel, radius: 13)
          }
        }
        .padding(.top, 16)
      } else {
        VStack(spacing: 8) {
          ForEach(AssistantPrompt.all, id: \.title) { prompt in promptButton(prompt) }
        }
        .padding(.top, 16)
      }
      if !configured { setupCard.padding(.top, 16) }
    }
  }

  private func promptButton(_ prompt: AssistantPrompt) -> some View {
    Button {
      choose(store.text(prompt.title, prompt.english))
    } label: {
      HStack(spacing: 10) {
        RitmSymbol(prompt.symbol)
          .font(.system(size: 16))
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 33, height: 33)
          .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 10, style: .circular))
        VStack(alignment: .leading, spacing: 2) {
          Text(store.text(prompt.title, prompt.english)).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.text)
          Text(store.text(prompt.subtitle, prompt.englishSubtitle)).ritmFont(10).foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 0)
        RitmSymbol("arrow.right").font(.system(size: 14)).foregroundStyle(RitmTheme.accentColor)
          .accessibilityHidden(true)
      }
      .padding(11)
      .frame(minHeight: 59)
      .assistantBox(RitmTheme.panel, radius: 13)
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle(scale: 0.98))
    .disabled(sending)
  }

  private var setupCard: some View {
    HStack(alignment: .top, spacing: 10) {
      RitmSymbol("slider.horizontal.3").font(.system(size: 16)).foregroundStyle(RitmTheme.accentColor)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(store.text("Помощник пока не подключён", "The assistant is not connected yet"))
          .ritmFont(12, weight: .semibold)
          .foregroundStyle(RitmTheme.text)
        Text(
          store.text(
            "Добавьте API-ключ OpenAI в настройках. После подключения Ritm сможет отвечать на ваши запросы.",
            "Add an OpenAI API key in Settings. Once connected, Ritm can answer your requests.")
        )
        .ritmFont(11, lineSpacing: 3.5)
        .foregroundStyle(RitmTheme.muted)
        Button(store.text("Открыть настройки", "Open settings")) { navigation.section = .settings }
          .buttonStyle(AssistantButtonStyle())
          .padding(.top, 4)
      }
    }
    .padding(12)
    .assistantBox(RitmTheme.soft, radius: 13)
  }

  // MARK: Sending state

  @ViewBuilder private func pendingRequest(_ request: NativeChatRequest) -> some View {
    UserMessageRow {
      VStack(alignment: .leading, spacing: 7) {
        Text(store.text("Вы", "You")).ritmFont(10, weight: .bold).foregroundStyle(RitmTheme.accentColor)
        Text(request.text).ritmFont(13, lineSpacing: 6.5).foregroundStyle(RitmTheme.text)
        Text(sending ? store.text("Отправляем…", "Sending…") : store.text("Не удалось получить ответ", "Could not get a reply"))
          .ritmFont(10, lineSpacing: 3)
          .foregroundStyle(RitmTheme.muted)
      }
    }
    if sending {
      HStack(spacing: 10) {
        AssistantOrb(size: 32)
        Text(
          request.mode == .ideaReview
            ? (request.reviewMessageID != nil
              ? store.text("Эксперты пересматривают свои оценки…", "The experts are revising their assessments…")
              : store.text("Эксперты оценивают идею…", "The experts are assessing the idea…"))
            : store.text("Ritm изучает ваши планы", "Ritm is studying your plans")
        )
        .ritmFont(12)
        .foregroundStyle(RitmTheme.muted)
        AssistantThinkingDots()
      }
      .frame(minHeight: 40)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.updatesFrequently)
    } else if let failure = request.failure {
      failureCard(request, failure)
    }
  }

  private func failureCard(_ request: NativeChatRequest, _ failure: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(store.text("Не удалось получить ответ", "Could not get a reply")).ritmFont(12, weight: .bold)
        .foregroundStyle(RitmTheme.text)
      Text(failure).ritmFont(12, lineSpacing: 4.5).foregroundStyle(RitmTheme.muted).padding(.top, 7).padding(.bottom, 4)
      // The clock only ticks while a retry pause is running.
      if let retryAt = request.retryAt, retryAt > Date() {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          retryRow(request, remaining: max(0, Int(ceil(retryAt.timeIntervalSince(context.date)))))
        }
      } else {
        retryRow(request, remaining: 0)
      }
      if !configured {
        Button(store.text("Настройки", "Settings")) { navigation.section = .settings }
          .buttonStyle(AssistantButtonStyle())
          .padding(.top, 8)
      }
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .assistantBox(RitmTheme.soft, radius: 12)
  }

  private func retryRow(_ request: NativeChatRequest, remaining: Int) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { retryButtons(request, remaining: remaining) }
      VStack(spacing: 8) { retryButtons(request, remaining: remaining) }
    }
    .padding(.top, 10)
  }

  @ViewBuilder private func retryButtons(_ request: NativeChatRequest, remaining: Int) -> some View {
    Button {
      Task { await submit(request) }
    } label: {
      AssistantButtonLabel(
        title: remaining > 0
          ? store.text("Повторить через \(remaining) с", "Retry in \(remaining) s")
          : store.text("Повторить", "Retry"),
        symbol: "arrow.clockwise")
    }
    .buttonStyle(AssistantButtonStyle())
    .disabled(!configured || sending || remaining > 0 || request.retryBlocked || !store.canWrite)
    Button(store.text("Изменить сообщение", "Edit message")) {
      composer = request.text
      mode = request.mode
      discussionID = request.reviewMessageID
      pending = nil
      composerFocused = true
    }
    .buttonStyle(AssistantButtonStyle())
  }

  @ViewBuilder private var discussionContext: some View {
    if let review = selectedReview {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(store.text("Обсуждение идеи · Оценка №\(review.ideaReview?.discussion?.round ?? 1)", "Idea discussion · Review #\(review.ideaReview?.discussion?.round ?? 1)"))
            .ritmFont(12, weight: .bold)
            .foregroundStyle(RitmTheme.accentColor)
          Spacer(minLength: 0)
          Button {
            startNewIdea()
          } label: {
            AssistantButtonLabel(title: store.text("Новая идея", "New idea"), symbol: "plus", iconSize: 13)
          }
          .buttonStyle(AssistantButtonStyle(small: true))
          .disabled(sending || failed)
        }
        Text(AssistantPlan.ideaText(messages, review: review))
          .ritmFont(12, lineSpacing: 3.5)
          .foregroundStyle(RitmTheme.text)
          .lineLimit(2)
        if let questions = review.ideaReview?.synthesis.questions, !questions.isEmpty {
          AssistantDisclosure(isOpen: $questionsOpen) {
            Text(store.text("Вопросы экспертов (\(questions.count))", "Expert questions (\(questions.count))"))
              .ritmFont(12)
              .foregroundStyle(RitmTheme.accentColor)
          } content: {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                Text("\(index + 1). \(question)").ritmFont(12, lineSpacing: 3.5).foregroundStyle(RitmTheme.text)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        Text(
          discussionLimit
            ? store.text("Достигнуто 8 оценок этой идеи. Начните новый разбор с её обновлённым описанием.", "This idea has reached 8 reviews. Start a new review with its updated description.")
            : discussionStale
              ? store.text("Появилась новая оценка. Выберите её, чтобы продолжить обсуждение.", "A newer review is available. Choose it to continue the discussion.")
              : store.text("Ответьте на вопросы или уточните идею. Каждый эксперт пересмотрит своё мнение с учётом ваших ответов.", "Answer the questions or refine the idea. Each expert will revisit their view with your answers.")
        )
        .ritmFont(10, lineSpacing: 3)
        .foregroundStyle(RitmTheme.muted)
        if discussionStale {
          Button(store.text("Перейти к новой оценке", "Go to the newer review")) { discussionID = review.id }
            .buttonStyle(AssistantButtonStyle())
            .disabled(sending || failed)
        }
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .assistantBox(RitmTheme.soft, radius: 12)
    } else if discussionID != nil {
      VStack(alignment: .leading, spacing: 6) {
        Text(store.text("Эта оценка больше недоступна. Выберите сохранённый разбор или начните новую идею.", "This review is no longer available. Choose a saved review or start a new idea."))
          .ritmFont(10, lineSpacing: 3)
          .foregroundStyle(RitmTheme.muted)
        Button(store.text("Новая идея", "New idea")) { startNewIdea() }
          .buttonStyle(AssistantButtonStyle())
          .disabled(sending || failed)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .assistantBox(RitmTheme.soft, radius: 12)
    }
  }

  // MARK: Composer

  private var composerArea: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !messages.isEmpty && mode == .assistant { chips }
      if !configured && !messages.isEmpty {
        HStack {
          Text(store.text("Для новых ответов подключите OpenAI.", "Connect OpenAI for new replies.")).ritmFont(10)
            .foregroundStyle(RitmTheme.muted)
          Spacer()
          Button {
            navigation.section = .settings
          } label: {
            HStack(spacing: 4) {
              Text(store.text("Настройки", "Settings"))
              RitmSymbol("arrow.right").font(.system(size: 11))
            }
          }
          .buttonStyle(RitmTextButtonStyle())
        }
      }
      field
      HStack(spacing: 5) {
        RitmSymbol("checkmark.shield").font(.system(size: 10))
        Text(mode == .ideaReview ? store.text("Разбор идеи не меняет ваше расписание", "An idea review does not change your schedule") : store.text("Изменения только после вашего подтверждения", "Changes only after your confirmation"))
      }
      .ritmFont(9)
      .foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity)
      .padding(.top, 9)
      .accessibilityElement(children: .combine)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 13)
  }

  /// `.a-chips`: quick prompts, one line that scrolls sideways; plain pills, no glass.
  private var chips: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 6) {
        ForEach(AssistantPrompt.all, id: \.title) { prompt in
          Button {
            choose(store.text(prompt.title, prompt.english))
          } label: {
            Text(store.text(prompt.title, prompt.english))
              .ritmFont(11)
              .foregroundStyle(RitmTheme.muted)
              .padding(.horizontal, 11)
              .frame(minHeight: 44)
              .background(RitmTheme.panel, in: Capsule())
              .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
              .contentShape(Capsule())
          }
          .buttonStyle(RitmPressStyle())
          .disabled(sending)
        }
      }
      .padding(.trailing, 12)
    }
    .scrollIndicators(.hidden)
    .padding(.vertical, 12)
    .padding(.trailing, -12)
  }

  /// `.a-field`: the input and the 44 pt send button in one field-coloured box.
  private var field: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField(
        "", text: $composer,
        prompt: Text(placeholder).foregroundColor(RitmTheme.muted), axis: .vertical
      )
      .lineLimit(2...6)
      .ritmFont(16)
      .foregroundStyle(RitmTheme.text)
      .focused($composerFocused)
      .disabled(sending)
      .padding(.vertical, 5)
      .onChange(of: composer) { _, value in
        var limited = value
        while limited.utf16.count > 6000 { limited.removeLast() }
        if limited != value { composer = limited }
      }
      .accessibilityLabel(composerLabel)
      Button {
        Task { await send() }
      } label: {
        Group {
          if sending {
            ProgressView().tint(RitmTheme.accentInk)
          } else {
            RitmSymbol("arrow.up").font(.system(size: 18, weight: .semibold))
          }
        }
        .foregroundStyle(RitmTheme.accentInk)
        .frame(width: 44, height: 44)
        .background(RitmTheme.ctaGradient, in: RoundedRectangle(cornerRadius: 13, style: .circular))
        .opacity(canSend || sending ? 1 : 0.6)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .disabled(!canSend)
      .accessibilityLabel(sending ? store.text("Отправка сообщения", "Sending message") : store.text("Отправить сообщение", "Send message"))
    }
    .padding(.vertical, 8)
    .padding(.leading, 12)
    .padding(.trailing, 8)
    .background(RitmTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .circular)
        .strokeBorder(composerFocused ? RitmTheme.accentColor : RitmTheme.line, lineWidth: 1)
    }
    .padding(.top, 12)
  }

  private var placeholder: String {
    if mode == .ideaReview {
      return discussionID != nil
        ? store.text("Ответьте на вопросы или уточните идею…", "Answer the questions or refine the idea…")
        : store.text("Опишите вашу идею…", "Describe your idea…")
    }
    return store.text("Спросите о своих планах…", "Ask about your plans…")
  }

  private var composerLabel: String {
    if mode == .ideaReview {
      return discussionID != nil
        ? store.text("Ответ экспертам или уточнение идеи", "Reply to the experts or refine the idea")
        : store.text("Идея для разбора экспертами", "Idea for the experts to review")
    }
    return store.text("Сообщение ИИ-помощнику", "Message to the AI assistant")
  }

  private var canSend: Bool {
    !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending && configured
      && store.canWrite && !failed && !(mode == .ideaReview && (discussionStale || discussionLimit))
  }

  // MARK: Actions

  private func choose(_ prompt: String) {
    composer = prompt
    mode = .assistant
    discussionID = nil
    composerFocused = true
  }

  private func discuss(_ id: String, showQuestions: Bool) {
    discussionID = id
    mode = .ideaReview
    questionsOpen = showQuestions
    composerFocused = true
  }

  private func startNewIdea() {
    discussionID = nil
    questionsOpen = false
    composer = ""
    composerFocused = true
  }

  private func consumePrompt() {
    guard navigation.section == .assistant, let prompt = navigation.assistantPrompt, !sending,
      !failed
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
    composerFocused = true
  }

  private func deleteConversation(_ id: String) async {
    if await store.performMutation({ try await $0.deleteConversation(id: id) }) {
      deleteTarget = nil
      if selectedID == id {
        selectedID = nil
        updatedConversation = nil
        discussionID = nil
      }
    }
  }

  private func send() async {
    let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSend, text.utf16.count <= 6000 else { return }
    let parentID = mode == .ideaReview ? selectedReview?.id : nil
    let request = NativeChatRequest(
      id: UUID().uuidString, conversationID: conversation?.id, text: text, mode: mode,
      reviewMessageID: parentID)
    composer = ""
    await submit(request)
  }

  /// A retry reuses the request ID, so the server never starts a second analysis.
  private func submit(_ request: NativeChatRequest) async {
    guard !sending else { return }
    var attempt = request
    attempt.failure = nil
    pending = attempt
    sending = true
    composerFocused = false
    let retry = request.failure != nil
    let result = await store.write {
      try await $0.chat(
        conversationId: request.conversationID, message: request.text, requestId: request.id,
        mode: request.mode, reviewMessageId: request.reviewMessageID)
    }
    sending = false
    guard let result else {
      let failure = store.lastFailure
      attempt.failure = failureText(failure)
      attempt.retryBlocked = AssistantPlan.retryBlocked(code: failure?.code)
      attempt.retryAt = failure?.retryAfterSeconds.map { Date().addingTimeInterval(Double($0)) }
      pending = attempt
      // Shown in the conversation instead of the page banner, as on the web.
      if !store.uncertainWrite { store.errorMessage = nil }
      return
    }
    selectedID = result.id
    updatedConversation = result
    pending = nil
    if request.mode == .ideaReview {
      discussionID =
        AssistantPlan.acceptedReview(
          result.messages, parent: request.reviewMessageID, standaloneRetry: retry)?.id
    } else {
      discussionID = nil
    }
  }

  private func failureText(_ failure: APIError?) -> String {
    switch AssistantPlan.failure(code: failure?.code, retryAfter: failure?.retryAfterSeconds) {
    case .discussionStale:
      return store.text(
        "Эта оценка уже обновилась или недоступна. Измените сообщение и выберите последнюю оценку идеи. Если её нет, обновите диалог.",
        "This review has changed or is unavailable. Edit the message and choose the latest review. If there is none, refresh the conversation.")
    case .scheduleChanged:
      return store.text(
        "Задача уже изменилась. Попросите Ritm составить новый план, чтобы использовать актуальное расписание.",
        "The task has changed. Ask Ritm for a new plan that uses the current schedule.")
    case .notConfigured:
      return store.text("Подключите OpenAI в настройках и повторите запрос.", "Connect OpenAI in Settings and try again.")
    case .ideaRateLimit:
      return store.text(
        "Достигнут лимит частоты разбора идей в Ritm. Повтор станет доступен после паузы.",
        "Ritm's idea review limit was reached. You can retry after a pause.")
    case .rateLimit:
      return store.text(
        "Достигнут лимит частоты запросов в Ritm. Повтор станет доступен после паузы.",
        "Ritm's request limit was reached. You can retry after a pause.")
    case .server:
      return failure?.message
        ?? store.errorMessage
        ?? store.text(
          "Не удалось выполнить действие. Проверьте соединение и попробуйте ещё раз.",
          "Could not complete the action. Check the connection and try again.")
    }
  }
}
