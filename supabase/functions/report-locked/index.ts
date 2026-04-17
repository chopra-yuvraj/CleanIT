// ============================================================
//  CleanIT — Report Room Locked Edge Function
//  Supabase Edge Function (Deno runtime)
//
//  Handles the "Room Locked / Student Absent" exception path:
//  1. Validates the cleaner is assigned to this request
//  2. Uploads mandatory proof photo to Supabase Storage
//  3. Calls the report_room_locked() RPC to cancel the request
//  4. Sends FCM push notification to the student
// ============================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;

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

    // ── 2. Get cleaner's internal profile ──
    const { data: cleanerUser } = await supabase
      .from("users")
      .select("id, role, name")
      .eq("auth_id", user.id)
      .single();

    if (!cleanerUser || cleanerUser.role !== "cleaner") {
      return jsonResponse(403, {
        success: false,
        code: "FORBIDDEN",
        message: "Only cleaners can report locked rooms.",
      });
    }

    // ── 3. Parse multipart form data ──
    const formData = await req.formData();
    const requestId = formData.get("request_id") as string;
    const photo = formData.get("photo") as File | null;
    const failureReason =
      (formData.get("failure_reason") as string) || "room_locked";

    if (!requestId) {
      return jsonResponse(400, {
        success: false,
        code: "INVALID_REQUEST",
        message: "request_id is required.",
      });
    }

    // ── 4. Validate photo is present (anti-abuse) ──
    if (!photo || photo.size === 0) {
      return jsonResponse(400, {
        success: false,
        code: "PHOTO_REQUIRED",
        message:
          "A proof photo is required to report a locked room. Please take a photo of the locked door.",
      });
    }

    // Validate file type
    const allowedTypes = ["image/jpeg", "image/png", "image/webp"];
    if (!allowedTypes.includes(photo.type)) {
      return jsonResponse(400, {
        success: false,
        code: "INVALID_FILE_TYPE",
        message: "Photo must be JPEG, PNG, or WebP.",
      });
    }

    // Validate file size (max 5MB)
    const MAX_SIZE = 5 * 1024 * 1024;
    if (photo.size > MAX_SIZE) {
      return jsonResponse(400, {
        success: false,
        code: "FILE_TOO_LARGE",
        message: "Photo must be under 5MB.",
      });
    }

    // ── 5. Upload photo to Supabase Storage ──
    const fileExt = photo.name.split(".").pop() || "jpg";
    const fileName = `${requestId}_${Date.now()}.${fileExt}`;
    const filePath = `locked-proofs/${fileName}`;

    const photoBuffer = await photo.arrayBuffer();
    const { error: uploadError } = await supabase.storage
      .from("proof-photos")
      .upload(filePath, photoBuffer, {
        contentType: photo.type,
        upsert: false,
      });

    if (uploadError) {
      console.error("Storage upload error:", uploadError);
      return jsonResponse(500, {
        success: false,
        code: "UPLOAD_FAILED",
        message: "Failed to upload proof photo.",
      });
    }

    // Get public URL for the uploaded photo
    const {
      data: { publicUrl },
    } = supabase.storage.from("proof-photos").getPublicUrl(filePath);

    // ── 6. Call the RPC function to cancel the request ──
    const { data: result, error: rpcError } = await supabase.rpc(
      "report_room_locked",
      {
        p_request_id: requestId,
        p_cleaner_id: cleanerUser.id,
        p_failure_reason: failureReason,
        p_proof_url: publicUrl,
      }
    );

    if (rpcError) {
      console.error("RPC error:", rpcError);
      return jsonResponse(500, {
        success: false,
        code: "INTERNAL_ERROR",
        message: "Failed to process report.",
      });
    }

    if (!result.success) {
      // Clean up the uploaded photo since the operation failed
      await supabase.storage.from("proof-photos").remove([filePath]);
      return jsonResponse(403, result);
    }

    // ── 7. Send FCM push notification to the student ──
    const studentId = result.student_id;
    const { data: student } = await supabase
      .from("users")
      .select("fcm_token, name")
      .eq("id", studentId)
      .single();

    if (student?.fcm_token) {
      await sendFCM(student.fcm_token, {
        title: "Room Locked 🔒",
        body: `Your cleaner arrived, but your room was locked. Your request has been cancelled.`,
        data: {
          type: "ROOM_LOCKED",
          request_id: requestId,
          proof_image_url: publicUrl,
        },
      });
    }

    return jsonResponse(200, {
      success: true,
      message: "Request cancelled. Student has been notified.",
      proof_image_url: publicUrl,
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

async function sendFCM(
  token: string,
  notification: { title: string; body: string; data?: Record<string, string> }
) {
  try {
    await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `key=${FCM_SERVER_KEY}`,
      },
      body: JSON.stringify({
        to: token,
        notification: {
          title: notification.title,
          body: notification.body,
          sound: "default",
        },
        data: notification.data || {},
        priority: "high",
      }),
    });
  } catch (err) {
    console.error("FCM send failed:", err);
  }
}
