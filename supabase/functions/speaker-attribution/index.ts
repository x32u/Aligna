import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

type Interval = {
  stable_speaker_key?: string;
  start_seconds?: number;
  end_seconds?: number;
};

type Turn = {
  id?: string;
  stable_speaker_key?: string;
  speaker_user_id?: string | null;
  speaker_display_name?: string;
  start_seconds?: number;
  end_seconds?: number;
  text?: string;
  attribution_confidence?: number | null;
  attribution_source?: string;
};

type AttributionRequest = {
  meeting_id?: string;
  model_version?: string | null;
  skipped?: boolean;
  status?: string;
  intervals?: Interval[];
  turns?: Turn[];
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const sources = new Set([
  "voice_profile",
  "anonymous",
  "ambiguous",
]);
const speakerStatuses = new Set([
  "preparing_speakers",
  "diarizing",
  "matching_speakers",
  "merging_transcript",
  "failed",
]);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey =
    Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !publishableKey || !serviceRoleKey) {
    return json({ error: "Speaker processing is not configured" }, 503);
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) {
    return json({ error: "Your session is no longer valid" }, 401);
  }

  let body: AttributionRequest;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  const meetingID = body.meeting_id?.toLowerCase();
  if (!meetingID || !uuidPattern.test(meetingID)) {
    return json({ error: "Invalid meeting" }, 400);
  }

  const { data: meeting, error: meetingError } = await admin
    .from("meetings")
    .select(
      "id, organizer_id, started_at, ended_at, processing_status, transcript_words",
    )
    .eq("id", meetingID)
    .maybeSingle();
  if (
    meetingError ||
    !meeting ||
    meeting.organizer_id !== user.id
  ) {
    return json({ error: "This meeting is not available" }, 404);
  }
  if (
    body.status &&
    speakerStatuses.has(body.status) &&
    !Array.isArray(body.turns)
  ) {
    const { error: statusError } = await admin
      .from("meetings")
      .update({ speaker_processing_status: body.status })
      .eq("id", meetingID);
    return statusError
      ? json({ error: "Could not update speaker processing" }, 500)
      : json({ success: true });
  }
  if (
    meeting.processing_status !== "merging_transcript" &&
    meeting.processing_status !== "analyzing"
  ) {
    return json({ error: "The transcript is not ready yet" }, 409);
  }
  if (
    !Array.isArray(meeting.transcript_words) ||
    meeting.transcript_words.length === 0
  ) {
    if (!body.status || !speakerStatuses.has(body.status)) {
      return json({ error: "The transcript is not ready yet" }, 409);
    }
  }

  const { data: participantRows, error: participantsError } = await admin
    .from("meeting_participants")
    .select("user_id")
    .eq("meeting_id", meetingID);
  if (participantsError) {
    return json({ error: "Could not verify participants" }, 500);
  }
  const candidateIDs = new Set([
    meeting.organizer_id,
    ...(participantRows ?? []).map((row) => row.user_id),
  ]);

  const maximumDuration = meeting.started_at && meeting.ended_at
    ? Math.max(
      0,
      (new Date(meeting.ended_at).getTime() -
        new Date(meeting.started_at).getTime()) / 1000,
    ) + 5
    : Number.MAX_SAFE_INTEGER;

  const turns = validateTurns(
    body.turns,
    meetingID,
    candidateIDs,
    maximumDuration,
  );
  const intervals = validateIntervals(
    body.intervals,
    maximumDuration,
  );
  if (turns.length === 0) {
    return json({ error: "No transcript turns were provided" }, 400);
  }

  const { error: deleteError } = await admin
    .from("meeting_transcript_turns")
    .delete()
    .eq("meeting_id", meetingID);
  if (deleteError) {
    return json({ error: "Could not replace transcript speakers" }, 500);
  }

  const { error: insertError } = await admin
    .from("meeting_transcript_turns")
    .insert(turns);
  if (insertError) {
    return json({ error: "Could not save transcript speakers" }, 500);
  }

  const { error: updateError } = await admin
    .from("meetings")
    .update({
      diarization_timeline: intervals,
      speaker_processing_skipped: body.skipped === true,
      speaker_processing_status: body.skipped === true
        ? "skipped"
        : "complete",
      voice_model_version: body.skipped === true
        ? null
        : cleanText(body.model_version, 160),
      processing_status: "merging_transcript",
    })
    .eq("id", meetingID);
  if (updateError) {
    return json({ error: "Could not finish transcript speakers" }, 500);
  }

  return json({ success: true, turn_count: turns.length });
});

function validateTurns(
  value: Turn[] | undefined,
  meetingID: string,
  candidateIDs: Set<string>,
  maximumDuration: number,
) {
  if (!Array.isArray(value) || value.length > 20_000) return [];

  return value.flatMap((turn) => {
    const id = turn.id?.toLowerCase();
    const key = cleanText(turn.stable_speaker_key, 80);
    const displayName = cleanText(turn.speaker_display_name, 120);
    const text = cleanText(turn.text, 20_000);
    const start = Number(turn.start_seconds);
    const end = Number(turn.end_seconds);
    const source = turn.attribution_source ?? "anonymous";
    const userID = turn.speaker_user_id?.toLowerCase() ?? null;
    const confidence = turn.attribution_confidence == null
      ? null
      : Number(turn.attribution_confidence);

    if (
      !id ||
      !uuidPattern.test(id) ||
      !key ||
      !displayName ||
      !text ||
      !Number.isFinite(start) ||
      !Number.isFinite(end) ||
      start < 0 ||
      end < start ||
      end > maximumDuration ||
      !sources.has(source) ||
      (userID !== null &&
        (!uuidPattern.test(userID) || !candidateIDs.has(userID))) ||
      (confidence !== null &&
        (!Number.isFinite(confidence) ||
          confidence < -1 ||
          confidence > 1))
    ) {
      return [];
    }
    return [{
      id,
      meeting_id: meetingID,
      stable_speaker_key: key,
      speaker_user_id: userID,
      speaker_display_name: displayName,
      start_seconds: start,
      end_seconds: end,
      text,
      attribution_confidence: confidence,
      attribution_source: source,
      original_speaker_user_id: userID,
      original_speaker_display_name: displayName,
      original_attribution_confidence: confidence,
      original_attribution_source: source,
    }];
  });
}

function validateIntervals(
  value: Interval[] | undefined,
  maximumDuration: number,
) {
  if (!Array.isArray(value) || value.length > 50_000) return [];
  return value.flatMap((interval) => {
    const key = cleanText(interval.stable_speaker_key, 80);
    const start = Number(interval.start_seconds);
    const end = Number(interval.end_seconds);
    if (
      !key ||
      !Number.isFinite(start) ||
      !Number.isFinite(end) ||
      start < 0 ||
      end < start ||
      end > maximumDuration
    ) {
      return [];
    }
    return [{
      stable_speaker_key: key,
      start_seconds: start,
      end_seconds: end,
    }];
  });
}

function cleanText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const text = value.replace(/\s+/g, " ").trim();
  return text ? text.slice(0, maximum) : null;
}
