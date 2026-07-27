import type { ActionItem, Meeting } from '@/types';

export interface MeetingAnalysis {
  meeting: Meeting;
  transcript: string;
  suggestions: ActionItem[];
}

export interface MeetingAIService {
  analyzeMeeting(meetingId: string): Promise<MeetingAnalysis>;
}

// Gemini transcription and extraction will be implemented in a later milestone.
