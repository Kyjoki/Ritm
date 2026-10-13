export type Theme = 'light' | 'dark' | 'system';
export type Priority = 'low' | 'normal' | 'high';
export type Repeat = 'none' | 'daily' | 'weekly' | 'monthly';
export type TaskKind = 'task' | 'event';

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
  language: 'ru';
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
}

export interface GoogleCalendarStatus {
  configured: boolean;
  status: 'unconfigured' | 'disconnected' | 'connected' | 'reauth_required';
  mode: 'readwrite';
  calendarId: 'primary';
  lastFetchedAt: string | null;
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
}
export interface GoogleCalendarResult {
  events: GoogleCalendarEvent[];
  from: string;
  to: string;
  timeZone: string;
  fetchedAt: string;
  partial: boolean;
}
export interface GoogleEventInput {
  title: string;
  description: string;
  date: string;
  time: string | null;
  duration: number;
  allDay: boolean;
}
