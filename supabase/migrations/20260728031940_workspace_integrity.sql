-- Prevent client updates from changing immutable workspace ownership fields.
create or replace function private.protect_workspace_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id <> old.id or new.created_by is distinct from old.created_by then
    raise exception 'Workspace identity and creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_workspace_identity on public.workspaces;
create trigger protect_workspace_identity
before update on public.workspaces
for each row execute function private.protect_workspace_identity();
