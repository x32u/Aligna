# Aligna Post-Meeting AI Test Plan

Use a physical iPhone for recording, network interruption, background, and
multilingual accuracy tests. The simulator uses deterministic audio and cannot
measure microphone or transcription quality.

## Test record

| Field | Result |
| --- | --- |
| Date and tester | |
| Device / iOS version | |
| Aligna build | |
| Meeting duration / file size | |
| Connection changes | |
| Languages actually spoken | |
| Generated title accurate? | |
| Summary accurate? | |
| Unsupported decisions or tasks | |
| Evidence timestamps accurate? | |
| Local recording playable after result/failure? | |
| Temporary Storage objects deleted? | |
| Speaker attribution state (attributed / skipped / failed) | |
| Distinct speakers reported vs. actually present | |
| Interruption tested (call / Siri / route loss) | |
| Elapsed time before and after resume | |
| Audio present from before AND after resume? | |
| Notes | |

Use consented scripts and names. Never place real confidential meeting content
in bug reports or screenshots.

## Required scenarios

1. **English** — record a planning meeting with one decision, one explicitly
   named assignee, and one explicit deadline.
2. **Filipino** — record the equivalent meeting in Filipino. Confirm the
   transcript is not translated and the summary follows the dominant language.
3. **Mixed Taglish** — switch naturally between Filipino and English. Confirm
   names and terms remain intact and the output is not forced into one language.
4. **No explicit assignee or deadline** — confirm both fields remain unassigned
   or null rather than being inferred.
5. **Two or more people speaking** — see "Multi-speaker attribution" below.
   Aligna does attribute speakers; confirm distinct speakers are separated and
   that a failed attribution never presents itself as one identified speaker.
6. **Pause and resume** — verify elapsed time and the retained M4A are correct.
   See "Interruption and resume" below for the interruption path.
7. **Airplane mode at Finish** — confirm the meeting appears immediately with
   “Saved on this iPhone,” then resumes after connectivity returns.
8. **Terminate during upload** — relaunch and confirm the same meeting resumes;
   no duplicate meeting or processing job may be created.
9. **Terminate during processing** — relaunch and confirm database state and
   results continue through Realtime or safe retry.
10. **Duplicate Finish/Retry taps** — confirm controls disable appropriately and
    the stable meeting/idempotency ID prevents duplicate results.
11. **Provider failure** — confirm “We couldn’t finish your notes,” Retry, local
    playback, private diagnostics, and 72-hour temporary-upload retention.
12. **Long recording** — exceed the direct-upload threshold. Confirm every
    chunk stays below 24 MiB, uses a two-second overlap, merged timestamps are
    relative to the full meeting, and overlap text is not duplicated.
13. **Large transcript** — exercise hierarchical summarization and verify the
    final structured result still cites valid original transcript evidence.

## Interruption and resume

`AVAudioSession` interruptions cannot be reproduced in the simulator: there is
no incoming call, no Siri, and no route loss. Every scenario here needs a
physical iPhone.

### Scenarios

1. **Incoming phone call** — start recording, have someone call the device, then
   decline the call.
   Expected: capture pauses on its own, the status reads "Paused", the elapsed
   timer stops advancing, and the waveform settles flat. After declining, tap
   **Resume**: the timer must start advancing again within a second, the status
   returns to "Recording", and the waveform reacts to speech. Keep talking for
   another 20 seconds, then Finish and confirm the saved audio contains **both**
   the pre-call and post-resume speech.
2. **Answer and end the call** — same, but accept the call and talk for 30
   seconds. On return, Resume must behave as above. The elapsed timer must **not**
   include the call duration.
3. **Siri interruption** — hold the side button mid-recording, dismiss Siri,
   then Resume.
4. **Route loss** — start recording, then unplug or power off a connected
   Bluetooth or wired microphone. Expected: automatic pause. Reconnect, then
   Resume.
5. **Resume with the input still unavailable** — pause via route loss, leave the
   microphone disconnected, and tap Resume. Expected: an explicit
   "Recording interrupted" failure — **not** a Resume that appears to work while
   the timer stays frozen. **Finish must still be available** and must save the
   audio recorded before the interruption.
6. **Manual pause and resume** — no interruption involved. Pause, wait 15
   seconds, Resume, speak, Finish. The saved duration must exclude the paused
   window.
7. **Retry after interruption** — force the failure in scenario 5, then tap
   **Try Again**. Expected: a brand-new recording from zero, the previous audio
   discarded. Retry is not a continuation.

### What to watch for

The bug this section exists to catch: the UI reporting "Recording" while the
recorder is stopped, with a frozen timer. If the timer is not advancing, capture
is not running, whatever the status says. Note the elapsed time before and after
every resume.

Automated tests cover the state machine and the view model against a mock
recorder — including a resume that reports success while leaving the recorder
stopped, an unresumable interruption, a media-services reset, and Finish after a
failed resume. They cannot exercise real `AVAudioSession` interruption delivery,
`AVAudioRecorder.record()` behaviour after a real interruption, or whether the
resumed audio actually lands in the M4A. Only the scenarios above establish that.

## Multi-speaker attribution

Speaker attribution runs on-device (FluidAudio offline diarizer) in parallel
with cloud transcription, then matches clusters against enrolled voice profiles.
None of it can be verified in the simulator: `MeetingCaptureDependencies.app()`
supplies mock audio there, and the diarizer models are downloaded and compiled
on first real use.

### Required recording

Record on a physical iPhone, not the simulator.

- **Participants:** two or more people, in the same room, taking clear turns.
- **Duration:** at least 60 seconds, with a minimum of four speaker changes.
- **Content:** each speaker says at least two full sentences per turn; include
  one decision and one explicitly named assignee so analysis is exercised too.
- **Consent:** every speaker must consent to being recorded. Use scripted,
  non-confidential content.

Recordings are gitignored (`*.m4a`) and must not be committed. Keep the file
locally, note the device and build in the test record above, and describe the
turn order in Notes so a later run can be compared.

### Procedure

1. Complete voice enrollment for at least one participant during onboarding, so
   the enrolled/unenrolled distinction is exercised.
2. Record the meeting and tap Finish. Wait for processing to reach "Notes ready".
3. Open the meeting and expand Transcript.
4. With the device attached, filter Console for subsystem `dev.notjc.Aligna`,
   category `SpeakerAttribution`. Each processed meeting logs one
   `Speaker attribution finished` line carrying `state`, `speakers`, `intervals`
   and the cluster keys. A DEBUG build additionally prints the raw interval
   timeline (`raw diarization <start>–<end> → <key>`).

### Expected results

- `state=attributed` and `speakers` equal to the number of people who actually
  spoke.
- Turns alternate between distinct speaker labels. Everything collapsing onto a
  single label is the regression this scenario exists to catch.
- The enrolled participant's turns show their real display name; unenrolled
  speakers show `Speaker 2`, `Speaker 3`, … and never inherit the enrolled name.
- Tapping a speaker label offers participant correction.

### Failure cases to force

- **Diarization model unavailable** — record with airplane mode enabled before
  the diarizer has ever downloaded its models. Expect `state=failed`, the notice
  "Speakers couldn't be identified for this recording. The transcript itself is
  complete.", a transcript that is still complete, labels reading
  "Unidentified speaker", and no speaker-correction menu. A numbered
  "Speaker 1" here is a bug.
- **Silence / no separable speech** — record ambient noise only. Expect
  `state=skipped` and the notice "Speakers weren't identified for this
  recording."

Automated tests cover the decision logic (`SpeakerAttributionResolver`) with
synthetic clusters: alternating speakers, a single speaker, an unmatched cluster
beside an enrolled profile, `noSpeech`, `modelUnavailable`, and a failing status
round-trip. They prove the plumbing and the failure states. They do **not**
establish that FluidAudio separates real voices in real acoustic conditions —
only this scenario does.

## Accessibility and privacy

- Test a small iPhone, largest Dynamic Type sizes, VoiceOver, light mode, dark
  mode, increased contrast, and Reduce Motion.
- Confirm recording requires microphone permission only. No speech-recognition
  permission prompt should appear.
- Confirm capture shows no language, speech-engine, live transcript, model, or
  audio-route diagnostics.
- Confirm the private Storage path begins with the authenticated user ID and
  meeting ID.
- Confirm a second account cannot list, read, replace, or delete the first
  account’s processing audio or meeting result.
- Confirm successful jobs delete every temporary cloud audio chunk.
- Confirm `GROQ_API_KEY`, secret/service-role keys, and raw provider errors are
  absent from the app bundle, client logs, UI, and repository.

## Release gate

Do not claim physical-device, offline, termination, long-recording,
multi-speaker, interruption/resume, or multilingual verification until this
table has observed results. Automated tests cover state mapping, idempotent
identifiers, persistence, speaker-attribution decision logic, capture state
transitions, and output presentation; they do not establish transcription
accuracy, real-voice speaker separation, or real audio-session interruption
behaviour.
