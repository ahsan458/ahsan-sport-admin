import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const respond = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") return respond(405, { error: "Only POST is allowed." });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return respond(500, { error: "Server environment is not configured." });
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return respond(401, { error: "Authentication is required." });
    const accessToken = authorization.slice("Bearer ".length);

    const callerClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } },
    });
    const { data: callerData, error: callerError } = await callerClient.auth.getUser(accessToken);
    if (callerError || !callerData.user) return respond(401, { error: "Your session is invalid. Please sign in again." });

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from("profiles").select("role, active").eq("id", callerData.user.id).maybeSingle();
    if (callerProfileError || !callerProfile || callerProfile.role !== "owner" || callerProfile.active === false) {
      return respond(403, { error: "Only the active system owner can unblock admin accounts." });
    }

    const body = await req.json().catch(() => ({}));
    const staffId = typeof body.staff_id === "string" ? body.staff_id.trim() : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(staffId)) {
      return respond(400, { error: "A valid admin account ID is required." });
    }
    if (staffId === callerData.user.id) return respond(400, { error: "The owner account cannot be changed here." });

    const { data: target, error: targetError } = await adminClient
      .from("profiles").select("id, role, active").eq("id", staffId).maybeSingle();
    if (targetError || !target) return respond(404, { error: "Admin account was not found." });
    if (target.role !== "admin") return respond(403, { error: "Only admin accounts can be unblocked with this action." });
    if (target.active !== false) return respond(200, { success: true, message: "This admin account is already active." });

    const { error: unbanError } = await adminClient.auth.admin.updateUserById(staffId, { ban_duration: "none" });
    if (unbanError) return respond(502, { error: "The sign-in ban could not be removed: " + unbanError.message });

    const { error: profileError } = await adminClient.from("profiles").update({ active: true }).eq("id", staffId);
    if (profileError) {
      await adminClient.auth.admin.updateUserById(staffId, { ban_duration: "876000h" });
      return respond(502, { error: "The sign-in ban was removed, but the profile could not be activated. The account was re-blocked; contact the system owner." });
    }

    return respond(200, { success: true, message: "Admin account unblocked and marked active." });
  } catch (error) {
    return respond(500, { error: error instanceof Error ? error.message : "Unexpected server error." });
  }
});
