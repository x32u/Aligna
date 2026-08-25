import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

type VoiceAction = "enroll" | "status" | "delete" | "candidates";

type VoiceRequest = {
  action?: VoiceAction;
  meeting_id?: string;
  embedding?: number[];
  embedding_dimension?: number;
  model_provider?: string;
  model_version?: string;
  package_version?: string;
  consented_at?: string;
  status?: string;
};

type StoredVoiceProfile = {
  user_id: string;
  encrypted_embedding: string;
  encryption_nonce: string;
  embedding_dimension: number;
  model_provider: string;
  model_version: string;
  package_version: string;
  encryption_key_version: number;
};

const MAX_CANDIDATES = 16;
const MAX_CANDIDATE_REQUESTS_PER_MINUTE = 12;
const KEY_VERSION = 1;
const allowedStatuses = new Set([
  "not_started",
  "in_progress",
  "enrolled",
  "skipped",
  "needs_reenrollment",
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
  const encryptionSecret = Deno.env.get("VOICE_PROFILE_ENCRYPTION_KEY");

  if (
    !supabaseURL ||
    !publishableKey ||
    !serviceRoleKey ||
    !encryptionSecret
  ) {
    return json({ error: "Voice recognition is not configured" }, 503);
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) {
    return json({ error: "Your session is no longer valid" }, 401);
  }

  let body: VoiceRequest;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }

  try {
    const key = await importEncryptionKey(encryptionSecret);
    switch (body.action) {
      case "enroll":
        return await enroll(adminClient, key, user, body);
      case "status":
        return await updateStatus(adminClient, user.id, body.status);
      case "delete":
        return await deleteProfile(adminClient, user.id);
      case "candidates":
        return await candidates(
          adminClient,
          key,
          user.id,
          body.meeting_id,
          body.model_provider,
          body.model_version,
          body.embedding_dimension,
        );
      default:
        return json({ error: "Unsupported action" }, 400);
    }
  } catch (error) {
    // Never include vectors, ciphertext, decrypted data, or keys in logs.
    console.error("voice profile request failed", {
      action: body.action ?? "unknown",
      requester: user.id,
      code: error instanceof VoiceFunctionError
        ? error.code
        : "unexpected_failure",
    });
    if (error instanceof VoiceFunctionError) {
      return json({ error: error.userMessage }, error.status);
    }
    return json({ error: "Voice recognition couldn’t finish this request" }, 500);
  }
});

async function enroll(
  admin: SupabaseClient,
  key: CryptoKey,
  user: {
    id: string;
    email_confirmed_at?: string | null;
    confirmed_at?: string | null;
  },
  body: VoiceRequest,
): Promise<Response> {
  if (!user.email_confirmed_at && !user.confirmed_at) {
    throw new VoiceFunctionError(
      "email_unverified",
      "Verify your email before setting up voice recognition.",
      403,
    );
  }

  const embedding = validateEmbedding(
    body.embedding,
    body.embedding_dimension,
  );
  const modelProvider = requiredText(body.model_provider, 80);
  const modelVersion = requiredText(body.model_version, 160);
  const packageVersion = requiredText(body.package_version, 80);
  const consentedAt = validDate(body.consented_at);
  const sealed = await encryptEmbedding(key, embedding);
  const now = new Date().toISOString();

  const { error } = await admin.rpc("service_voice_profile_enroll", {
    p_user_id: user.id,
    p_encrypted_embedding: sealed.ciphertext,
    p_encryption_nonce: sealed.nonce,
    p_embedding_dimension: embedding.length,
    p_model_provider: modelProvider,
    p_model_version: modelVersion,
    p_package_version: packageVersion,
    p_consented_at: consentedAt,
    p_enrolled_at: now,
    p_encryption_key_version: KEY_VERSION,
  });
  if (error) {
    throw new VoiceFunctionError(
      "profile_save_failed",
      "Voice recognition couldn’t save your profile.",
      500,
    );
  }
  return json({ success: true });
}

async function updateStatus(
  admin: SupabaseClient,
  userID: string,
  requestedStatus?: string,
): Promise<Response> {
  if (!requestedStatus || !allowedStatuses.has(requestedStatus)) {
    throw new VoiceFunctionError(
      "invalid_status",
      "Voice recognition couldn’t update this setting.",
      400,
    );
  }
  const { data: didUpdate, error } = await admin.rpc(
    "service_voice_enrollment_status_update",
    {
      p_user_id: userID,
      p_status: requestedStatus,
    },
  );
  if (error) {
    throw new VoiceFunctionError(
      "status_update_failed",
      "Voice recognition couldn’t update this setting.",
      500,
    );
  }
  if (!didUpdate) {
    throw new VoiceFunctionError(
      "profile_missing",
      "Set up your voice before turning on voice recognition.",
      409,
    );
  }
  return json({ success: true });
}

async function deleteProfile(
  admin: SupabaseClient,
  userID: string,
): Promise<Response> {
  const { error } = await admin.rpc("service_voice_profile_delete", {
    p_user_id: userID,
  });
  if (error) {
    throw new VoiceFunctionError(
      "profile_delete_failed",
      "Voice recognition couldn’t delete your profile.",
      500,
    );
  }
  return json({ success: true });
}

async function candidates(
  admin: SupabaseClient,
  key: CryptoKey,
  requesterID: string,
  meetingID?: string,
  compatibleProvider?: string,
  compatibleModelVersion?: string,
  compatibleDimension?: number,
): Promise<Response> {
  if (!meetingID) {
    throw new VoiceFunctionError(
      "meeting_required",
      "Choose a meeting before recognizing speakers.",
      400,
    );
  }
  await enforceRateLimit(admin, requesterID);

  const { data: meeting, error: meetingError } = await admin
    .from("meetings")
    .select("id, organizer_id, workspace_id")
    .eq("id", meetingID)
    .maybeSingle();
  if (meetingError || !meeting) {
    throw new VoiceFunctionError(
      "meeting_not_found",
      "This meeting is no longer available.",
      404,
    );
  }

  const { data: participants, error: participantError } = await admin
    .from("meeting_participants")
    .select("user_id")
    .eq("meeting_id", meetingID);
  if (participantError) {
    throw new VoiceFunctionError(
      "participant_lookup_failed",
      "Aligna couldn’t prepare meeting participants.",
      500,
    );
  }

  const participantIDs = (participants ?? []).map((row) => row.user_id);
  const requesterIsParticipant = participantIDs.includes(requesterID);
  let requesterIsWorkspaceMember = false;
  if (meeting.workspace_id) {
    const { data: membership } = await admin
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", meeting.workspace_id)
      .eq("user_id", requesterID)
      .maybeSingle();
    requesterIsWorkspaceMember = Boolean(membership);
  }
  if (
    meeting.organizer_id !== requesterID &&
    !requesterIsParticipant &&
    !requesterIsWorkspaceMember
  ) {
    throw new VoiceFunctionError(
      "meeting_access_denied",
      "You don’t have permission to recognize speakers in this meeting.",
      403,
    );
  }

  const candidateIDs = [
    ...new Set([meeting.organizer_id, ...participantIDs]),
  ].slice(0, MAX_CANDIDATES);

  const { data: profiles, error: profileError } = await admin
    .from("profiles")
    .select("id, display_name, avatar_path")
    .in("id", candidateIDs);
  if (profileError) {
    throw new VoiceFunctionError(
      "candidate_lookup_failed",
      "Aligna couldn’t prepare meeting participants.",
      500,
    );
  }

  const { data: allVoiceProfiles, error: voiceError } = await admin.rpc(
    "service_voice_profiles_for_candidates",
    { p_user_ids: candidateIDs },
  );
  if (voiceError) {
    throw new VoiceFunctionError(
      "voice_candidate_lookup_failed",
      "Aligna couldn’t prepare voice recognition.",
      500,
    );
  }
  const encryptedProfiles = (allVoiceProfiles ?? [])
    .filter((profile) =>
      (!compatibleProvider ||
        profile.model_provider === compatibleProvider) &&
      (!compatibleModelVersion ||
        profile.model_version === compatibleModelVersion) &&
      (!compatibleDimension ||
        profile.embedding_dimension === compatibleDimension)
    );
  const incompatibleIDs = (allVoiceProfiles ?? [])
    .filter((profile) =>
      !encryptedProfiles.some(
        (compatible) => compatible.user_id === profile.user_id,
      )
    )
    .map((profile) => profile.user_id);
  if (incompatibleIDs.length > 0) {
    await admin.rpc("service_voice_profiles_mark_reenrollment", {
      p_user_ids: incompatibleIDs,
    });
  }

  const profileByID = new Map(
    (profiles ?? []).map((profile) => [profile.id, profile]),
  );
  const output = [];
  for (const stored of encryptedProfiles as StoredVoiceProfile[]) {
    if (stored.encryption_key_version !== KEY_VERSION) {
      continue;
    }
    const profile = profileByID.get(stored.user_id);
    if (!profile) continue;
    const embedding = await decryptEmbedding(key, stored);
    if (
      embedding.length !== stored.embedding_dimension ||
      !isNormalized(embedding)
    ) {
      continue;
    }
    output.push({
      user_id: stored.user_id,
      display_name: profile.display_name,
      avatar_path: profile.avatar_path,
      embedding,
      embedding_dimension: stored.embedding_dimension,
      model_provider: stored.model_provider,
      model_version: stored.model_version,
      package_version: stored.package_version,
    });
  }

  await audit(admin, requesterID, meetingID, "candidates", output.length);
  return json({ candidates: output });
}

function validateEmbedding(
  value?: number[],
  dimension?: number,
): number[] {
  if (
    !Array.isArray(value) ||
    !Number.isInteger(dimension) ||
    dimension! < 64 ||
    dimension! > 2048 ||
    value.length !== dimension ||
    value.some((item) => !Number.isFinite(item) || Math.abs(item) > 1)
  ) {
    throw new VoiceFunctionError(
      "invalid_embedding",
      "Aligna couldn’t create a reliable voice profile.",
      400,
    );
  }
  if (!isNormalized(value)) {
    throw new VoiceFunctionError(
      "unnormalized_embedding",
      "Aligna couldn’t create a reliable voice profile.",
      400,
    );
  }
  return value;
}

function isNormalized(value: number[]): boolean {
  const magnitude = Math.sqrt(
    value.reduce((sum, item) => sum + item * item, 0),
  );
  return Number.isFinite(magnitude) && magnitude >= 0.98 && magnitude <= 1.02;
}

async function importEncryptionKey(secret: string): Promise<CryptoKey> {
  const bytes = fromBase64(secret);
  if (bytes.length !== 32) {
    throw new VoiceFunctionError(
      "invalid_encryption_key",
      "Voice recognition is not configured.",
      503,
    );
  }
  return await crypto.subtle.importKey(
    "raw",
    bytes,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

async function encryptEmbedding(
  key: CryptoKey,
  embedding: number[],
): Promise<{ ciphertext: string; nonce: string }> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(embedding));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    plaintext,
  );
  return {
    ciphertext: toBase64(new Uint8Array(ciphertext)),
    nonce: toBase64(nonce),
  };
}

async function decryptEmbedding(
  key: CryptoKey,
  stored: StoredVoiceProfile,
): Promise<number[]> {
  try {
    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: fromBase64(stored.encryption_nonce),
      },
      key,
      fromBase64(stored.encrypted_embedding),
    );
    const decoded = JSON.parse(
      new TextDecoder().decode(plaintext),
    );
    if (!Array.isArray(decoded) || decoded.some((v) => !Number.isFinite(v))) {
      throw new Error("invalid vector");
    }
    return decoded;
  } catch {
    throw new VoiceFunctionError(
      "profile_decryption_failed",
      "A voice profile needs to be recorded again.",
      409,
    );
  }
}

async function enforceRateLimit(
  admin: SupabaseClient,
  requesterID: string,
) {
  const since = new Date(Date.now() - 60_000).toISOString();
  const { data: count, error } = await admin.rpc(
    "service_voice_candidate_request_count",
    {
      p_requester_user_id: requesterID,
      p_since: since,
    },
  );
  if (error) {
    throw new VoiceFunctionError(
      "rate_limit_check_failed",
      "Voice recognition couldn’t start right now.",
      500,
    );
  }
  if ((count ?? 0) >= MAX_CANDIDATE_REQUESTS_PER_MINUTE) {
    throw new VoiceFunctionError(
      "rate_limited",
      "Wait a moment before trying voice recognition again.",
      429,
    );
  }
}

async function audit(
  admin: SupabaseClient,
  requesterID: string,
  meetingID: string | null,
  action: string,
  candidateCount: number,
) {
  await admin.rpc("service_voice_profile_audit", {
    p_requester_user_id: requesterID,
    p_meeting_id: meetingID,
    p_action: action,
    p_candidate_count: candidateCount,
  });
}

function requiredText(value: unknown, maximum: number): string {
  if (typeof value !== "string") {
    throw new VoiceFunctionError(
      "invalid_model_metadata",
      "Aligna couldn’t create a reliable voice profile.",
      400,
    );
  }
  const text = value.trim();
  if (!text || text.length > maximum) {
    throw new VoiceFunctionError(
      "invalid_model_metadata",
      "Aligna couldn’t create a reliable voice profile.",
      400,
    );
  }
  return text;
}

function validDate(value?: string): string {
  if (!value) {
    throw new VoiceFunctionError(
      "consent_required",
      "Review the privacy explanation before continuing.",
      400,
    );
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.getTime() > Date.now() + 60_000) {
    throw new VoiceFunctionError(
      "invalid_consent_time",
      "Review the privacy explanation before continuing.",
      400,
    );
  }
  return date.toISOString();
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

class VoiceFunctionError extends Error {
  constructor(
    readonly code: string,
    readonly userMessage: string,
    readonly status: number,
  ) {
    super(code);
  }
}
