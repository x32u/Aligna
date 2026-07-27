import type { Project, TimelineItem } from '@/types';

export interface ProjectService {
  listProjects(): Promise<Project[]>;
  getTimeline(projectId: string): Promise<TimelineItem[]>;
}

// PostgreSQL queries will be introduced after the schema and RLS policies are approved.
