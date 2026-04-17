// ============================================================
//  CleanIT — Create Request Edge Function
//  Supabase Edge Function (Deno runtime)
//
//  Creates a new cleaning request and broadcasts FCM
//  notifications to ALL on-duty cleaners.
// ============================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9.0.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Authenticate ──
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(401, {
        success: false,
        code: "UNAUTHORIZED",
        message: "Missing Authorization header.",
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return jsonResponse(401, {
        success: false,
        code: "UNAUTHORIZED",
        message: "Invalid or expired token.",
      });
    }

    // ── 2. Get student profile ──
    const { data: studentUser } = await supabase
      .from("users")
      .select("id, role, block, room_number, name")
      .eq("auth_id", user.id)
      .single();

    if (!studentUser || studentUser.role !== "student") {
      return jsonResponse(403, {
        success: false,
        code: "FORBIDDEN",
        message: "Only students can create cleaning requests.",
      });
    }

    // ── 3. Parse request body ──
    const { is_sweeping, is_mopping, is_urgent, notes } = await req.json();

    if (!is_sweeping && !is_mopping) {
      return jsonResponse(400, {
        success: false,
        code: "NO_TASKS_SELECTED",
        message: "Please select at least one task (sweeping or mopping).",
      });
    }

    // ── 4. Insert the request ──
    //    The unique index idx_one_active_request_per_student will
    //    automatically reject this if the student already has an active request.
    const { data: newRequest, error: insertError } = await supabase
      .from("requests")
      .insert({
        student_id: studentUser.id,
        is_sweeping: is_sweeping || false,
        is_mopping: is_mopping || false,
        is_urgent: is_urgent || false,
        notes: notes?.trim() || null,
      })
      .select()
      .single();

    if (insertError) {
      // Check for unique constraint violation (active request exists)
      if (insertError.code === "23505") {
        return jsonResponse(409, {
          success: false,
          code: "ACTIVE_REQUEST_EXISTS",
          message: "You already have an active cleaning request. Please wait for it to complete.",
        });
      }
      console.error("Insert error:", insertError);
      return jsonResponse(500, {
        success: false,
        code: "INTERNAL_ERROR",
        message: "Failed to create request.",
      });
    }

    // ── 5. Broadcast FCM to ALL on-duty cleaners ──
    const { data: cleaners } = await supabase
      .from("users")
      .select("fcm_token")
      .eq("role", "cleaner")
      .eq("is_on_duty", true)
      .not("fcm_token", "is", null);

    if (cleaners && cleaners.length > 0) {
      const tokens = cleaners
        .map((c: { fcm_token: string }) => c.fcm_token)
        .filter(Boolean);

      if (tokens.length > 0) {
        // Build task description
        const tasks = [];
        if (is_sweeping) tasks.push("Floor Sweeping");
        if (is_mopping) tasks.push("Wet Mopping");
        const taskStr = tasks.join(" + ");

        const roomLabel = `${studentUser.block}-${studentUser.room_number}`;

        // Use FCM multicast (send to up to 500 tokens per batch)
        const batchSize = 500;
        for (let i = 0; i < tokens.length; i += batchSize) {
          const batch = tokens.slice(i, i + batchSize);
          await sendFCMMulticast(batch, {
            title: is_urgent
              ? `🚨 URGENT: Room ${roomLabel}`
              : `New Request: Room ${roomLabel}`,
            body: is_urgent
              ? `URGENT — ${taskStr} needed NOW!`
              : `${taskStr} requested. Tap to accept!`,
            data: {
              type: "NEW_REQUEST",
              request_id: newRequest.id,
              room: roomLabel,
              is_urgent: String(is_urgent || false),
              tasks: taskStr,
              notes: notes || "",
            },
            // Urgent requests use a different notification channel
            // for the siren sound on Android
            android_channel_id: is_urgent ? "urgent_requests" : "normal_requests",
          });
        }
      }
    }

    return jsonResponse(201, {
      success: true,
      request_id: newRequest.id,
      message: "Request broadcast to all available cleaners.",
    });
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

async function sendFCMMulticast(
  tokens: string[],
  notification: {
    title: string;
    body: string;
    data?: Record<string, string>;
    android_channel_id?: string;
  }
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
    const accessToken = accessTokenObj.token;
    const projectId = fcmCredentials.project_id;
    const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    await Promise.all(
      tokens.map(async (token) => {
        const payload = {
          message: {
            token: token,
            notification: {
              title: notification.title,
              body: notification.body,
            },
            android: {
              notification: {
                sound: notification.android_channel_id === "urgent_requests" ? "siren.wav" : "default",
                channel_id: notification.android_channel_id || "normal_requests",
              },
            },
            data: notification.data || {},
          },
        };

        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(payload),
        });

        if (!res.ok) {
          const text = await res.text();
          console.error(`Failed to send FCM to ${token}:`, text);
        }
      })
    );
  } catch (err) {
    console.error("FCM multicast failed:", err);
  }
}
