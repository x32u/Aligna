import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type DeleteAccountRequest = {
  confirmSoleMemberWorkspaceDeletion?: boolean;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
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
    return json({ error: "Server configuration is incomplete" }, 500);
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

  let body: DeleteAccountRequest = {};
  try {
    body = await request.json();
  } catch {
    body = {};
  }

  const { data: ownedMemberships, error: ownershipError } =
    await adminClient
      .from("workspace_members")
      .select("workspace_id, workspaces!inner(id, name)")
      .eq("user_id", user.id)
      .eq("role", "owner");

  if (ownershipError) {
    return json({ error: "Could not inspect workspace ownership" }, 500);
  }

  const ownedWorkspaces = ownedMemberships ?? [];
  const blockedWorkspaces: Array<{ id: string; name: string }> = [];
  const soleMemberWorkspaceIDs: string[] = [];

  for (const membership of ownedWorkspaces) {
    const workspaceID = membership.workspace_id;
    const { data: otherMembers, error: membersError } = await adminClient
      .from("workspace_members")
      .select("user_id, role")
      .eq("workspace_id", workspaceID)
      .neq("user_id", user.id);

    if (membersError) {
      return json({ error: "Could not inspect workspace members" }, 500);
    }

    const workspaceRelation = membership.workspaces as
      | { id: string; name: string }
      | Array<{ id: string; name: string }>;
    const workspace = Array.isArray(workspaceRelation)
      ? workspaceRelation[0]
      : workspaceRelation;

    const hasOtherMembers = (otherMembers?.length ?? 0) > 0;
    const hasAnotherOwner =
      otherMembers?.some((member) => member.role === "owner") ?? false;

    if (hasOtherMembers && !hasAnotherOwner) {
      blockedWorkspaces.push({
        id: workspaceID,
        name: workspace?.name ?? "Untitled workspace",
      });
    } else if (!hasOtherMembers) {
      soleMemberWorkspaceIDs.push(workspaceID);
    }
  }

  if (blockedWorkspaces.length > 0) {
    return json(
      {
        error: "Transfer ownership before deleting your account.",
        code: "ownership_transfer_required",
        workspaces: blockedWorkspaces,
      },
      409,
    );
  }

  if (
    soleMemberWorkspaceIDs.length > 0 &&
    body.confirmSoleMemberWorkspaceDeletion !== true
  ) {
    return json(
      {
        error: "Confirm deletion of workspaces where you are the only member.",
        code: "workspace_deletion_confirmation_required",
        workspaceIDs: soleMemberWorkspaceIDs,
      },
      409,
    );
  }

  if (soleMemberWorkspaceIDs.length > 0) {
    const { error } = await adminClient
      .from("workspaces")
      .delete()
      .in("id", soleMemberWorkspaceIDs);
    if (error) {
      return json({ error: "Could not delete owned workspaces" }, 500);
    }
  }

  const { error: meetingsError } = await adminClient
    .from("meetings")
    .delete()
    .eq("organizer_id", user.id);
  if (meetingsError) {
    return json({ error: "Could not delete organized meetings" }, 500);
  }

  const { data: avatarObjects, error: avatarListError } =
    await adminClient.storage.from("avatars").list(user.id);
  if (avatarListError) {
    return json({ error: "Could not inspect avatar storage" }, 500);
  }

  const avatarPaths = (avatarObjects ?? []).map(
    (object) => `${user.id}/${object.name}`,
  );
  if (avatarPaths.length > 0) {
    const { error: avatarDeleteError } = await adminClient.storage
      .from("avatars")
      .remove(avatarPaths);
    if (avatarDeleteError) {
      return json({ error: "Could not delete avatar data" }, 500);
    }
  }

  const { error: deletionError } =
    await adminClient.auth.admin.deleteUser(user.id);
  if (deletionError) {
    return json({ error: "Account deletion could not be completed" }, 500);
  }

  return json({ deleted: true });
});
