-- Return limited invitee identity to authorized workspace managers.
create or replace function public.list_workspace_invitations(
  p_workspace_id uuid
)
returns table (
  id uuid,
  workspace_id uuid,
  invitee_id uuid,
  invitee_display_name text,
  invitee_handle text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_workspace_role(
    p_workspace_id,
    array['owner', 'admin']::public.workspace_role[]
  ) then
    raise exception 'Insufficient workspace permission'
      using errcode = '42501';
  end if;

  return query
  select
    invitation.id,
    invitation.workspace_id,
    invitation.invitee_id,
    profile.display_name,
    profile.handle,
    invitation.created_at
  from public.workspace_invitations invitation
  join public.profiles profile on profile.id = invitation.invitee_id
  where invitation.workspace_id = p_workspace_id
    and invitation.status = 'pending'
  order by invitation.created_at desc;
end;
$$;

revoke all on function public.list_workspace_invitations(uuid)
from public, anon, authenticated;
grant execute on function public.list_workspace_invitations(uuid)
to authenticated;
