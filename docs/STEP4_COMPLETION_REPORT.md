# Aligna Step 4 Completion Audit

**Audit date:** 5 August 2026
**Repository:** Aligna native iOS project
**Audited commit:** `6101a5f` (`main`) plus the working tree at audit time
**Scope:** Step 4 meeting recording, post-meeting transcription, AI analysis, persistence, and results. Existing Step 5 files were inspected only where they affect Step 4; no Step 5 feature work was performed.

## Status legend

- **Completed and verified** — present in the active implementation and confirmed by build, automated test, deployed-state inspection, or direct static verification.
- **Implemented but not verified** — connected implementation exists, but the required runtime scenario was not executed in this audit.
- **Partially implemented** — a meaningful implementation exists, but part of the requirement is absent or unsafe.
- **Not implemented** — no production implementation was found.
- **Blocked** — verification could not complete because of an identified environment or product issue.
- **Requires physical-device testing** — cannot be honestly validated using the simulator or static inspection.

## 1. Executive summary

### Verdict: **Not ready**

Aligna has a substantial, connected Step 4 implementation. It records speech-optimized local M4A audio, persists meetings before processing, uploads user-scoped chunks to a private Supabase bucket, invokes an authenticated Edge Function, transcribes with Groq Whisper, analyzes with Groq Llama, stores outcomes, listens through Realtime, and presents customer-facing processing/result states. The project builds successfully for an iPhone SE simulator and **75/75 unit tests pass**.

Step 4 is nevertheless not ready for sign-off because:

1. The deployed/local `process-meeting` function has been changed to depend on the later speaker pipeline. After Whisper it stops at `merging_transcript` and waits for `meeting_transcript_turns` before analysis. Step 4 is therefore no longer independently end-to-end and contradicts the Step 4 limitation that speaker diarization/identification is outside scope.
2. Required physical-iPhone checks were not performed in this audit: real microphone capture, English, Filipino, mixed Taglish, playback, long meetings, airplane-mode recovery, and app termination.
3. Upload/processing continuity is foreground/process-lifetime work. There is no background `URLSession` upload or `BGProcessingTask`, so termination and extended suspension are not guaranteed to continue.
4. Chunking uses fixed 20-minute segments with overlap but does not recursively reduce a chunk that still exceeds the 22 MiB direct limit.
5. UI-test preparation succeeds, but the simulator could not launch the UI test runner. Both UI tests remained unexecuted and the run was interrupted after approximately 181 seconds.
6. Temporary failed audio has a documented 72-hour policy, but cleanup is opportunistic on later function invocations rather than scheduled, so the actual deletion time is not guaranteed.

The current deployed project does show historical real processing evidence: 8 completed processing jobs/meetings with transcripts and analysis data, one failed transcription diagnostic, and no remaining objects in the processing bucket at audit time. This is useful operational evidence, but it is not a substitute for the required controlled device test matrix on the current source.

## 2. Requirement-by-requirement audit

### 2.1 Removal of Apple SpeechAnalyzer and technical transcription UI

- **Status:** **Partially implemented**.
- **Evidence:** The customer recording flow in `MeetingCaptureView`, `NewMeetingView`, and `MeetingCaptureViewModel` contains no language picker, term list, live transcript, engine/model label, machine/live fallback label, or transcription diagnostic panel. `Config/Aligna-Info.plist` contains `NSMicrophoneUsageDescription` and no speech-recognition usage description. The production capture path only uses the recorder.
- **Remaining code:** `Services/Speech/AppleFinalTranscriptionService.swift`, `AppleSpeechAssetManager.swift`, `AppleSpeechCapabilityProvider.swift`, `AppleSpeechTranscriptionService.swift`, their protocols/models, locale/glossary fields in `CaptureModels.swift`, and legacy speech tests still remain in the target. Production dependencies substitute mocks rather than fully removing the obsolete subsystem.
- **Tests:** `Capture does not require a speech-recognition model` and `Legacy speech failures cannot become completed transcripts` passed.
- **Gap:** Technical UI is removed from the normal path, but Apple speech code and its model abstractions are not fully removed.

### 2.2 Minimal one-tap recording workflow

- **Status:** **Implemented but requires physical-device testing**.
- **Evidence:** `HomeView` presents `MeetingCaptureFlowView`; the flow starts from `.task` without a setup form. `NewMeetingView.makeConfiguration()` assigns `Meeting · <date/time>` and does not require a title. `MeetingCaptureView` shows recording state, elapsed time, a small waveform, Pause/Resume, and Finish. `MeetingCaptureViewModel` guards repeated starts and repeated finishes through its capture state.
- **Tests:** State transitions, duplicate start prevention, pause-duration accounting, waveform smoothing, and cancel cleanup are covered by passing unit tests. There is no explicit duplicate-Finish UI or concurrency test.
- **Gaps:** No optional “Add details” disclosure was found. Simulator capture uses `MockAudioRecordingService`; real microphone permission, route, level behavior, and actual file quality require an iPhone.

### 2.3 Post-meeting processing flow

- **Status:** **Partially implemented**.
- **Evidence:** `MeetingCaptureViewModel.finish()` stops and validates audio before constructing and saving a queued `Meeting`. `MeetingCaptureFlowView` hands the saved meeting to `MeetingLibrary.retryProcessing`. `MeetingLibrary` persists state, owns processing tasks, monitors connectivity with `NWPathMonitor`, and resumes queued work. `MeetingDetailView` maps backend states to “Preparing recording,” “Creating transcript,” and “Organizing your notes.” `MeetingsView` keeps processing records visible.
- **Tests:** Save-before-processing, processing-phase copy, status promotion, error classification, and local persistence tests passed.
- **Gaps:** Work continues when navigating elsewhere only while the app process is allowed to run. No durable iOS background-transfer or background-processing mechanism was found. Current processing also pauses for the out-of-scope Step 5 speaker pipeline before analysis.

### 2.4 M4A audio preparation

- **Status:** **Completed in code; requires physical-device testing**.
- **Evidence:** `AudioRecordingService.startRecording()` writes `.m4a` directly under Application Support using AAC, mono, 16 kHz, 48 kbps. `stop()` retains and validates the local recording. `AudioPreparationService` exports chunks as Apple M4A when necessary.
- **Tests:** Mock recording produces an M4A and save-before-processing is covered. No production AVAudioRecorder integration test runs on the simulator.
- **Gap:** Actual iPhone recording quality, interruptions, Bluetooth routes, and long-duration file integrity were not tested here.

### 2.5 Long-recording compression and chunking

- **Status:** **Partially implemented**.
- **Evidence:** `AudioPreparationService` uses a 22 MiB direct-upload threshold, targets 18 MiB chunks, prefers 20-minute spans, and adds a 2-second overlap. The Edge Function shifts chunk timestamps and removes overlap duplication using word and segment comparisons.
- **Tests:** Timeline normalization has unit coverage, but no automated test directly exercises AVAsset export, a provider-limit file, overlap reconstruction through the Edge Function, or a multi-hour recording.
- **Gap:** A generated chunk that remains over 22 MiB throws `chunkTooLarge`; it is not recursively split or bitrate-adjusted. This makes provider-limit handling incomplete for atypically large/high-bitrate source files.

### 2.6 Secure Supabase backend architecture

- **Status:** **Completed and verified, with noted hardening gaps**.
- **Evidence:** Deployed project `nzdnznkwqodolltmnhmf` contains the private `meeting-processing-audio` bucket (24 MiB limit; M4A/MP4 MIME allowlist), user-scoped Storage policies, meeting/job tables, ownership-aware database policies, Realtime publication, and `process-meeting` v3 with JWT verification enabled. The iOS path is `{authenticated-user-id}/{meeting-id}/chunk-N.m4a`. The function authenticates with `auth.getUser`, queries the meeting through the caller-scoped client, and explicitly compares `organizer_id` with the caller before using a service-role client internally.
- **Idempotency:** Meeting ID is the request/idempotency key; `meeting_processing_jobs` has a unique meeting key and the claim function prevents a duplicate active result. The local library also deduplicates active processing tasks.
- **Tests/evidence:** The deployed database contained 8 completed jobs and no processing-bucket objects at audit time. Local SQL tests cover identity RLS, not the Step 4 processing policies.
- **Gaps:** The `private.meeting_processing_diagnostics` table has RLS disabled. Anonymous/authenticated grants are currently absent, so it is not client-readable, but enabling RLS would add defense in depth and remove the Supabase security advisory. Several authenticated `SECURITY DEFINER` routines also warrant periodic privilege review.

### 2.7 Groq Whisper transcription

- **Status:** **Implemented and historically exercised; current controlled flow not verified**.
- **Evidence:** `supabase/functions/process-meeting/index.ts` calls `/audio/transcriptions` with `whisper-large-v3`, `temperature=0`, `response_format=verbose_json`, segment and word timestamps, and no fixed `language`. It stores the full transcript, relative segments/words, provider language hints, model/version, and processing timestamps. Chunk offsets and overlap deduplication are implemented.
- **Operational evidence:** The deployed database has 8 completed rows with transcripts/segments/languages. One diagnostic records a `word_timestamps_missing` failure, demonstrating strict timestamp validation.
- **Gap:** No new Groq request was initiated by this audit. English, Filipino, and mixed Taglish recordings were not controlled-test verified. Requiring word timestamps is stricter than the product UI requires and can fail otherwise useful transcriptions.

### 2.8 Groq meeting analysis

- **Status:** **Partially implemented**.
- **Evidence:** The Edge Function uses `llama-3.3-70b-versatile`, temperature 0, JSON response mode, a schema-shaped prompt, and manual validation. It returns/stores generated title, summary, key points, decisions, action items with nullable assignee/due date and transcript evidence, open questions, follow-ups, and languages. Prompts explicitly forbid invention, preserve Filipino/English names and terms, and request the dominant meeting language. Transcripts above 72,000 characters use 36,000-character hierarchical summaries before final analysis.
- **Operational evidence:** Eight deployed meetings contain completed title/summary/outcome data.
- **Gaps:** Groq JSON mode is used with application-side validation, not a provider-enforced JSON Schema response format. More importantly, the current function will not enter analysis until the Step 5 attributed-turn records exist or speaker processing is explicitly skipped. That is the primary end-to-end Step 4 blocker.

### 2.9 Results screen

- **Status:** **Implemented but not fully runtime-verified**.
- **Evidence:** `MeetingDetailView` prioritizes the AI title and Overview, then Action Items, Decisions, Key Points, Open Questions, Follow-ups, a collapsed Transcript, and local audio playback via `AVAudioPlayer`. It supports title editing and processing retry. Provider/model names are not presented to ordinary users.
- **Tests:** Model promotion from a completed processing result is covered. No UI test covers the result screen or playback.
- **Gaps:** Only the title is directly editable; analysis items are display-only. Speaker correction UI is Step 5 functionality and should not be considered part of Step 4 completion. Actual playback requires an iPhone/manual test.

### 2.10 Offline, retry, and failure handling

- **Status:** **Partially implemented**.
- **Evidence:** Local audio and meeting metadata are saved before upload. `MeetingLibrary` reports the offline copy (“Saved on this iPhone…”) and resumes pending work when `NWPathMonitor` reports connectivity. Failed meetings remain visible as “Needs processing”; raw backend errors are reduced to customer-safe issues. Duplicate local processing tasks are guarded, and server jobs are idempotent by meeting ID.
- **Tests:** Offline/server error mapping, local retention, cancellation, and status promotion passed.
- **Gaps:** Airplane-mode recovery was not executed. App termination during upload/processing is not guaranteed; restart recovery depends on local state and a still-valid local file. No test forces a transcription failure, analysis failure, duplicate Retry race, or termination/relaunch sequence against the real backend.

### 2.11 Speaker-identification limitation

- **Status:** **Requirement violated by later existing work**.
- **Evidence:** FluidAudio 0.15.5, voice enrollment, diarization, speaker matching, transcript reconciliation, Step 5 migrations, three speaker-related Edge Functions, attributed transcript UI, and speaker unit/UI tests are present. `process-meeting` now transitions to `merging_transcript` and waits for `meeting_transcript_turns` before analysis.
- **Impact:** Step 4 can no longer be reviewed as an independent “no diarization/identification” pipeline. The code must either restore a speaker-independent Step 4 path or explicitly treat the existing speaker stage as a separately verified later feature without making core analysis depend on it.

### 2.12 Verification requirements

- **Status:** **Partially completed**.
- **Verified:** Full simulator build succeeds; 75 unit tests pass; deployed database/function/storage configuration was inspected; tracked, untracked, config, and built-app secret scans were performed.
- **Blocked:** Two UI tests could not launch the simulator test runner and were interrupted. They cover only Step 5 voice setup, not Step 4.
- **Requires physical device:** Real recording, playback, English/Filipino/Taglish, airplane mode, termination/relaunch, and long recording/provider-limit scenarios.

## 3. Actual end-to-end architecture

```text
HomeView “Start meeting”
  → MeetingCaptureFlowView / MeetingCaptureViewModel
  → AudioRecordingService (.m4a, 16 kHz mono AAC, retained locally)
  → LocalMeetingRepository saves a queued Meeting
  → MeetingLibrary starts/resumes processing
  → AudioPreparationService returns direct audio or overlapped chunks
  → SupabaseMeetingProcessingService upserts meeting + chunk metadata
  → private Storage: {user}/{meeting}/chunk-{n}.m4a
  → authenticated invocation of process-meeting
  → Edge Function authenticates user and verifies organizer ownership
  → idempotent processing job claim
  → Groq Whisper transcription and timestamp merge
  → CURRENT EXTRA DEPENDENCY: iOS/Step 5 speaker pipeline writes attributed turns
  → process-meeting analysis mode reads turns
  → Groq Llama structured meeting analysis
  → meeting result and job status saved; temporary audio deleted
  → Supabase Realtime meeting update
  → MeetingLibrary persists the update locally
  → MeetingsView / MeetingDetailView displays processing or results
```

The recording, local persistence, upload, Edge Function, database result, Realtime, and result UI are production implementations, not placeholders. Simulator recording is intentionally mocked. The external Groq stages are real deployed backend code; this audit inspected existing output rather than submitting a new recording. The Step 5 speaker stage is the break in the requested Step 4-only chain.

## 4. Files changed and working-tree state

The repository has one initial commit and a very large uncommitted working tree. No files were discarded, reset, staged, or committed during this audit. This report is the only source artifact added by the audit; generated audit DerivedData was also created under the already-untracked `build/` directory.

### Modified tracked files

- `Aligna.xcodeproj/project.pbxproj` — adds Supabase 2.52.0, FluidAudio 0.15.5, custom configuration/Info.plist, shared schemes, and the Live Activity extension.
- `Aligna.xcodeproj/xcuserdata/.../xcschememanagement.plist` — local scheme management metadata.
- `Aligna/Assets.xcassets/AccentColor.colorset/Contents.json` — adaptive accent variants.
- `Aligna/Assets.xcassets/AppIcon.appiconset/Contents.json` — app-icon asset reference.
- `Aligna/ContentView.swift` — session-driven root, appearance, deep-link handling, lifecycle refresh, and password-update sheet.
- `AlignaTests/AlignaTests.swift` — 75 Swift Testing cases across design, auth, dashboard, capture, processing, legacy speech, and existing Step 5 speaker logic.
- `AlignaUITests/AlignaUITests.swift` — two Step 5 voice-setup UI/performance tests.

### Added/untracked source areas

- `Aligna/App/` (1 Swift file) — tab/root navigation.
- `Aligna/Core/` (8) — design system, configuration, Supabase client, session, validation, dependencies.
- `Aligna/Data/` (14) — DTOs, local/cloud repositories, meeting library, Supabase services, mocks.
- `Aligna/Features/` (33) — authentication, dashboard, capture/results, meetings, onboarding, profile, settings, tasks, workspaces.
- `Aligna/Services/` (20) — recording/preparation, processing, obsolete Apple speech services, Live Activity, and existing Step 5 voice services.
- `Aligna/Shared/` (28) — reusable components, models, mock/sample data, service protocols, Live Activity attributes.
- `AlignaLiveActivity/` — widget extension source and Info.plist.
- `Aligna/Brand/`, `AlignaBrandMark.imageset`, and `AlignaAppIcon.png` — brand assets; the existing app icon is preserved.
- `Config/` — app Info.plist, checked-in template/config wiring, and ignored local secrets configuration. No Groq key was found.
- `supabase/migrations/` — six identity/collaboration/Step 4 migrations plus three already-existing Step 5 voice migrations.
- `supabase/functions/` — `delete-account`, `process-meeting`, and already-existing `voice-profiles`/`speaker-attribution` functions.
- `supabase/tests/identity_rls_test.sql` — identity/workspace RLS SQL tests.
- `SUPABASE_SETUP.md` and `TRANSCRIPTION_TEST_PLAN.md` — deployment and physical/manual verification guidance.
- `Aligna.xcodeproj/.../Package.resolved`, shared schemes, `.gitignore`, and untracked `build/` outputs.

Existing authentication, dashboard, collaboration, appearance, Live Activity, and Step 5 work is unrelated to this audit and was preserved as found.

## 5. Database and backend report

### Step 4 schema

`20260728150548_meeting_ai_processing.sql` adds/uses:

- Processing status values: `queued`, `uploading`, `transcribing`, `analyzing`, `complete`, `failed` (later Step 5 migrations add speaker states).
- Meeting processing fields for local/cloud audio metadata, chunk manifests, transcript text/segments/words, detected language(s), model/version, generated title, summary, key points, decisions, action items, open questions, follow-ups, processing timestamps, and customer-safe error state.
- `meeting_processing_jobs` for idempotent job ownership, attempts, stage, success/failure, and retention.
- `private.meeting_processing_diagnostics` for service-only technical diagnostics.
- Realtime publication of `public.meetings`.

`20260728151105_index_processing_diagnostics.sql` adds the diagnostics lookup index. Deployed migration history contains all local Step 4 migrations and later Step 5 migrations.

### Storage and policies

- Bucket: `meeting-processing-audio`, private, 24 MiB per object, M4A/MP4 MIME allowlist.
- Path: `{auth.uid()}/{meeting-id}/chunk-{index}.m4a`.
- Authenticated SELECT/INSERT/UPDATE/DELETE policies require the first path component to match `auth.uid()` and the referenced meeting to be owned/visible to the caller.
- The Swift client uses upsert, so SELECT, INSERT, and UPDATE are all required and present.

### Edge Functions and ownership

- `process-meeting` v3: deployed with JWT verification; also validates `auth.getUser()` and organizer ownership.
- `delete-account` v3: unrelated account cleanup.
- `voice-profiles` v3 and `speaker-attribution` v2: existing Step 5 functions, outside this audit but currently coupled to processing.
- Only the Edge Function reads `GROQ_API_KEY`; service-role use remains server-side.

### Idempotency, retry, and cleanup

- Client request key: meeting UUID.
- Server job uniqueness: one `meeting_processing_jobs` row per meeting, claimed transactionally through RPC/state.
- Local duplicate guard: one active `Task` per meeting in `MeetingLibrary`.
- Retry resumes the same meeting rather than creating a second meeting.
- Success deletes uploaded chunks immediately and clears cloud chunk metadata.
- Failure retains processing audio for 72 hours. `cleanupExpiredAudio` runs opportunistically when `process-meeting` is invoked; there is no scheduled cleanup, so “72 hours” is a minimum eligibility time rather than a guaranteed deletion deadline.

### Realtime

`SupabaseMeetingProcessingService` subscribes to the authenticated user’s meeting changes, fetches an initial snapshot, and turns backend updates into persisted local `Meeting` updates. The deployed `meetings` table is in the Realtime publication.

### Required secret and deployment commands

Do not place values in Swift, Info.plist, or committed xcconfig files. From `SUPABASE_SETUP.md`:

```sh
supabase link --project-ref <project-ref>
supabase db push
supabase secrets set GROQ_API_KEY=<value> --project-ref <project-ref>
supabase functions deploy process-meeting --project-ref <project-ref>
```

The current local shell does not have `supabase` or `deno` installed, so local CLI migration replay and `deno check` were not run. Deployment was verified by inspecting the connected Supabase project, not performed by this audit.

## 6. Security audit

| Check | Result | Evidence |
|---|---|---|
| Groq key absent from Swift | **Completed and verified** | Recursive tracked/untracked search found no `GROQ_API_KEY`, Groq host, or likely `gsk_…` value in Swift. |
| Key absent from Info.plist/committed xcconfig | **Completed and verified** | No Groq identifiers were found under `Config`, Xcode project files, or app/extension plists. `Secrets.xcconfig` is ignored and contained no Groq identifier. |
| No Groq key sent by iOS | **Completed and verified statically** | Swift invokes Supabase; only `process-meeting/index.ts` reads the Edge secret and calls Groq. |
| Built bundle is clean | **Completed and verified** | Executable/string scan of `build/Step4AuditDerivedData/.../Aligna.app` found no key name, Groq API host, or likely Groq key prefix. |
| Private audio storage | **Completed and verified** | Deployed bucket reports `public=false`; path/MIME/size policies were inspected. |
| User-scoped data/storage | **Completed and verified, with advisory** | Storage policies and meeting RLS are owner/member scoped. Private diagnostics has no anon/auth grants but RLS is disabled; enable it for defense in depth. |
| Function auth and ownership | **Completed and verified** | JWT verification, `auth.getUser`, RLS-scoped query, and explicit organizer comparison are all present. |
| Customer-safe errors | **Completed and verified statically** | Swift maps backend failures to generic offline/server/customer messages; raw detail is stored privately. |
| Sensitive logs | **Ready with limitation** | No secret logging was found. Backend DEBUG/error logging can include up to 500 characters of provider error detail; this should be redacted/structured because provider text may contain sensitive transcript-related context. |
| Temporary cleanup | **Partially implemented** | Immediate success deletion works and the bucket was empty at audit time. Failed-item cleanup is not scheduled, so exact retention is not guaranteed. |

Searches covered tracked and untracked files while excluding `.git` and generated package sources, then separately inspected the generated simulator app. Search output contained only documentation and the server Edge Function’s environment-variable reference; no candidate key value was printed or found.

## 7. Build and automated-test results

### Environment

- Xcode: `/Applications/Xcode-beta.app`, iOS 27.0 SDK.
- Project: `Aligna.xcodeproj`.
- Build/unit scheme: `AlignaUnitTests`.
- UI scheme: `AlignaUITests`.
- Destination: `Aligna iPhone SE`, iPhone SE (3rd generation), iOS 27.0 simulator, ID `9FE000D6-2474-4D5F-8C8B-84116BA57740`.
- Resolved packages: Supabase Swift 2.52.0 and FluidAudio 0.15.5.

### Commands and results

```sh
xcodebuild -project Aligna.xcodeproj -scheme AlignaUnitTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=9FE000D6-2474-4D5F-8C8B-84116BA57740' \
  -derivedDataPath build/Step4AuditDerivedData \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

**Result:** Passed, `** BUILD SUCCEEDED **`. A following incremental `-quiet` build produced no diagnostics.

```sh
xcodebuild ... -scheme AlignaUnitTests ... build-for-testing -quiet
xcodebuild ... -scheme AlignaUnitTests ... test-without-building -quiet
xcrun xcresulttool get test-results summary --path \
  build/Step4AuditDerivedData/Logs/Test/Test-AlignaUnitTests-2026.08.05_16-22-01-+0800.xcresult
```

**Result:** **75 passed, 0 failed, 0 skipped, 0 expected failures**. Runtime warnings array was empty.

```sh
xcodebuild ... -scheme AlignaUITests \
  -derivedDataPath build/Step4AuditUIDerivedData build-for-testing -quiet
xcodebuild ... -scheme AlignaUITests \
  -derivedDataPath build/Step4AuditUIDerivedData test-without-building -quiet
```

**Result:** Build-for-testing passed. Execution was **blocked**: the simulator repeatedly failed to launch `dev.notjc.Aligna` for UI testing and Xcode remained waiting for the runner. It was interrupted after approximately 181 seconds. Therefore **0 UI tests are reported passed, failed, or skipped**; both were not executed. Xcode emitted `debugger version lookup failed` and a cancellation-time scheme action assertion. The two UI tests are Step 5 voice-onboarding tests and do not cover Step 4.

The audit did not claim a current physical-device run, deployment, migration push, or new external Groq request.

## 8. Functional test matrix

| Scenario | Actual audit result | Evidence/notes |
|---|---|---|
| Start recording with one tap | **Not tested** | The underlying start/duplicate-start logic passed unit tests, but the actual Home-to-recording interaction was not executed. |
| Pause and resume | **Passed through automated test** | State/duration behavior passed. |
| Finish exactly once | **Not tested** | Guard code exists, but no explicit duplicate-Finish concurrency/UI test was found. |
| Local recording retention | **Passed through automated test** | Save-before-processing and local persistence covered with mocks. |
| English transcription | **Not tested** | Historical deployed result exists; no controlled current sample. |
| Filipino transcription | **Not tested** | Requires physical iPhone/external request. |
| Mixed Taglish transcription | **Not tested** | Requires physical iPhone/external request. |
| AI title and summary generation | **Not tested** | Historical DB rows verify operation, but not a controlled current test. |
| Decisions and action items | **Passed through automated test** | Result promotion/mapping passed; grounding against real audio not tested. |
| Transcript timestamps | **Passed through automated test** | Timeline normalization/reconciliation logic passed; provider merge not integration-tested. |
| Audio playback | **Not tested** | `AVAudioPlayer` implementation exists. |
| Offline finish | **Not tested** | Local save and offline error mapping pass separately; the complete airplane-mode Finish flow was not executed. |
| Reconnection and resumed processing | **Not tested** | NWPathMonitor implementation exists; real reconnect not executed. |
| App termination during upload | **Blocked** | No background transfer guarantee. |
| App termination during processing | **Not tested** | Server function can continue; client resubscribe path exists, but termination scenario was not run. |
| Duplicate Finish taps | **Not tested** | Capture state should prevent a second finalize, but no explicit race/UI test was found. |
| Duplicate Retry taps | **Not tested** | MeetingLibrary and server guards exist, but no live or automated retry-race test was found. |
| Failed transcription | **Not tested** | Deployed diagnostics show one historical failure; not deliberately reproduced. |
| Failed analysis | **Not tested** | Failure path exists; not deliberately reproduced. |
| Long recording above direct limit | **Not tested** | Chunk code exists; no large-file integration test. |
| Temporary cloud-audio cleanup | **Not tested** | Bucket was empty and success-delete code exists; no controlled retention test. |
| Meeting visibility while processing | **Not tested** | Persisted state/status mapping exists; no navigation/UI execution verified the row while processing. |

No row is labeled “Passed on physical iPhone” because this audit did not execute a physical-device test.

## 9. Known limitations and risks

### Product/reliability

- Core analysis currently depends on existing Step 5 speaker attribution, so Step 4 cannot complete independently.
- No background `URLSession` or `BGProcessingTask`; upload continuity through suspension/termination is not guaranteed.
- Restart recovery requires the local file and valid account state to remain available.
- Fixed chunk sizing can still yield an over-limit chunk and fail instead of subdividing it.
- Word-timestamp absence rejects an otherwise valid transcription.
- Duplicate overlap removal is heuristic and has no real long-recording integration test.
- Failed-audio deletion is opportunistic, not scheduled.
- Realtime reconnect and missed-event reconciliation are implemented through snapshot/resume logic but not stress-tested.
- Audio playback, interruptions, AirPods/Bluetooth routing, phone calls, low storage, and lock-screen behavior require an iPhone.

### Testing

- UI tests cannot currently launch in the selected simulator and do not cover Step 4 anyway.
- No Edge Function automated tests, Step 4 SQL RLS tests, Storage policy integration tests, or Groq contract fixtures were found.
- No automated AVAsset chunk/export, large file, app relaunch, airplane mode, English/Filipino/Taglish, or audio playback tests were found.
- Simulator capture uses a mock and cannot verify microphone quality.

### Architecture/maintenance

- Obsolete Apple speech services, locale/glossary models, and legacy tests remain in the main target even though the customer flow no longer uses them.
- Step 4 and Step 5 are interleaved in models, states, UI, migrations, tests, dependencies, and the deployed Edge Function, making rollback and independent verification difficult.
- The entire application beyond the Xcode starter is largely untracked; it must be reviewed and committed in coherent changes before it is safely reproducible.
- `supabase` and `deno` CLIs are unavailable locally, so clean migration replay and Edge type-checking were not performed.

### Security/privacy

- Enable RLS on private diagnostics even though client grants are currently revoked.
- Redact provider-error bodies before backend logging; keep technical detail in tightly controlled diagnostics.
- Update privacy/App Store disclosures to state that audio is temporarily uploaded to Supabase and Groq for processing.
- Document an enforceable scheduled retention job rather than relying on later traffic.
- Supabase leaked-password protection is disabled (authentication hardening outside Step 4 but relevant before release).

## 10. Step 5 readiness verdict

# **NO-GO FOR STEP 5**

The following must be completed first:

1. Restore a Step 4 processing path that reaches analysis without voice enrollment, diarization, voice identification, or attributed-turn records. Existing Step 5 logic must be optional rather than a core dependency.
2. Pass the complete physical-iPhone matrix for real M4A capture/playback, English, Filipino, mixed Taglish, offline/reconnect, duplicate actions, failure/retry, long recording, and termination/relaunch.
3. Add durable background upload/recovery behavior or clearly constrain and test the supported lifecycle.
4. Make chunking safely subdivide any chunk that remains above the provider/object limit and add a large-file integration test.
5. Add Step 4 Edge Function, SQL/RLS/Storage, and workflow UI/integration tests; repair the UI-test runner and add Step 4 UI coverage.
6. Schedule failed-audio cleanup and verify the retention policy end to end.
7. Separate or remove obsolete Apple speech and already-started Step 5 code from the Step 4 acceptance baseline.
8. Review, stage, and commit the large untracked implementation so the audited state is reproducible.
