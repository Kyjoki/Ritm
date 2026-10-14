export type Theme = 'light' | 'dark' | 'system';
export type Language = 'ru' | 'en';
export type Priority = 'low' | 'normal' | 'high';
export type Repeat = 'none' | 'daily' | 'weekly' | 'monthly';
export type TaskKind = 'task' | 'event';

/** Finance amounts use integer hundredths for the four supported currencies. */
export type FinanceCurrency = 'KZT' | 'USD' | 'EUR' | 'RUB';
export type FinanceEntryInput =
  | {
      type: 'income';
      amountMinor: number;
      currency: FinanceCurrency;
      date: string;
      category: string;
      note: string;
    }
  | {
      type: 'expense';
      amountMinor: number;
      currency: FinanceCurrency;
      date: string;
      category: string;
      note: string;
    }
  | {
      type: 'deposit';
      name: string;
      valueMinor: number;
      currency: FinanceCurrency;
      asOf: string;
      note: string;
    }
  | {
      type: 'stock';
      name: string;
      valueMinor: number;
      currency: FinanceCurrency;
      asOf: string;
      note: string;
    };
export type FinanceEntry = FinanceEntryInput & {
  id: string;
  createdAt: string;
  updatedAt: string;
};

export interface TaskInput {
  title: string;
  description: string;
  date: string | null;
  time: string | null;
  duration: number;
  priority: Priority;
  repeat: Repeat;
  kind: TaskKind;
  completed: boolean;
  calendarEntry?: boolean;
  colorId?: string | null;
}
export interface Task extends TaskInput {
  id: string;
  completedDates: string[];
  createdAt: string;
  updatedAt: string;
}
export interface Settings {
  displayName: string;
  email: string;
  theme: Theme;
  sidebar: 'dark' | 'light';
  language: Language;
  timeZone: string;
  notifications: boolean;
  dailyBriefing: boolean;
  workDayStart: string;
  workDayEnd: string;
}
export interface ScheduleTime {
  date: string | null;
  time: string | null;
  duration: number;
}
export interface ScheduleProposal {
  id: string;
  taskId: string;
  title: string;
  before: ScheduleTime;
  after: ScheduleTime;
  reason: string;
  status: 'pending' | 'applied' | 'rejected' | 'undone';
  taskUpdatedAt: string;
}
export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  createdAt: string;
  proposals: ScheduleProposal[];
  steps: string[];
  ideaReview?: IdeaReviewReport;
}
export type ChatMode = 'assistant' | 'idea_review';
export type IdeaExpertId = 'value' | 'feasibility' | 'resources' | 'risks';
export type IdeaVerdict = 'promising' | 'needs_testing' | 'weak';
export interface IdeaExpertOpinion {
  verdict: IdeaVerdict;
  summary: string;
  strengths: string[];
  concerns: string[];
  assumptions: string[];
  firstTest: string;
}
export interface IdeaExpertReview extends IdeaExpertOpinion {
  id: IdeaExpertId;
}
export interface IdeaReviewSynthesis {
  verdict: IdeaVerdict;
  summary: string;
  agreements: string[];
  disagreements: string[];
  questions: string[];
  nextSteps: string[];
}
export interface IdeaReviewReport {
  version: 1;
  model: string;
  experts: IdeaExpertReview[];
  synthesis: IdeaReviewSynthesis;
  discussion?: {
    round: number;
    parentMessageId: string;
    rootMessageId: string;
    changes: string[];
    verdictChanges: { id: IdeaExpertId; before: IdeaVerdict; after: IdeaVerdict }[];
  };
}
export interface Conversation {
  id: string;
  title: string;
  messages: ChatMessage[];
  createdAt: string;
  updatedAt: string;
}
export interface AiStatus {
  configured: boolean;
  model: string;
  source: 'environment' | 'saved' | 'none';
}
export interface Bootstrap {
  tasks: Task[];
  settings: Settings;
  conversations: Conversation[];
  aiStatus: AiStatus;
}
export interface ProposalResult {
  tasks: Task[];
  conversation: Conversation;
}
export interface ApiErrorBody {
  error: string;
  code?: string;
  retryAfterSeconds?: number;
}

export interface GoogleCalendarStatus {
  configured: boolean;
  status: 'unconfigured' | 'disconnected' | 'connected' | 'reauth_required';
  mode: 'readwrite';
  calendarId: 'primary';
  lastFetchedAt: string | null;
  extendedColors?: boolean;
  tasksEnabled?: boolean;
}
export interface GoogleOAuthSetup {
  configured: boolean;
  source: 'environment' | 'saved' | 'none';
  clientId: string;
  hasClientSecret: boolean;
  redirectUri: string | null;
}
export interface GoogleOAuthSetupInput {
  clientId: string;
  clientSecret?: string;
}
export interface GoogleCalendarEvent {
  id: string;
  source: 'google';
  calendarId: 'primary';
  title: string;
  description: string;
  etag: string;
  start: { date?: string; dateTime?: string };
  end: { date?: string; dateTime?: string };
  timeZone: string;
  allDay: boolean;
  busy: boolean;
  readOnly: boolean;
  colorId?: string;
  recurring?: boolean;
  readOnlyReason?: string;
  taskLink?: boolean;
  taskUnavailableReason?: string;
  googleTask?: GoogleTaskCompletion;
}
export interface GoogleTaskCompletion {
  taskListId: string;
  id: string;
  etag: string;
  status: 'needsAction' | 'completed';
  completed?: string;
  connectionId: string;
}
export interface GoogleTasksStatus {
  status: 'enabled' | 'permission_required' | 'unavailable' | 'partial';
  message?: string;
}
export interface GoogleCalendarResult {
  events: GoogleCalendarEvent[];
  from: string;
  to: string;
  timeZone: string;
  fetchedAt: string;
  partial: boolean;
  tasks?: GoogleTasksStatus;
}
export interface GoogleEventInput {
  title: string;
  description: string;
  date: string;
  time: string | null;
  duration: number;
  allDay: boolean;
  colorId?: string | null;
  repeat?: Repeat;
}
export interface GoogleTransferResult {
  event: GoogleCalendarEvent;
  transferredTaskId: string;
}
