// ============================================================
//  CleanIT — Accept Request Edge Function
//  Supabase Edge Function (Deno runtime)
//
//  Handles the "Fastest Finger First" race condition safely
//  by delegating to the accept_request() PostgreSQL RPC function
//  which uses SELECT ... FOR UPDATE SKIP LOCKED.
// ============================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9.0.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ── CORS Headers ──
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Authenticate the caller ──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(401, {
        success: false,
        code: "UNAUTHORIZED",
        message: "Missing Authorization header.",
      });
    }

    const supabaseAuth = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const {
      data: { user },
      error: authError,
    } = await supabaseAuth.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return jsonResponse(401, {
        success: false,
        code: "UNAUTHORIZED",
        message: "Invalid or expired token.",
      });
    }

    // ── 2. Get the cleaner's internal user ID ──
    const { data: cleanerUser, error: userError } = await supabaseAuth
      .from("users")
      .select("id, role")
      .eq("auth_id", user.id)
      .single();

    if (userError || !cleanerUser) {
      return jsonResponse(404, {
        success: false,
        code: "USER_NOT_FOUND",
        message: "User profile not found.",
      });
    }

    if (cleanerUser.role !== "cleaner") {
      return jsonResponse(403, {
        success: false,
        code: "FORBIDDEN",
        message: "Only cleaners can accept requests.",
      });
    }

    // ── 3. Parse request body ──
    const { request_id } = await req.json();
    if (!request_id) {
      return jsonResponse(400, {
        success: false,
        code: "INVALID_REQUEST",
        message: "request_id is required.",
      });
    }

    // ── 4. Call the atomic RPC function ──
    //    This is where the magic happens:
    //    - Locks the row with FOR UPDATE SKIP LOCKED
    //    - If another cleaner already locked it, returns instantly with "already taken"
    //    - If this cleaner wins, atomically updates status + creates assignment
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: result, error: rpcError } = await supabaseAdmin.rpc(
      "accept_request",
      {
        p_request_id: request_id,
        p_cleaner_id: cleanerUser.id,
      }
    );

    if (rpcError) {
      console.error("RPC error:", rpcError);
      return jsonResponse(500, {
        success: false,
        code: "INTERNAL_ERROR",
        message: "Failed to process acceptance.",
      });
    }

    // ── 5. Handle the result ──
    if (!result.success) {
      return jsonResponse(409, result);
    }

    // ── 6. Send FCM notification to the student ──
    //    Fetch the student's FCM token and notify them
    const { data: request } = await supabaseAdmin
      .from("requests")
      .select("student_id, is_urgent, notes")
      .eq("id", request_id)
      .single();

    if (request) {
      const { data: student } = await supabaseAdmin
        .from("users")
        .select("fcm_token, name")
        .eq("id", request.student_id)
        .single();

      if (student?.fcm_token) {
        await sendFCM(student.fcm_token, {
          title: "Cleaner Assigned! 🧹",
          body: `A cleaner has accepted your request and is on the way.`,
          data: { type: "REQUEST_ACCEPTED", request_id },
        });
      }
    }

    return jsonResponse(200, result);
  } catch (err) {
    console.error("Unhandled error:", err);
    return jsonResponse(500, {
      success: false,
      code: "INTERNAL_ERROR",
      message: "An unexpected error occurred.",
    });
  }
});

// ── Helpers ──

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sendFCM(
  token: string,
  notification: { title: string; body: string; data?: Record<string, string> }
) {
  try {
    const serviceAccountRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!serviceAccountRaw) {
      console.error("Missing FCM_SERVICE_ACCOUNT");
      return;
    }
    const fcmCredentials = JSON.parse(serviceAccountRaw);

    const auth = new GoogleAuth({
      credentials: {
        client_email: fcmCredentials.client_email,
        private_key: fcmCredentials.private_key,
      },
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const client = await auth.getClient();
    const accessTokenObj = await client.getAccessToken();
    const projectId = fcmCredentials.project_id;

    const payload = {
      message: {
        token: token,
        notification: {
          title: notification.title,
          body: notification.body,
        },
        android: {
          notification: {
            sound: "default",
          },
        },
        data: notification.data || {},
      },
    };

    await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessTokenObj.token}`,
      },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    // FCM failures are non-blocking — log but don't crash the endpoint
    console.error("FCM send failed:", err);
  }
}
