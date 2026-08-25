# Aligna Supabase setup

Aligna uses Supabase Auth, PostgreSQL, private Storage, and authenticated Edge
Functions. The iOS app contains only a project URL and a publishable key. Never
add a secret or `service_role` key to the app.

## 1. Link the verified project

The current Aligna project reference is `nzdnznkwqodolltmnhmf`.

```sh
brew install supabase/tap/supabase
supabase login
supabase link --project-ref nzdnznkwqodolltmnhmf
```

Do not run `supabase db reset` against a remote project. Apply only forward
migrations:

```sh
supabase db push
```

For local verification, Docker must be running:

```sh
supabase start
supabase db reset
supabase test db supabase/tests/identity_rls_test.sql
```

## 2. Configure iOS locally

Copy the example without committing the result:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Open Supabase Dashboard → Aligna → Connect → Mobile → Swift. Put the project
URL and an active `sb_publishable_...` key in `Secrets.xcconfig`. For URLs,
keep the xcconfig-safe `$()` between the slashes:

```text
SUPABASE_URL = https:/$()/nzdnznkwqodolltmnhmf.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_REPLACE_ME
```

`Secrets.xcconfig` is ignored by Git. Confirm before committing:

```sh
git check-ignore Config/Secrets.xcconfig
git grep -n -E 'sb_secret_|service_role'
```

## 3. Configure Auth

In Supabase Dashboard → Authentication → URL Configuration:

1. Add `aligna://auth/callback` to **Redirect URLs**.
2. Keep email/password enabled under Authentication → Providers → Email.
3. Keep **Confirm email** enabled for the production flow.
4. Customize the confirmation and password-recovery email templates if needed.

The app uses PKCE. Email confirmation and recovery callbacks return through the
registered `aligna` URL scheme. Social OAuth is intentionally not configured.

## 4. Database and Storage

The forward migration sequence is:

- `20260728030000_identity_and_collaboration.sql` creates the identity,
  workspace, invitation, meeting, RLS, trigger, RPC, and Storage foundation.
- `20260728031940_workspace_integrity.sql` protects immutable workspace
  ownership fields.
- `20260728033220_rls_performance.sql` adds foreign-key indexes and optimized
  authentication checks in RLS policies.
- `20260728033555_workspace_invitation_listing.sql` provides the guarded,
  limited pending-invitation list used by workspace managers.
- `20260728150548_meeting_ai_processing.sql` adds durable processing states,
  server-managed structured results, idempotent jobs, private diagnostics,
  Realtime publication, and the private `meeting-processing-audio` bucket with
  user/meeting-scoped Storage policies.
- `20260728151105_index_processing_diagnostics.sql` covers diagnostic cleanup
  and meeting-deletion lookups.
- `20260729090000_voice_recognition.sql` adds optional voice-enrollment state,
  server-encrypted private voice profiles, speaker-attributed transcript turns,
  correction history, and server-managed diarization metadata.
- `20260729093000_voice_recognition_advisor_indexes.sql` covers the speaker
  profile foreign keys reported by the Performance Advisor.

All application tables have RLS enabled. The private voice-profile and access
audit tables intentionally grant no client access; only JWT-authenticated Edge
Functions can reach them through the service role. The `avatars` bucket is
private, JPEG-only, limited to 2 MB, and only the owning user can modify its
object.

After pushing, run Security and Performance Advisors in Dashboard and resolve
new findings before release.

## 5. Edge Function

Store the Groq credential as an Edge Function secret. Do not put it in Xcode,
an xcconfig, the database, or Git:

```sh
supabase secrets set GROQ_API_KEY=YOUR_GROQ_KEY \
  --project-ref nzdnznkwqodolltmnhmf
```

Voice profiles require a separate random 32-byte AES key encoded as base64.
Generate and upload it without writing the value to the repository:

```sh
supabase secrets set VOICE_PROFILE_ENCRYPTION_KEY="$(openssl rand -base64 32)" \
  --project-ref nzdnznkwqodolltmnhmf
```

Changing this key makes existing cloud voice profiles unreadable. If rotation
is required, migrate or delete those encrypted profiles before replacing it.

Deploy only while linked to the verified project:

```sh
supabase functions deploy delete-account \
  --project-ref nzdnznkwqodolltmnhmf \
  --verify-jwt

supabase functions deploy process-meeting \
  --project-ref nzdnznkwqodolltmnhmf \
  --verify-jwt

supabase functions deploy voice-profiles \
  --project-ref nzdnznkwqodolltmnhmf \
  --verify-jwt

supabase functions deploy speaker-attribution \
  --project-ref nzdnznkwqodolltmnhmf \
  --verify-jwt
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to the function runtime. Never place the service
role key in source control or in the iOS configuration.

All four functions must keep JWT verification enabled. The commands above are
the reproducible deployment path for later versions.

The account-deletion function derives the user from the verified JWT. It blocks deletion until
ownership is transferred for multi-member workspaces, requires confirmation
before deleting sole-member workspaces, removes avatars and user-owned cloud
meeting metadata, then deletes the Auth user last. Local recordings remain on
the device.

`process-meeting` verifies the caller and meeting owner, claims a single
idempotent job, downloads only that meeting’s private M4A chunks, transcribes
without forcing a language, and creates structured meeting notes. Aligna
validates the JSON structure and transcript evidence before saving. Raw errors
and internal model/version metadata stay in the private diagnostics schema.

Successful processing deletes temporary cloud audio immediately. Failed jobs
retain it for at most 72 hours so the owner can retry; the function
opportunistically cleans expired failed uploads on later authenticated
invocations. The original M4A remains on the iPhone.

The optional speaker-identification flow runs FluidAudio diarization and voice
embedding comparison on the iPhone. Enrollment audio never leaves the device.
Only the consented aggregate embedding is sent to `voice-profiles`, where it is
encrypted before storage. Candidate profiles are limited to the organizer and
explicit meeting participants. The client sends speaker-attributed turns—not
voice vectors—to `speaker-attribution`.

## 6. Manual two-account verification

1. Create two accounts and verify both email addresses.
2. Complete both profiles with unique handles.
3. Create a workspace with account A.
4. Invite account B by its exact `@handle`.
5. Accept the invitation as account B.
6. Create a meeting as account A and select both members.
7. Record and finish the meeting; verify the original audio remains local while
   temporary private audio is removed after the notes are ready.
8. Sign out, sign in as account B, and confirm account A’s local recordings
   are hidden.
9. Relaunch the app and confirm the authenticated session restores.
10. Test role changes, invitation cancellation, and account-deletion ownership
    protection.
11. Opt into Voice Recognition in Settings, record all four samples, and
    verify deleting the profile removes both the local encrypted copy and the
    private server copy.
12. Record a two-account meeting with both accounts selected as participants.
    Confirm unmatched speakers remain generic and manually correct one speaker
    from the results transcript.
