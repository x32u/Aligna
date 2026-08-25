-- Durable, user-owned meeting processing for temporary AI audio uploads.
begin;

do $$
begin
  create type public.meeting_processing_status as enum (
    'queued',
    'uploading',
    'transcribing',
    'analyzing',
    'complete',
    'failed'
  );
exception
  when duplicate_object then null;
end
$$;

alter table public.meetings
  add column if not exists processing_status
    public.meeting_processing_status not null default 'queued',
  add column if not exists audio_chunks jsonb not null default '[]'::jsonb,
  add column if not exists generated_title text,
  add column if not exists summary text,
  add column if not exists key_points jsonb not null default '[]'::jsonb,
  add column if not exists decisions jsonb not null default '[]'::jsonb,
  add column if not exists action_items jsonb not null default '[]'::jsonb,
  add column if not exists open_questions jsonb not null default '[]'::jsonb,
  add column if not exists follow_ups jsonb not null default '[]'::jsonb,
  add column if not exists languages_detected text[] not null default '{}',
  add column if not exists full_transcript text,
  add column if not exists transcript_segments jsonb not null default '[]'::jsonb,
  add column if not exists detected_language text,
  add column if not exists processing_created_at timestamptz,
  add column if not exists processing_completed_at timestamptz;

alter table public.meetings
  add constraint meetings_audio_chunks_array
    check (jsonb_typeof(audio_chunks) = 'array'),
  add constraint meetings_key_points_array
    check (jsonb_typeof(key_points) = 'array'),
  add constraint meetings_decisions_array
    check (jsonb_typeof(decisions) = 'array'),
  add constraint meetings_action_items_array
    check (jsonb_typeof(action_items) = 'array'),
  add constraint meetings_open_questions_array
    check (jsonb_typeof(open_questions) = 'array'),
  add constraint meetings_follow_ups_array
    check (jsonb_typeof(follow_ups) = 'array');

create index if not exists meetings_processing_status_idx
  on public.meetings (organizer_id, processing_status, updated_at desc);

create or replace function private.protect_meeting_ai_results()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    if new.generated_title is distinct from old.generated_title
       or new.summary is distinct from old.summary
       or new.key_points is distinct from old.key_points
       or new.decisions is distinct from old.decisions
       or new.action_items is distinct from old.action_items
       or new.open_questions is distinct from old.open_questions
       or new.follow_ups is distinct from old.follow_ups
       or new.languages_detected is distinct from old.languages_detected
       or new.full_transcript is distinct from old.full_transcript
       or new.transcript_segments is distinct from old.transcript_segments
       or new.detected_language is distinct from old.detected_language
       or new.processing_created_at is distinct from old.processing_created_at
       or new.processing_completed_at
          is distinct from old.processing_completed_at
    then
      raise exception 'AI meeting results are server managed'
        using errcode = '42501';
    end if;

    if new.processing_status is distinct from old.processing_status
       and new.processing_status not in ('queued', 'uploading')
    then
      raise exception 'Processing completion is server managed'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.protect_meeting_ai_results()
  from public, anon, authenticated;

drop trigger if exists meetings_protect_ai_results on public.meetings;
create trigger meetings_protect_ai_results
before update on public.meetings
for each row execute function private.protect_meeting_ai_results();

create table if not exists public.meeting_processing_jobs (
  meeting_id uuid primary key
    references public.meetings(id) on delete cascade,
  owner_user_id uuid not null
    references public.profiles(id) on delete cascade,
  idempotency_key uuid not null,
  status public.meeting_processing_status not null default 'queued',
  attempt_count integer not null default 0,
  locked_at timestamptz,
  retry_after timestamptz,
  temporary_audio_delete_after timestamptz,
  last_user_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint meeting_processing_jobs_attempt_count
    check (attempt_count >= 0),
  constraint meeting_processing_jobs_user_message_length
    check (
      last_user_message is null
      or char_length(last_user_message) <= 240
    )
);

create unique index if not exists meeting_processing_jobs_idempotency_idx
  on public.meeting_processing_jobs (owner_user_id, idempotency_key);

create index if not exists meeting_processing_jobs_retry_idx
  on public.meeting_processing_jobs (status, retry_after)
  where status in ('queued', 'failed');

create or replace function public.claim_meeting_processing_job(
  p_meeting_id uuid,
  p_owner_user_id uuid,
  p_idempotency_key uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed boolean := false;
begin
  if not exists (
    select 1
    from public.meetings meeting
    where meeting.id = p_meeting_id
      and meeting.organizer_id = p_owner_user_id
  ) then
    return false;
  end if;

  insert into public.meeting_processing_jobs (
    meeting_id,
    owner_user_id,
    idempotency_key,
    status,
    attempt_count,
    locked_at
  )
  values (
    p_meeting_id,
    p_owner_user_id,
    p_idempotency_key,
    'uploading',
    1,
    now()
  )
  on conflict (meeting_id) do update
  set idempotency_key = excluded.idempotency_key,
      status = 'uploading',
      attempt_count =
        public.meeting_processing_jobs.attempt_count + 1,
      locked_at = now(),
      retry_after = null,
      last_user_message = null,
      completed_at = null
  where public.meeting_processing_jobs.status in ('queued', 'failed')
     or public.meeting_processing_jobs.locked_at
        < now() - interval '8 minutes'
  returning true into claimed;

  return coalesce(claimed, false);
end;
$$;

revoke all on function public.claim_meeting_processing_job(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated;
grant execute on function public.claim_meeting_processing_job(
  uuid,
  uuid,
  uuid
) to service_role;

drop trigger if exists meeting_processing_jobs_set_updated_at
  on public.meeting_processing_jobs;
create trigger meeting_processing_jobs_set_updated_at
before update on public.meeting_processing_jobs
for each row execute function private.set_updated_at();

create table if not exists private.meeting_processing_diagnostics (
  id bigint generated always as identity primary key,
  meeting_id uuid not null
    references public.meetings(id) on delete cascade,
  stage public.meeting_processing_status not null,
  provider text,
  model_version text,
  error_code text,
  error_detail text,
  created_at timestamptz not null default now()
);

revoke all on table private.meeting_processing_diagnostics
  from public, anon, authenticated;
revoke all on sequence private.meeting_processing_diagnostics_id_seq
  from public, anon, authenticated;

create or replace function public.log_meeting_processing_diagnostic(
  p_meeting_id uuid,
  p_stage public.meeting_processing_status,
  p_provider text,
  p_model_version text,
  p_error_code text,
  p_error_detail text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.meeting_processing_diagnostics (
    meeting_id,
    stage,
    provider,
    model_version,
    error_code,
    error_detail
  )
  values (
    p_meeting_id,
    p_stage,
    left(p_provider, 80),
    left(p_model_version, 160),
    left(p_error_code, 160),
    left(p_error_detail, 8000)
  );
$$;

revoke all on function public.log_meeting_processing_diagnostic(
  uuid,
  public.meeting_processing_status,
  text,
  text,
  text,
  text
) from public, anon, authenticated;
grant execute on function public.log_meeting_processing_diagnostic(
  uuid,
  public.meeting_processing_status,
  text,
  text,
  text,
  text
) to service_role;

alter table public.meeting_processing_jobs enable row level security;

drop policy if exists processing_jobs_select_owner
  on public.meeting_processing_jobs;
create policy processing_jobs_select_owner
on public.meeting_processing_jobs
for select
to authenticated
using (owner_user_id = (select auth.uid()));

revoke all on table public.meeting_processing_jobs
  from public, anon, authenticated;
grant select on table public.meeting_processing_jobs to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'meeting-processing-audio',
  'meeting-processing-audio',
  false,
  25165824,
  array['audio/mp4', 'audio/m4a', 'audio/x-m4a']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists meeting_audio_select_owner on storage.objects;
create policy meeting_audio_select_owner
on storage.objects
for select
to authenticated
using (
  bucket_id = 'meeting-processing-audio'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1
    from public.meetings meeting
    where meeting.organizer_id = (select auth.uid())
      and meeting.id::text = (storage.foldername(name))[2]
  )
);

drop policy if exists meeting_audio_insert_owner on storage.objects;
create policy meeting_audio_insert_owner
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'meeting-processing-audio'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1
    from public.meetings meeting
    where meeting.organizer_id = (select auth.uid())
      and meeting.id::text = (storage.foldername(name))[2]
  )
);

drop policy if exists meeting_audio_update_owner on storage.objects;
create policy meeting_audio_update_owner
on storage.objects
for update
to authenticated
using (
  bucket_id = 'meeting-processing-audio'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'meeting-processing-audio'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists meeting_audio_delete_owner on storage.objects;
create policy meeting_audio_delete_owner
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'meeting-processing-audio'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

-- Realtime clients receive only rows already permitted by meeting RLS.
do $$
begin
  alter publication supabase_realtime add table public.meetings;
exception
  when duplicate_object then null;
end
$$;

commit;
