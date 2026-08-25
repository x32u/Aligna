-- Foundational identity and collaboration schema.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

do $$
begin
  create type public.workspace_role as enum ('owner', 'admin', 'member');
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.invitation_status as enum (
    'pending',
    'accepted',
    'declined',
    'cancelled'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.meeting_status as enum (
    'scheduled',
    'recording',
    'completed',
    'cancelled'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.meeting_participant_role as enum (
    'organizer',
    'participant'
  );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.participant_response_status as enum (
    'invited',
    'accepted',
    'declined'
  );
exception
  when duplicate_object then null;
end
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  handle text,
  avatar_path text,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length
    check (char_length(display_name) between 0 and 80),
  constraint profiles_handle_format
    check (
      handle is null
      or (
        handle = lower(handle)
        and handle ~ '^[a-z0-9][a-z0-9_]{2,29}$'
      )
    ),
  constraint profiles_avatar_path_owner
    check (
      avatar_path is null
      or avatar_path = id::text || '/profile.jpg'
    )
);

create unique index profiles_handle_unique_ci
  on public.profiles (lower(handle))
  where handle is not null;

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workspaces_name_length
    check (char_length(btrim(name)) between 2 and 80)
);

create table public.workspace_members (
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  role public.workspace_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create index workspace_members_user_id_idx
  on public.workspace_members (user_id, joined_at desc);

create table public.workspace_invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  invitee_id uuid not null
    references public.profiles(id) on delete cascade,
  invited_by uuid not null
    references public.profiles(id) on delete cascade,
  status public.invitation_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint workspace_invitations_not_self
    check (invitee_id <> invited_by),
  constraint workspace_invitations_response_time
    check (
      (status = 'pending' and responded_at is null)
      or (status <> 'pending' and responded_at is not null)
    )
);

create unique index workspace_invitations_one_pending_idx
  on public.workspace_invitations (workspace_id, invitee_id)
  where status = 'pending';

create index workspace_invitations_invitee_idx
  on public.workspace_invitations (invitee_id, status, created_at desc);

create table public.meetings (
  id uuid primary key,
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  organizer_id uuid not null
    references public.profiles(id) on delete cascade,
  title text not null,
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  status public.meeting_status not null default 'scheduled',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint meetings_title_length
    check (char_length(btrim(title)) between 1 and 160),
  constraint meetings_time_order
    check (
      (started_at is null or ended_at is null)
      or ended_at >= started_at
    )
);

create index meetings_workspace_time_idx
  on public.meetings (
    workspace_id,
    coalesce(started_at, scheduled_at, created_at) desc
  );

create index meetings_organizer_idx
  on public.meetings (organizer_id, created_at desc);

create table public.meeting_participants (
  meeting_id uuid not null
    references public.meetings(id) on delete cascade,
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  role public.meeting_participant_role not null default 'participant',
  response_status public.participant_response_status not null default 'invited',
  invited_by uuid
    references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (meeting_id, user_id)
);

create index meeting_participants_user_idx
  on public.meeting_participants (user_id, response_status, created_at desc);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger workspaces_set_updated_at
before update on public.workspaces
for each row execute function private.set_updated_at();

create trigger meetings_set_updated_at
before update on public.meetings
for each row execute function private.set_updated_at();

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_handle text;
  requested_name text;
begin
  requested_handle := lower(
    btrim(coalesce(new.raw_user_meta_data ->> 'handle', ''))
  );
  requested_name := btrim(
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  );

  if requested_handle !~ '^[a-z0-9][a-z0-9_]{2,29}$'
     or exists (
       select 1
       from public.profiles
       where lower(handle) = requested_handle
     )
  then
    requested_handle := null;
  end if;

  insert into public.profiles (id, display_name, handle)
  values (new.id, left(requested_name, 80), requested_handle)
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function private.handle_new_auth_user()
  from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create or replace function private.is_workspace_member(
  p_workspace_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_members
    where workspace_id = p_workspace_id
      and user_id = auth.uid()
  );
$$;

create or replace function private.has_workspace_role(
  p_workspace_id uuid,
  p_roles public.workspace_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_members
    where workspace_id = p_workspace_id
      and user_id = auth.uid()
      and role = any(p_roles)
  );
$$;

create or replace function private.shares_workspace(
  p_other_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_other_user_id = auth.uid()
    or exists (
      select 1
      from public.workspace_members mine
      join public.workspace_members theirs
        on theirs.workspace_id = mine.workspace_id
      where mine.user_id = auth.uid()
        and theirs.user_id = p_other_user_id
    );
$$;

create or replace function private.can_access_meeting(
  p_meeting_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.meetings m
    where m.id = p_meeting_id
      and (
        exists (
          select 1
          from public.workspace_members wm
          where wm.workspace_id = m.workspace_id
            and wm.user_id = auth.uid()
        )
        or exists (
          select 1
          from public.meeting_participants mp
          where mp.meeting_id = m.id
            and mp.user_id = auth.uid()
        )
      )
  );
$$;

revoke all on function private.is_workspace_member(uuid)
  from public, anon, authenticated;
revoke all on function private.has_workspace_role(uuid, public.workspace_role[])
  from public, anon, authenticated;
revoke all on function private.shares_workspace(uuid)
  from public, anon, authenticated;
revoke all on function private.can_access_meeting(uuid)
  from public, anon, authenticated;

grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.has_workspace_role(
  uuid,
  public.workspace_role[]
) to authenticated;
grant execute on function private.shares_workspace(uuid) to authenticated;
grant execute on function private.can_access_meeting(uuid) to authenticated;

create or replace function public.find_profile_by_handle(
  p_handle text
)
returns table (
  id uuid,
  handle text,
  display_name text,
  avatar_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.handle, p.display_name, p.avatar_path
  from public.profiles p
  where p.handle = lower(trim(leading '@' from btrim(p_handle)))
  limit 1;
$$;

create or replace function public.create_workspace(
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_workspace_id uuid;
  clean_name text := btrim(p_name);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(clean_name) not between 2 and 80 then
    raise exception 'Workspace name must contain 2 to 80 characters'
      using errcode = '22023';
  end if;

  insert into public.workspaces (name, created_by)
  values (clean_name, auth.uid())
  returning id into new_workspace_id;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (new_workspace_id, auth.uid(), 'owner');

  return new_workspace_id;
end;
$$;

create or replace function public.invite_workspace_member(
  p_workspace_id uuid,
  p_invitee_id uuid
)
returns public.workspace_invitations
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_invitation public.workspace_invitations;
begin
  if not private.has_workspace_role(
    p_workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  ) then
    raise exception 'Insufficient workspace permission'
      using errcode = '42501';
  end if;

  if p_invitee_id = auth.uid() then
    raise exception 'You cannot invite yourself' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_invitee_id
  ) then
    raise exception 'Account not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.workspace_members
    where workspace_id = p_workspace_id
      and user_id = p_invitee_id
  ) then
    raise exception 'This account is already a workspace member'
      using errcode = '23505';
  end if;

  insert into public.workspace_invitations (
    workspace_id,
    invitee_id,
    invited_by
  )
  values (p_workspace_id, p_invitee_id, auth.uid())
  returning * into created_invitation;

  return created_invitation;
end;
$$;

create or replace function public.respond_to_workspace_invitation(
  p_invitation_id uuid,
  p_accept boolean
)
returns public.invitation_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.workspace_invitations;
  next_status public.invitation_status;
begin
  select *
  into invitation
  from public.workspace_invitations
  where id = p_invitation_id
  for update;

  if invitation.id is null then
    raise exception 'Invitation not found' using errcode = 'P0002';
  end if;

  if invitation.invitee_id <> auth.uid() then
    raise exception 'Only the invitee can respond' using errcode = '42501';
  end if;

  if invitation.status <> 'pending' then
    raise exception 'Invitation has already been resolved'
      using errcode = '22023';
  end if;

  next_status := case when p_accept then 'accepted' else 'declined' end;

  update public.workspace_invitations
  set status = next_status,
      responded_at = now()
  where id = p_invitation_id;

  if p_accept then
    insert into public.workspace_members (workspace_id, user_id, role)
    values (invitation.workspace_id, auth.uid(), 'member')
    on conflict (workspace_id, user_id) do nothing;
  end if;

  return next_status;
end;
$$;

create or replace function public.cancel_workspace_invitation(
  p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_workspace_id uuid;
begin
  select workspace_id
  into target_workspace_id
  from public.workspace_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if target_workspace_id is null then
    raise exception 'Pending invitation not found' using errcode = 'P0002';
  end if;

  if not private.has_workspace_role(
    target_workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  ) then
    raise exception 'Insufficient workspace permission'
      using errcode = '42501';
  end if;

  update public.workspace_invitations
  set status = 'cancelled',
      responded_at = now()
  where id = p_invitation_id;
end;
$$;

create or replace function private.protect_workspace_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_count integer;
begin
  if not exists (
    select 1
    from public.workspaces
    where id = old.workspace_id
  ) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE'
     and old.user_id = auth.uid()
     and old.role <> new.role
  then
    raise exception 'Members cannot change their own role'
      using errcode = '42501';
  end if;

  if (tg_op = 'DELETE' and old.role = 'owner')
     or (
       tg_op = 'UPDATE'
       and old.role = 'owner'
       and new.role <> 'owner'
     )
  then
    select count(*)
    into owner_count
    from public.workspace_members
    where workspace_id = old.workspace_id
      and role = 'owner';

    if owner_count <= 1 then
      raise exception 'A workspace must keep at least one owner'
        using errcode = '23514';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.protect_workspace_members()
  from public, anon, authenticated;

create trigger workspace_members_protection
before update or delete on public.workspace_members
for each row execute function private.protect_workspace_members();

create or replace function public.set_workspace_member_role(
  p_workspace_id uuid,
  p_user_id uuid,
  p_role public.workspace_role
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.workspace_role;
  target_role public.workspace_role;
begin
  select role into actor_role
  from public.workspace_members
  where workspace_id = p_workspace_id
    and user_id = auth.uid();

  select role into target_role
  from public.workspace_members
  where workspace_id = p_workspace_id
    and user_id = p_user_id;

  if actor_role not in ('owner', 'admin') then
    raise exception 'Insufficient workspace permission'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'You cannot change your own role'
      using errcode = '42501';
  end if;

  if target_role is null then
    raise exception 'Workspace member not found' using errcode = 'P0002';
  end if;

  if actor_role = 'admin'
     and (target_role = 'owner' or p_role = 'owner')
  then
    raise exception 'Only an owner can manage owners'
      using errcode = '42501';
  end if;

  update public.workspace_members
  set role = p_role
  where workspace_id = p_workspace_id
    and user_id = p_user_id;
end;
$$;

create or replace function public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role public.workspace_role;
  target_role public.workspace_role;
begin
  select role into actor_role
  from public.workspace_members
  where workspace_id = p_workspace_id
    and user_id = auth.uid();

  select role into target_role
  from public.workspace_members
  where workspace_id = p_workspace_id
    and user_id = p_user_id;

  if target_role is null then
    raise exception 'Workspace member not found' using errcode = 'P0002';
  end if;

  if p_user_id <> auth.uid() and actor_role not in ('owner', 'admin') then
    raise exception 'Insufficient workspace permission'
      using errcode = '42501';
  end if;

  if actor_role = 'admin' and target_role = 'owner' then
    raise exception 'Admins cannot remove owners' using errcode = '42501';
  end if;

  delete from public.workspace_members
  where workspace_id = p_workspace_id
    and user_id = p_user_id;
end;
$$;

create or replace function private.protect_meeting_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.id <> new.id
     or old.workspace_id <> new.workspace_id
     or old.organizer_id <> new.organizer_id
  then
    raise exception 'Meeting identity fields cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.protect_meeting_identity()
  from public, anon, authenticated;

create trigger meetings_protect_identity
before update on public.meetings
for each row execute function private.protect_meeting_identity();

create or replace function private.add_meeting_organizer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.meeting_participants (
    meeting_id,
    user_id,
    role,
    response_status,
    invited_by
  )
  values (
    new.id,
    new.organizer_id,
    'organizer',
    'accepted',
    new.organizer_id
  )
  on conflict (meeting_id, user_id) do update
  set role = 'organizer',
      response_status = 'accepted';

  return new;
end;
$$;

revoke all on function private.add_meeting_organizer()
  from public, anon, authenticated;

create trigger meetings_add_organizer
after insert on public.meetings
for each row execute function private.add_meeting_organizer();

create or replace function private.protect_participant_response()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  meeting_workspace_id uuid;
  meeting_organizer_id uuid;
begin
  if old.meeting_id <> new.meeting_id
     or old.user_id <> new.user_id
  then
    raise exception 'Participant identity fields cannot be changed'
      using errcode = '42501';
  end if;

  select workspace_id, organizer_id
  into meeting_workspace_id, meeting_organizer_id
  from public.meetings
  where id = old.meeting_id;

  if auth.uid() = old.user_id
     and auth.uid() <> meeting_organizer_id
     and not private.has_workspace_role(
       meeting_workspace_id,
       array['owner', 'admin']::public.workspace_role[]
     )
     and (
       old.role <> new.role
       or old.invited_by is distinct from new.invited_by
       or old.created_at <> new.created_at
       or new.response_status not in ('accepted', 'declined')
     )
  then
    raise exception 'Invitees may update only their response'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function private.protect_participant_response()
  from public, anon, authenticated;

create trigger meeting_participants_protect_response
before update on public.meeting_participants
for each row execute function private.protect_participant_response();

alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_invitations enable row level security;
alter table public.meetings enable row level security;
alter table public.meeting_participants enable row level security;

create policy profiles_select_collaborators
on public.profiles
for select
to authenticated
using (private.shares_workspace(id));

create policy profiles_update_self
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy workspaces_select_members
on public.workspaces
for select
to authenticated
using (private.is_workspace_member(id));

create policy workspaces_update_admins
on public.workspaces
for update
to authenticated
using (
  private.has_workspace_role(
    id,
    array['owner', 'admin']::public.workspace_role[]
  )
)
with check (
  private.has_workspace_role(
    id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

create policy workspaces_delete_owners
on public.workspaces
for delete
to authenticated
using (
  private.has_workspace_role(
    id,
    array['owner']::public.workspace_role[]
  )
);

create policy workspace_members_select_members
on public.workspace_members
for select
to authenticated
using (private.is_workspace_member(workspace_id));

create policy invitations_select_authorized
on public.workspace_invitations
for select
to authenticated
using (
  invitee_id = auth.uid()
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

create policy meetings_select_authorized
on public.meetings
for select
to authenticated
using (
  private.is_workspace_member(workspace_id)
  or exists (
    select 1
    from public.meeting_participants mp
    where mp.meeting_id = id
      and mp.user_id = auth.uid()
  )
);

create policy meetings_insert_members
on public.meetings
for insert
to authenticated
with check (
  organizer_id = auth.uid()
  and private.is_workspace_member(workspace_id)
);

create policy meetings_update_organizer_or_admin
on public.meetings
for update
to authenticated
using (
  organizer_id = auth.uid()
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
)
with check (
  organizer_id = auth.uid()
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

create policy meetings_delete_organizer_or_admin
on public.meetings
for delete
to authenticated
using (
  organizer_id = auth.uid()
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

create policy participants_select_meeting_access
on public.meeting_participants
for select
to authenticated
using (private.can_access_meeting(meeting_id));

create policy participants_insert_organizer_or_admin
on public.meeting_participants
for insert
to authenticated
with check (
  exists (
    select 1
    from public.meetings m
    where m.id = meeting_id
      and (
        m.organizer_id = auth.uid()
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
      and private.is_workspace_member(m.workspace_id)
  )
);

create policy participants_update_self_or_manager
on public.meeting_participants
for update
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.meetings m
    where m.id = meeting_id
      and (
        m.organizer_id = auth.uid()
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
  )
)
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.meetings m
    where m.id = meeting_id
      and (
        m.organizer_id = auth.uid()
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
  )
);

create policy participants_delete_manager
on public.meeting_participants
for delete
to authenticated
using (
  exists (
    select 1
    from public.meetings m
    where m.id = meeting_id
      and (
        m.organizer_id = auth.uid()
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
  )
);

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.workspaces from anon, authenticated;
revoke all on table public.workspace_members from anon, authenticated;
revoke all on table public.workspace_invitations from anon, authenticated;
revoke all on table public.meetings from anon, authenticated;
revoke all on table public.meeting_participants from anon, authenticated;

grant select, update on table public.profiles to authenticated;
grant select, update, delete on table public.workspaces to authenticated;
grant select on table public.workspace_members to authenticated;
grant select on table public.workspace_invitations to authenticated;
grant select, insert, update, delete on table public.meetings to authenticated;
grant select, insert, update, delete
  on table public.meeting_participants to authenticated;

revoke all on function public.find_profile_by_handle(text)
  from public, anon, authenticated;
revoke all on function public.create_workspace(text)
  from public, anon, authenticated;
revoke all on function public.invite_workspace_member(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.respond_to_workspace_invitation(uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.cancel_workspace_invitation(uuid)
  from public, anon, authenticated;
revoke all on function public.set_workspace_member_role(
  uuid,
  uuid,
  public.workspace_role
) from public, anon, authenticated;
revoke all on function public.remove_workspace_member(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.find_profile_by_handle(text)
  to authenticated;
grant execute on function public.create_workspace(text)
  to authenticated;
grant execute on function public.invite_workspace_member(uuid, uuid)
  to authenticated;
grant execute on function public.respond_to_workspace_invitation(uuid, boolean)
  to authenticated;
grant execute on function public.cancel_workspace_invitation(uuid)
  to authenticated;
grant execute on function public.set_workspace_member_role(
  uuid,
  uuid,
  public.workspace_role
) to authenticated;
grant execute on function public.remove_workspace_member(uuid, uuid)
  to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  false,
  2097152,
  array['image/jpeg']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy avatars_select_authenticated
on storage.objects
for select
to authenticated
using (bucket_id = 'avatars');

create policy avatars_insert_own_folder
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name = auth.uid()::text || '/profile.jpg'
);

create policy avatars_update_own_folder
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and owner_id = auth.uid()::text
  and name = auth.uid()::text || '/profile.jpg'
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name = auth.uid()::text || '/profile.jpg'
);

create policy avatars_delete_own_folder
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and owner_id = auth.uid()::text
  and name = auth.uid()::text || '/profile.jpg'
);

commit;
