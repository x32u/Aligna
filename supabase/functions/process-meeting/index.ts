import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

const BUCKET = "meeting-processing-audio";
const TRANSCRIPTION_MODEL = "whisper-large-v3";
const ANALYSIS_MODEL = "openai/gpt-oss-120b";
const PROCESSING_VERSION = "aligna-meeting-v3-gpt-oss";
const FAILURE_RETENTION_HOURS = 72;
const MAX_DIRECT_ANALYSIS_CHARACTERS = 72_000;
const ANALYSIS_CHUNK_CHARACTERS = 36_000;

type ProcessingStatus =
  | "queued"
  | "uploading"
  | "transcribing"
  | "preparing_speakers"
  | "diarizing"
  | "matching_speakers"
  | "merging_transcript"
  | "analyzing"
  | "complete"
  | "failed";

type ProcessMeetingRequest = {
  meeting_id?: string;
  idempotency_key?: string;
  action?: "transcribe" | "analyze";
};

type AudioChunk = {
  path: string;
  start_seconds: number;
  end_seconds: number;
};

type TranscriptSegment = {
  start: number;
  end: number;
  text: string;
};

type TranscriptWord = {
  start: number;
  end: number;
  word: string;
};

type TranscriptTurn = {
  stable_speaker_key: string;
  speaker_user_id: string | null;
  speaker_display_name: string;
  start_seconds: number;
  end_seconds: number;
  text: string;
  attribution_source: string;
};

type Evidence = {
  timestamp_seconds: number;
  quote: string;
};

type EvidenceItem = {
  text: string;
  evidence: Evidence;
};

type ActionItem = {
  task: string;
  assignee: string | null;
  assignee_user_id: string | null;
  assignee_display_name: string | null;
  assignment_confidence: number | null;
  evidence_speaker_key: string | null;
  due_date: string | null;
  evidence: Evidence;
};

type MeetingAnalysis = {
  generated_title: string;
  summary: string;
  key_points: EvidenceItem[];
  decisions: EvidenceItem[];
  action_items: ActionItem[];
  open_questions: EvidenceItem[];
  follow_ups: EvidenceItem[];
  languages_detected: string[];
};

type WhisperResponse = {
  text?: string;
  language?: string;
  segments?: Array<{
    start?: number;
    end?: number;
    text?: string;
  }>;
  words?: Array<{
    start?: number;
    end?: number;
    word?: string;
  }>;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json({ message: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return json({ message: "Please sign in again." }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey =
    Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const groqKey = Deno.env.get("GROQ_API_KEY");

  if (!supabaseURL || !publishableKey || !serviceRoleKey) {
    return json({ message: "Meeting processing is not configured." }, 500);
  }

  let body: ProcessMeetingRequest;
  try {
    body = await request.json();
  } catch {
    return json({ message: "The request could not be read." }, 400);
  }

  const meetingID = body.meeting_id?.toLowerCase();
  const idempotencyKey = body.idempotency_key?.toLowerCase();
  const action = body.action ?? "transcribe";
  if (
    !meetingID ||
    !idempotencyKey ||
    !uuidPattern.test(meetingID) ||
    !uuidPattern.test(idempotencyKey)
  ) {
    return json({ message: "The meeting request is invalid." }, 400);
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  EdgeRuntime.waitUntil(cleanupExpiredAudio(adminClient));

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) {
    return json({ message: "Your session is no longer valid." }, 401);
  }

  const { data: meeting, error: meetingError } = await userClient
    .from("meetings")
    .select(
      "id, organizer_id, processing_status, audio_chunks, full_transcript, transcript_segments, transcript_words, languages_detected, detected_language, speaker_processing_skipped",
    )
    .eq("id", meetingID)
    .maybeSingle();

  if (
    meetingError ||
    !meeting ||
    meeting.organizer_id !== user.id
  ) {
    return json({ message: "This meeting is not available." }, 404);
  }

  if (meeting.processing_status === "complete") {
    return json({ accepted: true, status: "complete" });
  }

  if (action === "analyze") {
    if (!groqKey) {
      await recordFailure(
        adminClient,
        meetingID,
        meeting.processing_status as ProcessingStatus,
        "configuration_missing",
        "GROQ_API_KEY is not configured",
      );
      return json(
        { message: "Meeting processing is not configured yet." },
        503,
      );
    }
    if (meeting.processing_status === "analyzing") {
      return json({ accepted: true, status: "analyzing" }, 202);
    }
    if (meeting.processing_status !== "merging_transcript") {
      return json(
        { message: "The speaker-attributed transcript is not ready yet." },
        409,
      );
    }

    const { data: lockedJobs, error: lockError } = await adminClient
      .from("meeting_processing_jobs")
      .update({
        status: "analyzing",
        locked_at: new Date().toISOString(),
      })
      .eq("meeting_id", meetingID)
      .eq("status", "merging_transcript")
      .select("meeting_id");
    if (lockError) {
      return json({ message: "We couldn’t organize this meeting." }, 500);
    }
    if ((lockedJobs?.length ?? 0) === 0) {
      return json({ accepted: true, status: "analyzing" }, 202);
    }

    const task = analyzeStoredMeeting({
      adminClient,
      groqKey,
      meetingID,
    });
    EdgeRuntime.waitUntil(task);
    return json({ accepted: true, status: "analyzing" }, 202);
  }

  const audioChunks = parseAudioChunks(meeting.audio_chunks, user.id, meetingID);
  if (audioChunks.length === 0) {
    return json(
      { message: "The recording has not finished uploading yet." },
      409,
    );
  }

  const { data: claimed, error: claimError } = await adminClient.rpc(
    "claim_meeting_processing_job",
    {
      p_meeting_id: meetingID,
      p_owner_user_id: user.id,
      p_idempotency_key: idempotencyKey,
    },
  );

  if (claimError) {
    console.error("meeting claim failed", {
      meetingID,
      code: claimError.code,
    });
    return json({ message: "We couldn’t queue this meeting." }, 500);
  }

  if (claimed !== true) {
    return json({ accepted: true, status: meeting.processing_status }, 202);
  }

  if (!groqKey) {
    await recordFailure(
      adminClient,
      meetingID,
      "uploading",
      "configuration_missing",
      "GROQ_API_KEY is not configured",
    );
    return json(
      { message: "Meeting processing is not configured yet." },
      503,
    );
  }

  const task = transcribeMeeting({
    adminClient,
    groqKey,
    meetingID,
    audioChunks,
  });
  EdgeRuntime.waitUntil(task);

  return json({ accepted: true, status: "uploading" }, 202);
});

async function transcribeMeeting(input: {
  adminClient: SupabaseClient;
  groqKey: string;
  meetingID: string;
  audioChunks: AudioChunk[];
}) {
  const { adminClient, groqKey, meetingID, audioChunks } = input;

  try {
    await setStage(adminClient, meetingID, "transcribing");

    const detectedLanguages = new Set<string>();
    const allSegments: TranscriptSegment[] = [];
    const allWords: TranscriptWord[] = [];
    let transcript = "";

    for (let index = 0; index < audioChunks.length; index += 1) {
      const chunk = audioChunks[index];
      const { data: audioBlob, error: downloadError } =
        await adminClient.storage.from(BUCKET).download(chunk.path);
      if (downloadError || !audioBlob) {
        throw new ProcessingError(
          "audio_download_failed",
          `Could not download audio chunk ${index}`,
        );
      }

      const result = await transcribeAudio(
        groqKey,
        audioBlob,
        `meeting-${meetingID}-${index}.m4a`,
      );
      if (result.language) {
        detectedLanguages.add(result.language);
      }

      const shifted = (result.segments ?? [])
        .map((segment) => ({
          start: Math.max(0, Number(segment.start ?? 0) + chunk.start_seconds),
          end: Math.max(0, Number(segment.end ?? 0) + chunk.start_seconds),
          text: cleanText(segment.text ?? ""),
        }))
        .filter((segment) => segment.text.length > 0);
      const shiftedWords = (result.words ?? [])
        .map((word) => ({
          start: Math.max(
            0,
            Number(word.start ?? 0) + chunk.start_seconds,
          ),
          end: Math.max(
            0,
            Number(word.end ?? 0) + chunk.start_seconds,
          ),
          word: cleanText(word.word ?? ""),
        }))
        .filter((word) => word.word.length > 0);
      for (const word of shiftedWords) {
        appendDeduplicatedWord(allWords, word);
      }

      if (shifted.length > 0) {
        for (const segment of shifted) {
          appendDeduplicatedSegment(allSegments, segment);
        }
        transcript = allSegments.map((segment) => segment.text).join(" ");
      } else {
        transcript = mergeOverlappingText(
          transcript,
          cleanText(result.text ?? ""),
        );
      }
    }

    transcript = cleanText(transcript);
    if (!transcript) {
      throw new ProcessingError(
        "empty_transcript",
        "The transcription provider returned no text",
      );
    }
    if (allWords.length === 0) {
      throw new ProcessingError(
        "word_timestamps_missing",
        "The transcription provider returned no word timestamps",
      );
    }

    const { error: saveError } = await adminClient
      .from("meetings")
      .update({
        full_transcript: transcript,
        transcript_segments: allSegments,
        transcript_words: allWords,
        detected_language: detectedLanguages.values().next().value ?? null,
        languages_detected: [...detectedLanguages],
        processing_created_at: new Date().toISOString(),
      })
      .eq("id", meetingID);
    if (saveError) {
      throw new ProcessingError(
        "transcript_save_failed",
        saveError.message,
      );
    }
    await setStage(adminClient, meetingID, "merging_transcript");
  } catch (error) {
    const processingError =
      error instanceof ProcessingError
        ? error
        : new ProcessingError("unexpected_failure", String(error));
    await recordFailure(
      adminClient,
      meetingID,
      await currentStage(adminClient, meetingID),
      processingError.code,
      processingError.detail,
    );
  }
}

async function analyzeStoredMeeting(input: {
  adminClient: SupabaseClient;
  groqKey: string;
  meetingID: string;
}) {
  const { adminClient, groqKey, meetingID } = input;
  try {
    await setStage(adminClient, meetingID, "analyzing");

    const { data: meeting, error: meetingError } = await adminClient
      .from("meetings")
      .select(
        "organizer_id, full_transcript, transcript_segments, languages_detected, detected_language, audio_chunks, speaker_processing_skipped",
      )
      .eq("id", meetingID)
      .maybeSingle();
    if (meetingError || !meeting?.full_transcript) {
      throw new ProcessingError(
        "transcript_not_ready",
        meetingError?.message ?? "Stored transcript is missing",
      );
    }

    const { data: storedTurns, error: turnsError } = await adminClient
      .from("meeting_transcript_turns")
      .select(
        "stable_speaker_key, speaker_user_id, speaker_display_name, start_seconds, end_seconds, text, attribution_source",
      )
      .eq("meeting_id", meetingID)
      .order("start_seconds", { ascending: true });
    if (turnsError || !storedTurns || storedTurns.length === 0) {
      throw new ProcessingError(
        "speaker_turns_missing",
        turnsError?.message ?? "Speaker-attributed transcript is missing",
      );
    }

    const segments = Array.isArray(meeting.transcript_segments)
      ? meeting.transcript_segments as TranscriptSegment[]
      : [];
    const providerLanguages = Array.isArray(meeting.languages_detected)
      ? meeting.languages_detected
      : meeting.detected_language
      ? [meeting.detected_language]
      : [];
    const turns = storedTurns as TranscriptTurn[];
    const analysis = await analyzeMeeting(
      groqKey,
      meeting.full_transcript,
      segments,
      providerLanguages,
      turns,
    );

    const completedAt = new Date().toISOString();
    const { error: resultError } = await adminClient
      .from("meetings")
      .update({
        title: analysis.generated_title,
        generated_title: analysis.generated_title,
        summary: analysis.summary,
        key_points: analysis.key_points,
        decisions: analysis.decisions,
        action_items: analysis.action_items,
        open_questions: analysis.open_questions,
        follow_ups: analysis.follow_ups,
        languages_detected: analysis.languages_detected,
        detected_language:
          analysis.languages_detected[0] ??
          meeting.detected_language ??
          null,
        processing_status: "complete",
        processing_completed_at: completedAt,
      })
      .eq("id", meetingID);
    if (resultError) {
      throw new ProcessingError("result_save_failed", resultError.message);
    }

    await adminClient
      .from("meeting_processing_jobs")
      .update({
        status: "complete",
        locked_at: null,
        completed_at: completedAt,
        temporary_audio_delete_after: null,
        last_user_message: null,
      })
      .eq("meeting_id", meetingID);

    await adminClient.rpc("log_meeting_processing_diagnostic", {
      p_meeting_id: meetingID,
      p_stage: "complete",
      p_provider: "groq",
      p_model_version:
        `${PROCESSING_VERSION}:${TRANSCRIPTION_MODEL}:${ANALYSIS_MODEL}`,
      p_error_code: null,
      p_error_detail: null,
    });

    const audioChunks = parseAudioChunksForCleanup(
      meeting.audio_chunks,
      meeting.organizer_id,
      meetingID,
    );
    if (audioChunks.length > 0) {
      const { error: cleanupError } = await adminClient.storage
        .from(BUCKET)
        .remove(audioChunks);
      if (cleanupError) {
        console.error("temporary audio cleanup failed", {
          meetingID,
          code: cleanupError.name,
        });
      } else {
        await adminClient
          .from("meetings")
          .update({ audio_chunks: [] })
          .eq("id", meetingID);
      }
    }
  } catch (error) {
    const processingError =
      error instanceof ProcessingError
        ? error
        : new ProcessingError("unexpected_failure", String(error));
    await recordFailure(
      adminClient,
      meetingID,
      await currentStage(adminClient, meetingID),
      processingError.code,
      processingError.detail,
    );
  }
}

async function transcribeAudio(
  groqKey: string,
  audio: Blob,
  fileName: string,
): Promise<WhisperResponse> {
  const form = new FormData();
  form.append("file", audio, fileName);
  form.append("model", TRANSCRIPTION_MODEL);
  form.append("temperature", "0");
  form.append("response_format", "verbose_json");
  form.append("timestamp_granularities[]", "segment");
  form.append("timestamp_granularities[]", "word");

  const response = await fetch(
    "https://api.groq.com/openai/v1/audio/transcriptions",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${groqKey}` },
      body: form,
    },
  );

  if (!response.ok) {
    throw new ProcessingError(
      "transcription_failed",
      await safeProviderError(response),
    );
  }
  return await response.json() as WhisperResponse;
}

async function analyzeMeeting(
  groqKey: string,
  transcript: string,
  segments: TranscriptSegment[],
  providerLanguages: string[],
  turns: TranscriptTurn[],
): Promise<MeetingAnalysis> {
  let analysisInput = attributedTranscriptWithTimestamps(turns);

  if (analysisInput.length > MAX_DIRECT_ANALYSIS_CHARACTERS) {
    const chunks = splitText(analysisInput, ANALYSIS_CHUNK_CHARACTERS);
    const notes: unknown[] = [];
    for (let index = 0; index < chunks.length; index += 1) {
      notes.push(
        await requestJSON(groqKey, [
          {
            role: "system",
            content:
              "Extract faithful notes from this speaker-attributed transcript portion. Preserve speaker keys, account UUIDs, names, Filipino and English wording, explicit decisions, tasks, dates, questions, and timestamped evidence. Do not infer missing identities, assignees, or deadlines. Return JSON only.",
          },
          {
            role: "user",
            content: JSON.stringify({
              chunk_index: index,
              transcript: chunks[index],
            }),
          },
        ]),
      );
    }
    analysisInput = JSON.stringify({
      instruction:
        "These are ordered notes from one meeting. Synthesize them without inventing facts. Keep the original evidence timestamps.",
      notes,
    });
  }

  const raw = await requestJSON(groqKey, [
    {
      role: "system",
      content: analysisSystemPrompt(),
    },
    {
      role: "user",
      content: JSON.stringify({
        provider_language_hints: providerLanguages,
        transcript: analysisInput,
      }),
    },
  ]);

  return validateAnalysis(raw, transcript, segments, turns);
}

async function requestJSON(
  groqKey: string,
  messages: Array<{ role: string; content: string }>,
): Promise<unknown> {
  const response = await fetch(
    "https://api.groq.com/openai/v1/chat/completions",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${groqKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: ANALYSIS_MODEL,
        temperature: 0,
        response_format: { type: "json_object" },
        messages,
      }),
    },
  );

  if (!response.ok) {
    throw new ProcessingError(
      "analysis_failed",
      await safeProviderError(response),
    );
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw new ProcessingError(
      "analysis_invalid_response",
      "The analysis response contained no JSON content",
    );
  }

  try {
    return JSON.parse(content);
  } catch {
    throw new ProcessingError(
      "analysis_invalid_json",
      "The analysis response was not valid JSON",
    );
  }
}

function analysisSystemPrompt(): string {
  return `
You create factual meeting notes from multilingual transcripts.
Return one JSON object with exactly this shape:
{
  "generated_title": "short title",
  "summary": "concise summary in the meeting's dominant language",
  "key_points": [{"text":"...", "evidence":{"timestamp_seconds":0,"quote":"exact transcript quote"}}],
  "decisions": [{"text":"...", "evidence":{"timestamp_seconds":0,"quote":"exact transcript quote"}}],
  "action_items": [{"task":"...", "assignee":null, "assignee_user_id":null, "assignee_display_name":null, "assignment_confidence":null, "evidence_speaker_key":null, "due_date":null, "evidence":{"timestamp_seconds":0,"quote":"exact transcript quote"}}],
  "open_questions": [{"text":"...", "evidence":{"timestamp_seconds":0,"quote":"exact transcript quote"}}],
  "follow_ups": [{"text":"...", "evidence":{"timestamp_seconds":0,"quote":"exact transcript quote"}}],
  "languages_detected": ["English", "Filipino"]
}
Never invent decisions, people, assignments, deadlines, or dates.
Use null for an assignee or due date unless it is explicit.
Speaker lines contain a stable speaker key, optional verified account UUID, and
display-name snapshot. If a recognized speaker explicitly says “I’ll do this,”
that speaker may be the assignee. A mentioned person is not necessarily the
speaker. Only return assignee_user_id when that exact UUID appears on a
recognized speaker line and the assignment is explicit. Unknown speakers must
not be mapped to accounts. Use evidence_speaker_key from the supporting line.
assignment_confidence is an internal value from 0 to 1, or null when unassigned.
When explicit, keep due_date in the transcript's own wording instead of
calculating or normalizing an unstated calendar date.
Preserve Filipino, English, Taglish, names, and domain terms.
Write the summary naturally in the dominant meeting language.
Every extracted item must include a short exact quote and its transcript timestamp.
Use empty arrays when a category has no supported items.
Do not infer identity from voice similarity; use only the supplied labels.
Return JSON only.
`.trim();
}

function validateAnalysis(
  raw: unknown,
  transcript: string,
  segments: TranscriptSegment[],
  turns: TranscriptTurn[],
): MeetingAnalysis {
  if (!isRecord(raw)) {
    throw new ProcessingError(
      "analysis_schema_invalid",
      "Analysis root was not an object",
    );
  }

  const generatedTitle = requiredText(raw.generated_title, 160);
  const summary = requiredText(raw.summary, 8_000);
  const languages = stringArray(raw.languages_detected, 12, 80);

  return {
    generated_title: generatedTitle,
    summary,
    key_points: validateEvidenceItems(
      raw.key_points,
      transcript,
      segments,
    ),
    decisions: validateEvidenceItems(raw.decisions, transcript, segments),
    action_items: validateActionItems(
      raw.action_items,
      transcript,
      segments,
      turns,
    ),
    open_questions: validateEvidenceItems(
      raw.open_questions,
      transcript,
      segments,
    ),
    follow_ups: validateEvidenceItems(
      raw.follow_ups,
      transcript,
      segments,
    ),
    languages_detected: languages,
  };
}

function validateEvidenceItems(
  value: unknown,
  transcript: string,
  segments: TranscriptSegment[],
): EvidenceItem[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!isRecord(item)) return [];
    const text = optionalText(item.text, 2_000);
    const evidence = validateEvidence(item.evidence, transcript, segments);
    return text && evidence ? [{ text, evidence }] : [];
  }).slice(0, 80);
}

function validateActionItems(
  value: unknown,
  transcript: string,
  segments: TranscriptSegment[],
  turns: TranscriptTurn[],
): ActionItem[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!isRecord(item)) return [];
    const task = optionalText(item.task, 2_000);
    const evidence = validateEvidence(item.evidence, transcript, segments);
    if (!task || !evidence) return [];
    const evidenceTurn = turns.find((turn) =>
      evidence.timestamp_seconds >= turn.start_seconds - 0.25 &&
      evidence.timestamp_seconds <= turn.end_seconds + 0.25
    );
    const requestedUserID = optionalUUID(item.assignee_user_id);
    const recognizedTurn = requestedUserID
      ? turns.find((turn) =>
        turn.speaker_user_id === requestedUserID
      )
      : undefined;
    const evidenceSupportsSelfAssignment =
      Boolean(
        requestedUserID &&
          evidenceTurn?.speaker_user_id === requestedUserID,
      );
    const evidenceSupportsNamedAssignment =
      Boolean(
        recognizedTurn &&
          normalizeForMatch(evidence.quote).includes(
            normalizeForMatch(recognizedTurn.speaker_display_name),
          ),
      );
    const groundedRecognizedTurn =
      evidenceSupportsSelfAssignment || evidenceSupportsNamedAssignment
        ? recognizedTurn
        : undefined;
    const assigneeUserID =
      groundedRecognizedTurn?.speaker_user_id ?? null;
    const assigneeDisplayName =
      groundedRecognizedTurn?.speaker_display_name ??
        groundedNullableText(
          item.assignee_display_name ?? item.assignee,
          transcript,
          160,
        );
    const confidence = assigneeUserID
      ? boundedNumber(item.assignment_confidence, 0, 1)
      : null;
    return [{
      task,
      assignee: assigneeDisplayName,
      assignee_user_id: assigneeUserID,
      assignee_display_name: assigneeDisplayName,
      assignment_confidence: confidence,
      evidence_speaker_key:
        evidenceTurn?.stable_speaker_key ?? null,
      due_date: groundedNullableText(item.due_date, transcript, 80),
      evidence,
    }];
  }).slice(0, 100);
}

function validateEvidence(
  value: unknown,
  transcript: string,
  segments: TranscriptSegment[],
): Evidence | null {
  if (!isRecord(value)) return null;
  const quote = optionalText(value.quote, 600);
  const timestamp = Number(value.timestamp_seconds);
  if (!quote || !Number.isFinite(timestamp) || timestamp < 0) return null;

  const maximum = segments.at(-1)?.end ?? Number.MAX_SAFE_INTEGER;
  if (timestamp > maximum + 5) return null;

  const normalizedQuote = normalizeForMatch(quote);
  const normalizedTranscript = normalizeForMatch(transcript);
  if (
    normalizedQuote.length >= 8 &&
    !normalizedTranscript.includes(normalizedQuote)
  ) {
    return null;
  }
  return { timestamp_seconds: timestamp, quote };
}

function parseAudioChunks(
  value: unknown,
  userID: string,
  meetingID: string,
): AudioChunk[] {
  if (!Array.isArray(value)) return [];
  const requiredPrefix = `${userID}/${meetingID}/`;

  return value.flatMap((item) => {
    if (!isRecord(item)) return [];
    const path = typeof item.path === "string" ? item.path : "";
    const start = Number(item.start_seconds);
    const end = Number(item.end_seconds);
    if (
      !path.startsWith(requiredPrefix) ||
      path.includes("..") ||
      !Number.isFinite(start) ||
      !Number.isFinite(end) ||
      start < 0 ||
      end <= start
    ) {
      return [];
    }
    return [{ path, start_seconds: start, end_seconds: end }];
  }).sort((a, b) => a.start_seconds - b.start_seconds);
}

function parseAudioChunksForCleanup(
  value: unknown,
  ownerUserID: string,
  meetingID: string,
): string[] {
  if (!Array.isArray(value)) return [];
  const requiredPrefix = `${ownerUserID}/${meetingID}/`;
  return value.flatMap((item) => {
    if (!isRecord(item) || typeof item.path !== "string") return [];
    if (
      item.path.includes("..") ||
      !item.path.startsWith(requiredPrefix)
    ) return [];
    return [item.path];
  });
}

function appendDeduplicatedWord(
  target: TranscriptWord[],
  incoming: TranscriptWord,
) {
  const normalizedIncoming = normalizeForMatch(incoming.word);
  if (!normalizedIncoming) return;

  const duplicateIndex = target.findLastIndex((existing) =>
    normalizeForMatch(existing.word) === normalizedIncoming &&
    Math.abs(existing.start - incoming.start) <= 1.2 &&
    Math.abs(existing.end - incoming.end) <= 1.2
  );
  if (duplicateIndex >= 0) {
    const existing = target[duplicateIndex];
    target[duplicateIndex] = {
      start: Math.min(existing.start, incoming.start),
      end: Math.max(existing.end, incoming.end),
      word: existing.word.length >= incoming.word.length
        ? existing.word
        : incoming.word,
    };
    return;
  }
  target.push(incoming);
  target.sort((a, b) => a.start - b.start);
}

function appendDeduplicatedSegment(
  target: TranscriptSegment[],
  incoming: TranscriptSegment,
) {
  const previous = target.at(-1);
  if (!previous) {
    target.push(incoming);
    return;
  }

  const text = mergeOverlappingText(previous.text, incoming.text);
  if (!text || normalizeForMatch(text) === normalizeForMatch(previous.text)) {
    previous.end = Math.max(previous.end, incoming.end);
    return;
  }

  const newOnly = removePrefix(text, previous.text);
  if (!newOnly) return;
  target.push({
    start: Math.max(previous.start, incoming.start),
    end: Math.max(incoming.start, incoming.end),
    text: newOnly,
  });
}

function mergeOverlappingText(existing: string, incoming: string): string {
  const left = cleanText(existing);
  const right = cleanText(incoming);
  if (!left) return right;
  if (!right) return left;

  const leftWords = left.split(/\s+/);
  const rightWords = right.split(/\s+/);
  const maximum = Math.min(40, leftWords.length, rightWords.length);
  let overlap = 0;

  for (let count = maximum; count >= 3; count -= 1) {
    const suffix = normalizeForMatch(leftWords.slice(-count).join(" "));
    const prefix = normalizeForMatch(rightWords.slice(0, count).join(" "));
    if (suffix === prefix) {
      overlap = count;
      break;
    }
  }

  return cleanText(
    `${left} ${rightWords.slice(overlap).join(" ")}`,
  );
}

function removePrefix(combined: string, prefix: string): string {
  const combinedWords = combined.split(/\s+/);
  const prefixWords = prefix.split(/\s+/);
  return combinedWords.slice(prefixWords.length).join(" ");
}

function transcriptWithTimestamps(
  transcript: string,
  segments: TranscriptSegment[],
): string {
  if (segments.length === 0) return transcript;
  return segments.map((segment) =>
    `[${formatTimestamp(segment.start)}] ${segment.text}`
  ).join("\n");
}

function attributedTranscriptWithTimestamps(
  turns: TranscriptTurn[],
): string {
  return turns.map((turn) => {
    const identity = turn.speaker_user_id
      ? `${turn.stable_speaker_key}|${turn.speaker_user_id}|${turn.speaker_display_name}`
      : `${turn.stable_speaker_key}|unknown|${turn.speaker_display_name}`;
    return `[${formatTimestamp(turn.start_seconds)}] ${identity}: ${turn.text}`;
  }).join("\n");
}

function splitText(value: string, size: number): string[] {
  const lines = value.split("\n");
  const chunks: string[] = [];
  let current = "";

  for (const line of lines) {
    if (current.length + line.length + 1 > size && current) {
      chunks.push(current);
      current = "";
    }
    current += `${current ? "\n" : ""}${line}`;
  }
  if (current) chunks.push(current);
  return chunks;
}

async function setStage(
  adminClient: SupabaseClient,
  meetingID: string,
  status: ProcessingStatus,
) {
  const now = new Date().toISOString();
  const { error: meetingError } = await adminClient
    .from("meetings")
    .update({ processing_status: status })
    .eq("id", meetingID);
  const { error: jobError } = await adminClient
    .from("meeting_processing_jobs")
    .update({ status, locked_at: now })
    .eq("meeting_id", meetingID);

  if (meetingError || jobError) {
    throw new ProcessingError(
      "stage_save_failed",
      meetingError?.message ?? jobError?.message ?? "Unknown stage error",
    );
  }
}

async function currentStage(
  adminClient: SupabaseClient,
  meetingID: string,
): Promise<ProcessingStatus> {
  const { data } = await adminClient
    .from("meeting_processing_jobs")
    .select("status")
    .eq("meeting_id", meetingID)
    .maybeSingle();
  return (data?.status as ProcessingStatus | undefined) ?? "failed";
}

async function recordFailure(
  adminClient: SupabaseClient,
  meetingID: string,
  stage: ProcessingStatus,
  code: string,
  detail: string,
) {
  const deleteAfter = new Date(
    Date.now() + FAILURE_RETENTION_HOURS * 60 * 60 * 1_000,
  ).toISOString();

  console.error("meeting processing failed", {
    meetingID,
    stage,
    code,
    detail: detail.slice(0, 500),
  });

  await adminClient
    .from("meetings")
    .update({ processing_status: "failed" })
    .eq("id", meetingID);
  await adminClient
    .from("meeting_processing_jobs")
    .update({
      status: "failed",
      locked_at: null,
      retry_after: new Date(Date.now() + 30_000).toISOString(),
      temporary_audio_delete_after: deleteAfter,
      last_user_message: "We couldn’t finish your notes.",
    })
    .eq("meeting_id", meetingID);
  await adminClient.rpc("log_meeting_processing_diagnostic", {
    p_meeting_id: meetingID,
    p_stage: stage,
    p_provider: "groq",
    p_model_version: `${PROCESSING_VERSION}:${
      stage === "transcribing" ? TRANSCRIPTION_MODEL : ANALYSIS_MODEL
    }`,
    p_error_code: code,
    p_error_detail: detail.slice(0, 8_000),
  });
}

async function safeProviderError(response: Response): Promise<string> {
  const requestID = response.headers.get("x-request-id");
  const body = (await response.text()).slice(0, 2_000);
  return `${response.status}${requestID ? ` ${requestID}` : ""}: ${body}`;
}

async function cleanupExpiredAudio(adminClient: SupabaseClient) {
  const { data: expiredJobs } = await adminClient
    .from("meeting_processing_jobs")
    .select("meeting_id")
    .eq("status", "failed")
    .lt("temporary_audio_delete_after", new Date().toISOString())
    .limit(20);

  for (const job of expiredJobs ?? []) {
    const { data: meeting } = await adminClient
      .from("meetings")
      .select("audio_chunks")
      .eq("id", job.meeting_id)
      .maybeSingle();
    const paths = Array.isArray(meeting?.audio_chunks)
      ? meeting.audio_chunks.flatMap((chunk: unknown) =>
        isRecord(chunk) && typeof chunk.path === "string" &&
          !chunk.path.includes("..")
          ? [chunk.path]
          : []
      )
      : [];

    if (paths.length > 0) {
      await adminClient.storage.from(BUCKET).remove(paths);
    }
    await adminClient
      .from("meetings")
      .update({ audio_chunks: [] })
      .eq("id", job.meeting_id);
    await adminClient
      .from("meeting_processing_jobs")
      .update({ temporary_audio_delete_after: null })
      .eq("meeting_id", job.meeting_id);
  }
}

function requiredText(value: unknown, maximum: number): string {
  const text = optionalText(value, maximum);
  if (!text) {
    throw new ProcessingError(
      "analysis_schema_invalid",
      "A required analysis field was empty",
    );
  }
  return text;
}

function optionalText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const text = cleanText(value);
  return text ? text.slice(0, maximum) : null;
}

function nullableText(value: unknown, maximum: number): string | null {
  return value === null ? null : optionalText(value, maximum);
}

function groundedNullableText(
  value: unknown,
  transcript: string,
  maximum: number,
): string | null {
  const text = nullableText(value, maximum);
  if (!text) return null;
  return normalizeForMatch(transcript).includes(normalizeForMatch(text))
    ? text
    : null;
}

function optionalUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.toLowerCase();
  return uuidPattern.test(normalized) ? normalized : null;
}

function boundedNumber(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  const number = Number(value);
  return Number.isFinite(number) &&
      number >= minimum &&
      number <= maximum
    ? number
    : null;
}

function stringArray(
  value: unknown,
  maximumItems: number,
  maximumLength: number,
): string[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const text = optionalText(item, maximumLength);
    return text ? [text] : [];
  }).slice(0, maximumItems);
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function normalizeForMatch(value: string): string {
  return value
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

function formatTimestamp(value: number): string {
  const total = Math.max(0, Math.floor(value));
  const hours = Math.floor(total / 3_600);
  const minutes = Math.floor((total % 3_600) / 60);
  const seconds = total % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${
      String(seconds).padStart(2, "0")
    }`
    : `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

class ProcessingError extends Error {
  constructor(
    readonly code: string,
    readonly detail: string,
  ) {
    super(detail);
  }
}
