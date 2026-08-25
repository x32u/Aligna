-- Keep encrypted voice profiles in the unexposed private schema while allowing
-- authenticated Edge Functions to perform the narrowly-scoped operations they
-- need with the server-only service role.
begin;

create or replace function public.service_voice_profile_enroll(
  p_user_id uuid,
  p_encrypted_embedding text,
  p_encryption_nonce text,
  p_embedding_dimension integer,
  p_model_provider text,
  p_model_version text,
  p_package_version text,
  p_consented_at timestamptz,
  p_enrolled_at timestamptz,
  p_encryption_key_version integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.voice_profiles (
    user_id,
    encrypted_embedding,
    encryption_nonce,
    embedding_dimension,
    model_provider,
    model_version,
    package_version,
    enrollment_status,
    consented_at,
    enrolled_at,
    encryption_key_version
  )
  values (
    p_user_id,
    p_encrypted_embedding,
    p_encryption_nonce,
    p_embedding_dimension,
    p_model_provider,
    p_model_version,
    p_package_version,
    'enrolled',
    p_consented_at,
    p_enrolled_at,
    p_encryption_key_version
  )
  on conflict (user_id) do update set
    encrypted_embedding = excluded.encrypted_embedding,
    encryption_nonce = excluded.encryption_nonce,
    embedding_dimension = excluded.embedding_dimension,
    model_provider = excluded.model_provider,
    model_version = excluded.model_version,
    package_version = excluded.package_version,
    enrollment_status = 'enrolled',
    consented_at = excluded.consented_at,
    enrolled_at = excluded.enrolled_at,
    encryption_key_version = excluded.encryption_key_version;

  update public.profiles
  set voice_enrollment_status = 'enrolled'
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  insert into private.voice_profile_access_audit (
    requester_user_id,
    meeting_id,
    action,
    candidate_count
  )
  values (p_user_id, null, 'enroll', 0);
end;
$$;

create or replace function public.service_voice_enrollment_status_update(
  p_user_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in (
    'not_started',
    'in_progress',
    'enrolled',
    'skipped',
    'needs_reenrollment'
  ) then
    raise exception 'Invalid voice enrollment status'
      using errcode = '22023';
  end if;

  if p_status = 'enrolled'
     and not exists (
       select 1
       from private.voice_profiles
       where user_id = p_user_id
         and enrollment_status = 'enrolled'
     )
  then
    return false;
  end if;

  update public.profiles
  set voice_enrollment_status =
    p_status::public.voice_enrollment_status
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  insert into private.voice_profile_access_audit (
    requester_user_id,
    meeting_id,
    action,
    candidate_count
  )
  values (p_user_id, null, 'status:' || p_status, 0);

  return true;
end;
$$;

create or replace function public.service_voice_profile_delete(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.voice_profiles
  where user_id = p_user_id;

  update public.profiles
  set voice_enrollment_status = 'not_started'
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  insert into private.voice_profile_access_audit (
    requester_user_id,
    meeting_id,
    action,
    candidate_count
  )
  values (p_user_id, null, 'delete', 0);
end;
$$;

create or replace function public.service_voice_profiles_for_candidates(
  p_user_ids uuid[]
)
returns table (
  user_id uuid,
  encrypted_embedding text,
  encryption_nonce text,
  embedding_dimension integer,
  model_provider text,
  model_version text,
  package_version text,
  encryption_key_version integer
)
language sql
security definer
set search_path = ''
as $$
  select
    voice_profiles.user_id,
    voice_profiles.encrypted_embedding,
    voice_profiles.encryption_nonce,
    voice_profiles.embedding_dimension,
    voice_profiles.model_provider,
    voice_profiles.model_version,
    voice_profiles.package_version,
    voice_profiles.encryption_key_version
  from private.voice_profiles
  where voice_profiles.user_id = any(p_user_ids)
    and voice_profiles.enrollment_status = 'enrolled';
$$;

create or replace function public.service_voice_profiles_mark_reenrollment(
  p_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.voice_profiles
  set enrollment_status = 'needs_reenrollment'
  where user_id = any(p_user_ids);

  update public.profiles
  set voice_enrollment_status = 'needs_reenrollment'
  where id = any(p_user_ids);
end;
$$;

create or replace function public.service_voice_candidate_request_count(
  p_requester_user_id uuid,
  p_since timestamptz
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select count(*)
  from private.voice_profile_access_audit
  where requester_user_id = p_requester_user_id
    and action = 'candidates'
    and created_at >= p_since;
$$;

create or replace function public.service_voice_profile_audit(
  p_requester_user_id uuid,
  p_meeting_id uuid,
  p_action text,
  p_candidate_count integer
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.voice_profile_access_audit (
    requester_user_id,
    meeting_id,
    action,
    candidate_count
  )
  values (
    p_requester_user_id,
    p_meeting_id,
    p_action,
    p_candidate_count
  );
$$;

revoke all on function public.service_voice_profile_enroll(
  uuid, text, text, integer, text, text, text, timestamptz, timestamptz, integer
) from public, anon, authenticated;
grant execute on function public.service_voice_profile_enroll(
  uuid, text, text, integer, text, text, text, timestamptz, timestamptz, integer
) to service_role;

revoke all on function public.service_voice_enrollment_status_update(
  uuid, text
) from public, anon, authenticated;
grant execute on function public.service_voice_enrollment_status_update(
  uuid, text
) to service_role;

revoke all on function public.service_voice_profile_delete(uuid)
  from public, anon, authenticated;
grant execute on function public.service_voice_profile_delete(uuid)
  to service_role;

revoke all on function public.service_voice_profiles_for_candidates(uuid[])
  from public, anon, authenticated;
grant execute on function public.service_voice_profiles_for_candidates(uuid[])
  to service_role;

revoke all on function public.service_voice_profiles_mark_reenrollment(uuid[])
  from public, anon, authenticated;
grant execute on function public.service_voice_profiles_mark_reenrollment(uuid[])
  to service_role;

revoke all on function public.service_voice_candidate_request_count(
  uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.service_voice_candidate_request_count(
  uuid, timestamptz
) to service_role;

revoke all on function public.service_voice_profile_audit(
  uuid, uuid, text, integer
) from public, anon, authenticated;
grant execute on function public.service_voice_profile_audit(
  uuid, uuid, text, integer
) to service_role;

commit;
