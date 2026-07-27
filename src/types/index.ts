export type ProjectStatus = 'on-track' | 'at-risk' | 'completed';
export type TaskStatus = 'todo' | 'in-progress' | 'blocked' | 'done';
export type SuggestionStatus = 'pending' | 'approved' | 'dismissed' | 'editing';

export interface Person {
  id: string;
  name: string;
  initials: string;
  role: string;
  color: string;
}

export interface Project {
  id: string;
  name: string;
  description: string;
  status: ProjectStatus;
  progress: number;
  dueDate: string;
  members: Person[];
  openTasks: number;
}

export interface Meeting {
  id: string;
  title: string;
  projectId: string;
  projectName: string;
  date: string;
  duration: string;
  attendees: Person[];
  summary: string;
}

export interface ActionItem {
  id: string;
  title: string;
  description: string;
  assignee: Person;
  deadline: string;
  confidence: number;
  status: SuggestionStatus;
}

export interface TimelineItem {
  id: string;
  title: string;
  owner: Person;
  startDay: number;
  durationDays: number;
  progress: number;
  status: TaskStatus;
  dependency?: string;
}
