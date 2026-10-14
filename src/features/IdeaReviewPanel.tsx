import { translate, useI18n } from '../lib/i18n';
import { ChevronDown, Lightbulb } from 'lucide-react';
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

function ReviewList({ title, items }: { title: string; items: string[] }) {
  if (!items.length) return null;
  return (
    <div className="idea-review-list">
      <h4>{title}</h4>
      <ul>
        {items.map((item, index) => (
          <li key={index}>{item}</li>
        ))}
      </ul>
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
    `${t('Общее мнение')} — ${t(verdictLabels[synthesis.verdict])}`,
    synthesis.summary,
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
    t(
      'Модель: {model}. Четыре отдельных запроса с разными ролями; каждый эксперт получает исходную идею без ответов остальных. Это оценка ИИ, без проверки фактов в интернете.',
      { model: report.model },
    ),
  ]
    .filter(Boolean)
    .join('\n\n');
}

export function IdeaReviewPanel({ report }: { report: IdeaReviewReport }) {
  const { t } = useI18n();
  const { synthesis } = report;
  return (
    <section className="idea-review" aria-label={t('Разбор идеи независимыми ИИ-экспертами')}>
      <div className="idea-review-synthesis">
        <div className="idea-review-title">
          <Lightbulb size={19} aria-hidden="true" />
          <h3>{t('Общее мнение')}</h3>
        </div>
        <span className={`idea-review-verdict idea-review-verdict--${synthesis.verdict}`}>
          {t(verdictLabels[synthesis.verdict])}
        </span>
        <p>{synthesis.summary}</p>
        <ReviewList title={t('В чём согласны')} items={synthesis.agreements} />
        <ReviewList title={t('Где мнения расходятся')} items={synthesis.disagreements} />
        <ReviewList title={t('Что нужно уточнить')} items={synthesis.questions} />
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
        {t(
          'Модель: {model}. Каждый эксперт получает исходную идею отдельным запросом, без ответов остальных. Общий вывод собирается после их оценок. Факты в интернете не проверяются.',
          { model: report.model },
        )}
      </p>
    </section>
  );
}
