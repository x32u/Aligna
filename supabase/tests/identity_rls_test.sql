begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'owner-a@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Owner A","handle":"owner_a"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'member-a@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Member A","handle":"member_a"}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'owner-b@example.test',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Owner B","handle":"owner_b"}',
    now(),
    now()
  );

insert into public.workspaces (id, name, created_by)
values
  (
    '20000000-0000-0000-0000-000000000001',
    'Workspace A',
    '10000000-0000-0000-0000-000000000001'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    'Workspace B',
    '10000000-0000-0000-0000-000000000003'
  );

insert into public.workspace_members (workspace_id, user_id, role)
values
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'owner'
  ),
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    'member'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003',
    'owner'
  );

insert into public.workspace_invitations (
  id,
  workspace_id,
  invitee_id,
  invited_by
)
values (
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003'
);

insert into public.meetings (
  id,
  workspace_id,
  organizer_id,
  title,
  status
)
values (
  '40000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003',
  'Private B meeting',
  'scheduled'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select is(
  (select count(*)::integer from public.workspaces),
  1,
  'cross-workspace reads are filtered'
);

select is(
  (select count(*)::integer from public.meetings),
  0,
  'nonparticipants cannot read another workspace meeting'
);

select is(
  (select count(*)::integer from public.workspace_invitations),
  0,
  'other users cannot read an invitation'
);

select is(
  (select count(*)::integer from public.profiles),
  2,
  'profiles outside a shared workspace are private'
);

update public.workspaces
set name = 'Unauthorized edit'
where id = '20000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)::integer
    from public.workspaces
    where name = 'Unauthorized edit'
  ),
  0,
  'unauthorized workspace updates affect no rows'
);

select throws_ok(
  $$
    select public.set_workspace_member_role(
      '20000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      'admin'
    )
  $$,
  '42501',
  'You cannot change your own role',
  'users cannot change their own role'
);

select throws_ok(
  $$
    select public.respond_to_workspace_invitation(
      '30000000-0000-0000-0000-000000000001',
      true
    )
  $$,
  '42501',
  'Only the invitee can respond',
  'only an invitation invitee may respond'
);

select throws_ok(
  $$
    select public.remove_workspace_member(
      '20000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001'
    )
  $$,
  '23514',
  'A workspace must keep at least one owner',
  'the final owner cannot be removed'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000002',
  true
);

select is(
  (
    select status::text
    from public.workspace_invitations
    where id = '30000000-0000-0000-0000-000000000001'
  ),
  'pending',
  'the invitee can read their pending invitation'
);

select is(
  public.respond_to_workspace_invitation(
    '30000000-0000-0000-0000-000000000001',
    false
  )::text,
  'declined',
  'the invitee can decline their invitation'
);

select is(
  (
    select count(*)::integer
    from public.workspace_members
    where workspace_id = '20000000-0000-0000-0000-000000000002'
      and user_id = '10000000-0000-0000-0000-000000000002'
  ),
  0,
  'declining does not create membership'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);

select is(
  (select count(*)::integer from public.meetings),
  1,
  'workspace B owner can read their meeting'
);

select is(
  (
    select count(*)::integer
    from public.meeting_participants
    where meeting_id = '40000000-0000-0000-0000-000000000001'
      and role = 'organizer'
  ),
  1,
  'meeting organizer is inserted automatically'
);

select is(
  (
    select handle
    from public.find_profile_by_handle('@owner_a')
  ),
  'owner_a',
  'exact handle lookup returns a limited profile'
);

select * from finish();
rollback;
