import { translate, useI18n } from '../lib/i18n';
import { ArrowRight, ChevronDown, Lightbulb, MessageSquare } from 'lucide-react';
import type { IdeaExpertId, IdeaReviewReport, IdeaVerdict } from '../../shared/types';
import '../styles/idea-review.css';

export const ideaExpertRoles: Record<IdeaExpertId, { title: string; description: string }> = {
  value: { title: 'Польза', description: 'Кому нужна идея и какую проблему она решает' },
  feasibility: { title: 'Реализация', description: 'Что потребуется, чтобы идея заработала' },
  resources: { title: 'Ресурсы', description: 'Время, усилия и затраты' },
  risks: { title: 'Риски', description: 'Слабые места и возможные последствия' },
};

const verdictLabels: Record<IdeaVerdict, string> = {
  promising: 'Есть потенциал',
  needs_testing: 'Нужна проверка',
  weak: 'Слабая в текущем виде',
};

function ReviewList({
  title,
  items,
  numbered = false,
}: {
  title: string;
  items: string[];
  numbered?: boolean;
}) {
  if (!items.length) return null;
  const List = numbered ? 'ol' : 'ul';
  return (
    <div className="idea-review-list">
      <h4>{title}</h4>
      <List>
        {items.map((item, index) => (
          <li key={index}>{item}</li>
        ))}
      </List>
    </div>
  );
}

export function ideaReviewCopyText(
  report: IdeaReviewReport,
  t: ReturnType<typeof useI18n>['t'] = (source, values) => translate('ru', source, values),
): string {
  const list = (title: string, items: string[]) =>
    items.length ? `${title}\n${items.map((item) => `• ${item}`).join('\n')}` : '';
  const synthesis = report.synthesis;
  return [
    report.discussion ? t('Оценка №{round}', { round: report.discussion.round }) : '',
    `${t('Общее мнение')} — ${t(verdictLabels[synthesis.verdict])}`,
    synthesis.summary,
    report.discussion
      ? list(t('Что изменилось после ваших ответов'), report.discussion.changes)
      : '',
    ...(report.discussion?.verdictChanges ?? []).map((change) =>
      t('{expert}: {before} → {after}', {
        expert: t(ideaExpertRoles[change.id].title),
        before: t(verdictLabels[change.before]),
        after: t(verdictLabels[change.after]),
      }),
    ),
    list(t('В чём согласны'), synthesis.agreements),
    list(t('Где мнения расходятся'), synthesis.disagreements),
    list(t('Что нужно уточнить'), synthesis.questions),
    list(t('Следующие шаги'), synthesis.nextSteps),
    ...report.experts.map((expert) =>
      [
        `${t(ideaExpertRoles[expert.id].title)} — ${t(verdictLabels[expert.verdict])}`,
        expert.summary,
        list(t('Сильные стороны'), expert.strengths),
        list(t('Сомнения'), expert.concerns),
        list(t('Предположения'), expert.assumptions),
        `${t('Первая проверка')}\n${expert.firstTest}`,
      ]
        .filter(Boolean)
        .join('\n\n'),
    ),
    report.discussion
      ? t(
          'Модель: {model}. Каждый эксперт учитывает исходную идею, ваши уточнения и только свои прежние оценки. Общий вывод собирается после их ответов. Факты в интернете не проверяются.',
          { model: report.model },
        )
      : t(
          'Модель: {model}. Четыре отдельных запроса с разными ролями; каждый эксперт получает исходную идею без ответов остальных. Это оценка ИИ, без проверки фактов в интернете.',
          { model: report.model },
        ),
  ]
    .filter(Boolean)
    .join('\n\n');
}

export function IdeaReviewPanel({
  report,
  onDiscuss,
  discussionSelected = false,
  discussionDisabled = false,
  superseded = false,
}: {
  report: IdeaReviewReport;
  onDiscuss?: (showQuestions?: boolean) => void;
  discussionSelected?: boolean;
  discussionDisabled?: boolean;
  superseded?: boolean;
}) {
  const { t } = useI18n();
  const { synthesis } = report;
  return (
    <section className="idea-review" aria-label={t('Разбор идеи независимыми ИИ-экспертами')}>
      <div className="idea-review-synthesis">
        <div className="idea-review-title">
          <Lightbulb size={19} aria-hidden="true" />
          <h3>{t('Общее мнение')}</h3>
          {report.discussion ? (
            <span className="idea-review-round">
              {t('Оценка №{round}', { round: report.discussion.round })}
            </span>
          ) : null}
        </div>
        <span className={`idea-review-verdict idea-review-verdict--${synthesis.verdict}`}>
          {t(verdictLabels[synthesis.verdict])}
        </span>
        <p>{synthesis.summary}</p>
        {report.discussion ? (
          <div className="idea-review-revision">
            <ReviewList
              title={t('Что изменилось после ваших ответов')}
              items={report.discussion.changes}
            />
            {report.discussion.verdictChanges.length ? (
              <div className="idea-review-verdict-changes">
                <h4>{t('Пересмотренные оценки')}</h4>
                {report.discussion.verdictChanges.map((change) => (
                  <p key={change.id}>
                    <strong>{t(ideaExpertRoles[change.id].title)}</strong>
                    <span>
                      {t(verdictLabels[change.before])}
                      <ArrowRight size={13} aria-hidden="true" />
                      {t(verdictLabels[change.after])}
                    </span>
                  </p>
                ))}
              </div>
            ) : (
              <p className="idea-review-method">
                {t('Итоговые оценки экспертов остались прежними; аргументы обновлены выше.')}
              </p>
            )}
          </div>
        ) : null}
        <ReviewList title={t('В чём согласны')} items={synthesis.agreements} />
        <ReviewList title={t('Где мнения расходятся')} items={synthesis.disagreements} />
        <ReviewList title={t('Что нужно уточнить')} items={synthesis.questions} numbered />
        {onDiscuss && synthesis.questions.length && !superseded ? (
          <button
            type="button"
            className="idea-review-answer-questions"
            disabled={discussionDisabled}
            onClick={() => onDiscuss(true)}
          >
            {t('Ответить на вопросы')}
          </button>
        ) : null}
        <ReviewList title={t('Следующие шаги')} items={synthesis.nextSteps} />
      </div>
      <div className="idea-review-experts">
        {report.experts.map((expert) => (
          <details className="idea-review-expert" key={expert.id}>
            <summary>
              <span className="idea-review-expert-heading">
                <strong>{t(ideaExpertRoles[expert.id].title)}</strong>
                <span>{t(verdictLabels[expert.verdict])}</span>
              </span>
              <ChevronDown size={17} aria-hidden="true" />
            </summary>
            <div className="idea-review-expert-body">
              <p>{expert.summary}</p>
              <ReviewList title={t('Сильные стороны')} items={expert.strengths} />
              <ReviewList title={t('Сомнения')} items={expert.concerns} />
              <ReviewList title={t('Предположения')} items={expert.assumptions} />
              <div className="idea-review-first-test">
                <h4>{t('Первая проверка')}</h4>
                <p>{expert.firstTest}</p>
              </div>
            </div>
          </details>
        ))}
      </div>
      <p className="idea-review-method">
        {report.discussion
          ? t(
              'Модель: {model}. Каждый эксперт учитывает исходную идею, ваши уточнения и только свои прежние оценки. Общий вывод собирается после их ответов. Факты в интернете не проверяются.',
              { model: report.model },
            )
          : t(
              'Модель: {model}. Каждый эксперт получает исходную идею отдельным запросом, без ответов остальных. Общий вывод собирается после их оценок. Факты в интернете не проверяются.',
              { model: report.model },
            )}
      </p>
      {onDiscuss ? (
        <div className="idea-review-discussion-actions">
          <button
            type="button"
            className="button button-secondary"
            disabled={discussionDisabled || superseded}
            onClick={() => onDiscuss()}
            aria-pressed={discussionSelected}
          >
            <MessageSquare size={15} aria-hidden="true" />
            {discussionSelected ? t('Обсуждение выбрано') : t('Обсудить с экспертами')}
          </button>
          {superseded ? (
            <p>{t('Есть более новая оценка этой идеи — продолжите обсуждение под ней.')}</p>
          ) : (report.discussion?.round ?? 1) >= 8 ? (
            <p>
              {t('Достигнуто 8 оценок этой идеи. Начните новый разбор с её обновлённым описанием.')}
            </p>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
