-- Optional, consented voice recognition and speaker-attributed transcripts.
-- Raw enrollment audio never reaches Supabase.
begin;

do $$
begin
  create type public.voice_enrollment_status as enum (
    'not_started',
    'in_progress',
    'enrolled',
    'skipped',
    'needs_reenrollment'
  );
exception
  when duplicate_object then null;
end
$$;

alter table public.profiles
  add column if not exists voice_enrollment_status
    public.voice_enrollment_status not null default 'not_started';

create or replace function private.protect_voice_enrollment_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role'
     and new.voice_enrollment_status
       is distinct from old.voice_enrollment_status
  then
    raise exception 'Voice enrollment status is server managed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.protect_voice_enrollment_status()
  from public, anon, authenticated;

drop trigger if exists profiles_protect_voice_enrollment_status
  on public.profiles;
create trigger profiles_protect_voice_enrollment_status
before update on public.profiles
for each row execute function private.protect_voice_enrollment_status();

create table if not exists private.voice_profiles (
  user_id uuid primary key
    references public.profiles(id) on delete cascade,
  encrypted_embedding text not null,
  encryption_nonce text not null,
  embedding_dimension integer not null,
  model_provider text not null,
  model_version text not null,
  package_version text not null,
  enrollment_status public.voice_enrollment_status not null
    default 'enrolled',
  consented_at timestamptz not null,
  enrolled_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  encryption_key_version integer not null default 1,
  constraint voice_profiles_dimension
    check (embedding_dimension between 64 and 2048),
  constraint voice_profiles_ciphertext_length
    check (char_length(encrypted_embedding) between 32 and 100000),
  constraint voice_profiles_nonce_length
    check (char_length(encryption_nonce) between 12 and 256),
  constraint voice_profiles_model_metadata
    check (
      char_length(model_provider) between 1 and 80
      and char_length(model_version) between 1 and 160
      and char_length(package_version) between 1 and 80
    )
);

alter table private.voice_profiles enable row level security;
revoke all on table private.voice_profiles
  from public, anon, authenticated;

drop trigger if exists voice_profiles_set_updated_at
  on private.voice_profiles;
create trigger voice_profiles_set_updated_at
before update on private.voice_profiles
for each row execute function private.set_updated_at();

create table if not exists private.voice_profile_access_audit (
  id bigint generated always as identity primary key,
  requester_user_id uuid not null,
  meeting_id uuid,
  action text not null,
  candidate_count integer not null default 0,
  created_at timestamptz not null default now(),
  constraint voice_profile_audit_action_length
    check (char_length(action) between 1 and 80),
  constraint voice_profile_audit_candidate_count
    check (candidate_count between 0 and 32)
);

alter table private.voice_profile_access_audit enable row level security;
revoke all on table private.voice_profile_access_audit
  from public, anon, authenticated;
revoke all on sequence private.voice_profile_access_audit_id_seq
  from public, anon, authenticated;

create index if not exists voice_profile_access_rate_limit_idx
  on private.voice_profile_access_audit (
    requester_user_id,
    created_at desc
  );

do $$
begin
  alter type public.meeting_processing_status
    add value if not exists 'preparing_speakers';
  alter type public.meeting_processing_status
    add value if not exists 'diarizing';
  alter type public.meeting_processing_status
    add value if not exists 'matching_speakers';
  alter type public.meeting_processing_status
    add value if not exists 'merging_transcript';
exception
  when duplicate_object then null;
end
$$;

alter table public.meetings
  add column if not exists transcript_words
    jsonb not null default '[]'::jsonb,
  add column if not exists diarization_timeline
    jsonb not null default '[]'::jsonb,
  add column if not exists speaker_processing_skipped
    boolean not null default false,
  add column if not exists speaker_processing_status
    text not null default 'preparing_speakers',
  add column if not exists voice_model_version text;

alter table public.meetings
  add constraint meetings_transcript_words_array
    check (jsonb_typeof(transcript_words) = 'array'),
  add constraint meetings_diarization_timeline_array
    check (jsonb_typeof(diarization_timeline) = 'array'),
  add constraint meetings_speaker_processing_status
    check (
      speaker_processing_status in (
        'preparing_speakers',
        'diarizing',
        'matching_speakers',
        'merging_transcript',
        'complete',
        'skipped',
        'failed'
      )
    );

create table if not exists public.meeting_transcript_turns (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null
    references public.meetings(id) on delete cascade,
  stable_speaker_key text not null,
  speaker_user_id uuid
    references public.profiles(id) on delete set null,
  speaker_display_name text not null,
  start_seconds double precision not null,
  end_seconds double precision not null,
  text text not null,
  attribution_confidence real,
  attribution_source text not null,
  original_speaker_user_id uuid
    references public.profiles(id) on delete set null,
  original_speaker_display_name text not null,
  original_attribution_confidence real,
  original_attribution_source text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint meeting_transcript_turns_key_length
    check (char_length(stable_speaker_key) between 1 and 80),
  constraint meeting_transcript_turns_name_length
    check (char_length(speaker_display_name) between 1 and 120),
  constraint meeting_transcript_turns_original_name_length
    check (char_length(original_speaker_display_name) between 1 and 120),
  constraint meeting_transcript_turns_time_order
    check (
      start_seconds >= 0
      and end_seconds >= start_seconds
    ),
  constraint meeting_transcript_turns_text_length
    check (char_length(text) between 1 and 20000),
  constraint meeting_transcript_turns_confidence
    check (
      attribution_confidence is null
      or attribution_confidence between -1 and 1
    )
);

create index if not exists meeting_transcript_turns_timeline_idx
  on public.meeting_transcript_turns (
    meeting_id,
    start_seconds,
    id
  );

create index if not exists meeting_transcript_turns_speaker_idx
  on public.meeting_transcript_turns (
    meeting_id,
    stable_speaker_key
  );

drop trigger if exists meeting_transcript_turns_set_updated_at
  on public.meeting_transcript_turns;
create trigger meeting_transcript_turns_set_updated_at
before update on public.meeting_transcript_turns
for each row execute function private.set_updated_at();

alter table public.meeting_transcript_turns enable row level security;
revoke all on table public.meeting_transcript_turns
  from public, anon, authenticated;
grant select on table public.meeting_transcript_turns to authenticated;

drop policy if exists meeting_transcript_turns_select
  on public.meeting_transcript_turns;
create policy meeting_transcript_turns_select
on public.meeting_transcript_turns
for select
to authenticated
using (private.can_access_meeting(meeting_id));

create or replace function public.correct_meeting_speaker(
  p_meeting_id uuid,
  p_stable_speaker_key text,
  p_speaker_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_name text;
begin
  if not private.can_access_meeting(p_meeting_id) then
    raise exception 'Meeting access denied' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.meetings meeting
    where meeting.id = p_meeting_id
      and (
        meeting.organizer_id = p_speaker_user_id
        or exists (
          select 1
          from public.meeting_participants participant
          where participant.meeting_id = meeting.id
            and participant.user_id = p_speaker_user_id
        )
      )
  ) then
    raise exception 'Speaker is not a meeting participant'
      using errcode = '42501';
  end if;

  select profile.display_name
  into selected_name
  from public.profiles profile
  where profile.id = p_speaker_user_id;

  update public.meeting_transcript_turns
  set speaker_user_id = p_speaker_user_id,
      speaker_display_name = selected_name,
      attribution_confidence = null,
      attribution_source = 'manual_correction'
  where meeting_id = p_meeting_id
    and stable_speaker_key = p_stable_speaker_key;
end;
$$;

revoke all on function public.correct_meeting_speaker(
  uuid,
  text,
  uuid
) from public, anon;
grant execute on function public.correct_meeting_speaker(
  uuid,
  text,
  uuid
) to authenticated;

create or replace function private.protect_speaker_processing_results()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role'
     and (
       new.transcript_words is distinct from old.transcript_words
       or new.diarization_timeline
          is distinct from old.diarization_timeline
       or new.speaker_processing_skipped
          is distinct from old.speaker_processing_skipped
       or new.speaker_processing_status
          is distinct from old.speaker_processing_status
       or new.voice_model_version
          is distinct from old.voice_model_version
     )
  then
    raise exception 'Speaker processing results are server managed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.protect_speaker_processing_results()
  from public, anon, authenticated;

drop trigger if exists meetings_protect_speaker_processing_results
  on public.meetings;
create trigger meetings_protect_speaker_processing_results
before update on public.meetings
for each row execute function
  private.protect_speaker_processing_results();

commit;
