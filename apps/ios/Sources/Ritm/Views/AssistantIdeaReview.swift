import RitmCore
import SwiftUI

/// `.a-idea`: the joint view first, then each expert behind a disclosure.
struct IdeaReviewView: View {
  let messageID: String
  let report: IdeaReviewReport
  let selected: Bool
  let disabled: Bool
  let superseded: Bool
  @Binding var openKeys: Set<String>
  let onDiscuss: (Bool) -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    let synthesis = report.synthesis
    let round = report.discussion?.round ?? 1
    return VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          RitmSymbol("lightbulb").font(.system(size: 16)).foregroundStyle(RitmTheme.accentColor)
          Text(store.text("Общее мнение", "Overall view")).ritmFont(14, weight: .bold).foregroundStyle(RitmTheme.text)
          Spacer(minLength: 0)
          Text(store.text("Оценка №\(round)", "Review #\(round)"))
            .ritmFont(10, weight: .semibold)
            .foregroundStyle(RitmTheme.accentColor)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(RitmTheme.soft, in: Capsule())
        }
        verdictChip(synthesis.verdict)
        Text(synthesis.summary).ritmFont(13, lineSpacing: 6.5).foregroundStyle(RitmTheme.text).textSelection(.enabled)
        if let discussion = report.discussion, round > 1 {
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
                  .ritmFont(11, lineSpacing: 2.5)
                  .foregroundStyle(RitmTheme.muted)
              }
            }
          }
        }
        list(store.text("В чём согласны", "Where they agree"), synthesis.agreements)
        list(store.text("Где мнения расходятся", "Where they disagree"), synthesis.disagreements)
        list(store.text("Что нужно уточнить", "What to clarify"), synthesis.questions, numbered: true)
        if !synthesis.questions.isEmpty && !superseded {
          Button { onDiscuss(true) } label: {
            Text(store.text("Ответить на вопросы", "Answer the questions"))
              .ritmFont(12, weight: .semibold)
              .foregroundStyle(RitmTheme.accentColor)
              .frame(minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(disabled)
          .opacity(disabled ? 0.5 : 1)
        }
        list(store.text("Следующие шаги", "Next steps"), synthesis.nextSteps)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .assistantBox(RitmTheme.panel, radius: 14)
      ForEach(report.experts) { expert in expertRow(expert) }
      Text(
        report.discussion != nil && round > 1
          ? store.text("Модель: \(report.model). Каждый эксперт учитывает исходную идею, ваши уточнения и только свои прежние оценки. Факты в интернете не проверяются.", "Model: \(report.model). Each expert considers the original idea, your clarifications and only their own earlier assessments. Facts are not checked on the internet.")
          : store.text("Модель: \(report.model). Каждый эксперт получает исходную идею отдельным запросом, без ответов остальных. Факты в интернете не проверяются.", "Model: \(report.model). Each expert gets the original idea in a separate request, without the others' answers. Facts are not checked on the internet.")
      )
      .ritmFont(10, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      Button {
        onDiscuss(false)
      } label: {
        AssistantButtonLabel(
          title: selected ? store.text("Обсуждение выбрано", "Discussion selected") : store.text("Обсудить с экспертами", "Discuss with the experts"),
          symbol: "bubble.left")
      }
      .buttonStyle(AssistantButtonStyle())
      .disabled(disabled || superseded)
      .accessibilityAddTraits(selected ? .isSelected : [])
      if superseded {
        Text(store.text("Есть более новая оценка этой идеи — продолжите обсуждение под ней.", "There is a newer review of this idea — continue the discussion under it."))
          .ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted)
      } else if round >= AssistantPlan.discussionRounds {
        Text(store.text("Достигнуто 8 оценок этой идеи. Начните новый разбор с её обновлённым описанием.", "This idea has reached 8 reviews. Start a new review with its updated description."))
          .ritmFont(10, lineSpacing: 3).foregroundStyle(RitmTheme.muted)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.text("Разбор идеи независимыми ИИ-экспертами", "Idea review by independent AI experts"))
  }

  /// `details.a-exp`: the role and its verdict, the reasoning below when open.
  private func expertRow(_ expert: IdeaExpertReview) -> some View {
    let key = messageID + expert.id.rawValue
    let open = Binding(
      get: { openKeys.contains(key) },
      set: { value in
        if value { openKeys.insert(key) } else { openKeys.remove(key) }
      })
    return AssistantDisclosure(isOpen: open) {
      Text(IdeaText.role(expert.id, store: store)).ritmFont(12, weight: .bold).foregroundStyle(RitmTheme.text)
      Text(IdeaText.verdict(expert.verdict, store: store)).ritmFont(11).foregroundStyle(RitmTheme.muted)
    } content: {
      VStack(alignment: .leading, spacing: 10) {
        Text(expert.summary).ritmFont(12, lineSpacing: 4).foregroundStyle(RitmTheme.text)
        list(store.text("Сильные стороны", "Strengths"), expert.strengths)
        list(store.text("Сомнения", "Concerns"), expert.concerns)
        list(store.text("Предположения", "Assumptions"), expert.assumptions)
        VStack(alignment: .leading, spacing: 4) {
          Text(store.text("Первая проверка", "First test")).ritmFont(11, weight: .semibold).foregroundStyle(RitmTheme.text)
          Text(expert.firstTest).ritmFont(11, lineSpacing: 2.5).foregroundStyle(RitmTheme.muted)
        }
      }
      .padding(.top, 2)
      .padding(.bottom, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .assistantBox(RitmTheme.field, radius: 12)
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
            .ritmFont(12, lineSpacing: 3)
            .foregroundStyle(RitmTheme.muted)
        }
      }
    }
  }
}
