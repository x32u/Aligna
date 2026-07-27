import type {
  ActionItem,
  Meeting,
  Person,
  Project,
  TimelineItem,
} from '@/types';

export const people: Record<string, Person> = {
  maya: {
    id: 'maya',
    name: 'Maya Chen',
    initials: 'MC',
    role: 'Product Manager',
    color: '#5B5BEF',
  },
  leo: {
    id: 'leo',
    name: 'Leo Ramos',
    initials: 'LR',
    role: 'Mobile Engineer',
    color: '#178F5B',
  },
  sam: {
    id: 'sam',
    name: 'Sam Patel',
    initials: 'SP',
    role: 'Product Designer',
    color: '#D97706',
  },
  nina: {
    id: 'nina',
    name: 'Nina Brooks',
    initials: 'NB',
    role: 'QA Lead',
    color: '#D6455D',
  },
};

export const projects: Project[] = [
  {
    id: 'aligna-launch',
    name: 'Aligna Mobile Launch',
    description: 'Ship the first trusted meeting-to-project workflow for product teams.',
    status: 'on-track',
    progress: 0.64,
    dueDate: '2026-08-28',
    members: [people.maya, people.leo, people.sam, people.nina],
    openTasks: 12,
  },
  {
    id: 'client-portal',
    name: 'Northstar Client Portal',
    description: 'Unify client approvals, reports, and delivery status.',
    status: 'at-risk',
    progress: 0.42,
    dueDate: '2026-09-12',
    members: [people.maya, people.sam, people.leo],
    openTasks: 19,
  },
];

export const meetings: Meeting[] = [
  {
    id: 'weekly-product-sync',
    title: 'Weekly Product Sync',
    projectId: 'aligna-launch',
    projectName: 'Aligna Mobile Launch',
    date: '2026-07-27',
    duration: '42 min',
    attendees: [people.maya, people.leo, people.sam, people.nina],
    summary:
      'The team aligned on the manager approval workflow, moved the internal beta to August 14, and agreed to validate offline recording recovery before expanding AI extraction.',
  },
  {
    id: 'design-review',
    title: 'Mobile Design Review',
    projectId: 'aligna-launch',
    projectName: 'Aligna Mobile Launch',
    date: '2026-07-24',
    duration: '31 min',
    attendees: [people.maya, people.sam, people.leo],
    summary:
      'The team selected the compact dashboard direction and defined accessibility requirements for task approval controls.',
  },
];

export const actionItems: ActionItem[] = [
  {
    id: 'action-1',
    title: 'Prototype the approval queue',
    description: 'Create the manager review states for approve, edit, and dismiss.',
    assignee: people.sam,
    deadline: '2026-08-01',
    confidence: 0.96,
    status: 'pending',
  },
  {
    id: 'action-2',
    title: 'Validate offline recording recovery',
    description: 'Test interrupted uploads and retain the local audio file until confirmed.',
    assignee: people.leo,
    deadline: '2026-08-04',
    confidence: 0.91,
    status: 'pending',
  },
  {
    id: 'action-3',
    title: 'Prepare internal beta checklist',
    description: 'Document QA owners, supported devices, and release acceptance criteria.',
    assignee: people.nina,
    deadline: '2026-08-07',
    confidence: 0.87,
    status: 'pending',
  },
];

export const timelineItems: TimelineItem[] = [
  {
    id: 'timeline-1',
    title: 'Design system',
    owner: people.sam,
    startDay: 0,
    durationDays: 3,
    progress: 1,
    status: 'done',
  },
  {
    id: 'timeline-2',
    title: 'Auth & projects',
    owner: people.leo,
    startDay: 2,
    durationDays: 4,
    progress: 0.7,
    status: 'in-progress',
    dependency: 'Design system',
  },
  {
    id: 'timeline-3',
    title: 'Meeting capture',
    owner: people.leo,
    startDay: 5,
    durationDays: 4,
    progress: 0.35,
    status: 'in-progress',
    dependency: 'Auth & projects',
  },
  {
    id: 'timeline-4',
    title: 'AI review flow',
    owner: people.maya,
    startDay: 8,
    durationDays: 4,
    progress: 0.15,
    status: 'todo',
    dependency: 'Meeting capture',
  },
  {
    id: 'timeline-5',
    title: 'Internal beta',
    owner: people.nina,
    startDay: 11,
    durationDays: 2,
    progress: 0,
    status: 'blocked',
    dependency: 'AI review flow',
  },
];
