-- Add foreign-key indexes and cache auth.uid() once per RLS statement.
create index if not exists workspaces_created_by_idx
on public.workspaces (created_by);

create index if not exists workspace_invitations_invited_by_idx
on public.workspace_invitations (invited_by);

create index if not exists meeting_participants_invited_by_idx
on public.meeting_participants (invited_by);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists invitations_select_authorized
on public.workspace_invitations;
create policy invitations_select_authorized
on public.workspace_invitations
for select
to authenticated
using (
  invitee_id = (select auth.uid())
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

drop policy if exists meetings_select_authorized on public.meetings;
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
      and mp.user_id = (select auth.uid())
  )
);

drop policy if exists meetings_insert_members on public.meetings;
create policy meetings_insert_members
on public.meetings
for insert
to authenticated
with check (
  organizer_id = (select auth.uid())
  and private.is_workspace_member(workspace_id)
);

drop policy if exists meetings_update_organizer_or_admin
on public.meetings;
create policy meetings_update_organizer_or_admin
on public.meetings
for update
to authenticated
using (
  organizer_id = (select auth.uid())
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
)
with check (
  organizer_id = (select auth.uid())
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

drop policy if exists meetings_delete_organizer_or_admin
on public.meetings;
create policy meetings_delete_organizer_or_admin
on public.meetings
for delete
to authenticated
using (
  organizer_id = (select auth.uid())
  or private.has_workspace_role(
    workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  )
);

drop policy if exists participants_insert_organizer_or_admin
on public.meeting_participants;
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
        m.organizer_id = (select auth.uid())
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
      and private.is_workspace_member(m.workspace_id)
  )
);

drop policy if exists participants_update_self_or_manager
on public.meeting_participants;
create policy participants_update_self_or_manager
on public.meeting_participants
for update
to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.meetings m
    where m.id = meeting_id
      and (
        m.organizer_id = (select auth.uid())
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
  )
)
with check (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.meetings m
    where m.id = meeting_id
      and (
        m.organizer_id = (select auth.uid())
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
  )
);

drop policy if exists participants_delete_manager
on public.meeting_participants;
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
        m.organizer_id = (select auth.uid())
        or private.has_workspace_role(
          m.workspace_id,
          array['owner', 'admin']::public.workspace_role[]
        )
      )
  )
);
