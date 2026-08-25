-- Cover speaker-profile foreign keys reported by the database advisor.
begin;

create index if not exists meeting_transcript_turns_speaker_user_idx
  on public.meeting_transcript_turns (speaker_user_id)
  where speaker_user_id is not null;

create index if not exists meeting_transcript_turns_original_speaker_user_idx
  on public.meeting_transcript_turns (original_speaker_user_id)
  where original_speaker_user_id is not null;

commit;
