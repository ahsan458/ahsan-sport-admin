import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const respond = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") {
    return respond(405, { error: "Only POST is allowed." });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return respond(500, { error: "Server environment is not configured." });
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return respond(401, { error: "Authentication is required." });
    }
    const accessToken = authorization.slice("Bearer ".length);

    const callerClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } },
    });
    const { data: callerData, error: callerError } = await callerClient.auth.getUser(accessToken);
    if (callerError || !callerData.user) {
      return respond(401, { error: "Your session is invalid. Please sign in again." });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from("profiles")
      .select("role, active")
      .eq("id", callerData.user.id)
      .maybeSingle();

    if (callerProfileError || !callerProfile || callerProfile.role !== "owner" || callerProfile.active === false) {
      return respond(403, { error: "Only the active system owner can block staff accounts." });
    }

    const body = await req.json().catch(() => ({}));
    const staffId = typeof body.staff_id === "string" ? body.staff_id.trim() : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(staffId)) {
      return respond(400, { error: "A valid staff account ID is required." });
    }
    if (staffId === callerData.user.id) {
      return respond(400, { error: "The owner account cannot be blocked here." });
    }

    const { data: target, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role, active")
      .eq("id", staffId)
      .maybeSingle();

    if (targetError || !target) {
      return respond(404, { error: "Staff account was not found." });
    }
    if (target.role !== "admin") {
      return respond(403, { error: "Only admin accounts can be blocked with this action." });
    }
    if (target.active === false) {
      return respond(200, { success: true, message: "This account is already inactive." });
    }

    // Supabase documents 876000h as a 100-year ban.
    const { error: banError } = await adminClient.auth.admin.updateUserById(staffId, {
      ban_duration: "876000h",
    });
    if (banError) {
      return respond(502, { error: "The sign-in ban could not be applied: " + banError.message });
    }

    const { error: profileError } = await adminClient
      .from("profiles")
      .update({ active: false })
      .eq("id", staffId);

    if (profileError) {
      return respond(502, {
        error: "The sign-in ban was applied, but the profile status update failed. Contact the system owner.",
      });
    }

    return respond(200, { success: true, message: "Staff account blocked and marked inactive." });
  } catch (error) {
    return respond(500, {
      error: error instanceof Error ? error.message : "Unexpected server error.",
    });
  }
});
