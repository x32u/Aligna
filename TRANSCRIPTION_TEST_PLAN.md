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
5. **Two people speaking** — confirm Aligna does not add speaker labels, voice
   identity, or diarization claims.
6. **Pause and resume** — verify elapsed time and the retained M4A are correct.
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

Do not claim physical-device, offline, termination, long-recording, or
multilingual verification until this table has observed results. Automated
tests cover state mapping, idempotent identifiers, persistence, and output
presentation; they do not establish transcription accuracy.
