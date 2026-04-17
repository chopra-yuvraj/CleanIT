// ============================================================
//  CleanIT — Verify QR Edge Function
//  Supabase Edge Function (Deno runtime)
//
//  Verifies the time-sensitive QR code scanned by the cleaner,
//  validates its signature and 3-minute expiry window, then
//  marks the job as COMPLETED.
// ============================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  decode as base64Decode,
} from "https://deno.land/std@0.177.0/encoding/base64.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const QR_SECRET = Deno.env.get("QR_SIGNING_SECRET")!; // Shared secret for HMAC signing

const QR_EXPIRY_MS = 3 * 60 * 1000; // 3 minutes

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ── HMAC-SHA256 using Web Crypto API ──
async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const msgData = encoder.encode(message);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

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
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (!user) {
      return jsonResponse(401, {
        success: false,
        code: "UNAUTHORIZED",
        message: "Invalid or expired token.",
      });
    }

    // ── 2. Get cleaner profile ──
    const { data: cleanerUser } = await supabase
      .from("users")
      .select("id, role")
      .eq("auth_id", user.id)
      .single();

    if (!cleanerUser || cleanerUser.role !== "cleaner") {
      return jsonResponse(403, {
        success: false,
        code: "FORBIDDEN",
        message: "Only cleaners can verify QR codes.",
      });
    }

    // ── 3. Parse request body ──
    const { request_id, qr_payload } = await req.json();

    if (!request_id || !qr_payload) {
      return jsonResponse(400, {
        success: false,
        code: "INVALID_REQUEST",
        message: "request_id and qr_payload are required.",
      });
    }

    // ── 4. Decode and verify the QR payload ──
    //    QR payload structure (base64-encoded JSON):
    //    {
    //      "request_id": "uuid",
    //      "student_id": "uuid",
    //      "timestamp": 1713350000000,  // epoch ms
    //      "signature": "hmac-sha256-hex"
    //    }
    let qrData: {
      request_id: string;
      student_id: string;
      timestamp: number;
      signature: string;
    };

    try {
      const decoded = new TextDecoder().decode(base64Decode(qr_payload));
      qrData = JSON.parse(decoded);
    } catch {
      return jsonResponse(400, {
        success: false,
        code: "INVALID_QR",
        message: "QR code is malformed or corrupted.",
      });
    }

    // ── 5. Verify the request_id in QR matches the one in the URL ──
    if (qrData.request_id !== request_id) {
      return jsonResponse(400, {
        success: false,
        code: "QR_MISMATCH",
        message: "QR code does not match this request.",
      });
    }

    // ── 6. Verify HMAC signature (using Web Crypto API) ──
    const payload = `${qrData.request_id}:${qrData.student_id}:${qrData.timestamp}`;
    const expectedSignature = await hmacSha256Hex(QR_SECRET, payload);

    if (qrData.signature !== expectedSignature) {
      return jsonResponse(400, {
        success: false,
        code: "INVALID_SIGNATURE",
        message: "QR code signature verification failed.",
      });
    }

    // ── 7. Check expiry (3-minute window) ──
    const now = Date.now();
    const age = now - qrData.timestamp;

    if (age > QR_EXPIRY_MS) {
      return jsonResponse(410, {
        success: false,
        code: "QR_EXPIRED",
        message: "This QR code has expired. Ask the student to generate a new one.",
      });
    }

    if (age < 0) {
      // QR timestamp is in the future — suspicious
      return jsonResponse(400, {
        success: false,
        code: "INVALID_QR",
        message: "QR code timestamp is invalid.",
      });
    }

    // ── 8. Complete the job via RPC ──
    const { data: result, error: rpcError } = await supabase.rpc("complete_job", {
      p_request_id: request_id,
      p_cleaner_id: cleanerUser.id,
    });

    if (rpcError || !result?.success) {
      return jsonResponse(400, {
        success: false,
        code: "COMPLETION_FAILED",
        message: result?.message || "Failed to complete the job.",
      });
    }

    return jsonResponse(200, {
      success: true,
      message: "Job completed! Student will be prompted for feedback.",
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

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
