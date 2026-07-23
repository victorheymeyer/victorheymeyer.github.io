// Waitlist join (v1): the only write path for waitlist_signups that anon
// can reach. Verifies a Cloudflare Turnstile token server-side, then calls
// the waitlist_join RPC using the service role key. The RPC itself is not
// granted to anon (see the create_waitlist_signups migration) precisely so
// that this Turnstile check can't be bypassed by calling the RPC directly.
//
// verify_jwt is disabled for this function: signups happen before anyone is
// authenticated, so there is no Supabase JWT to check. Turnstile is the
// anti-abuse mechanism here instead.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const TURNSTILE_SECRET_KEY = Deno.env.get("TURNSTILE_SECRET_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// CORS is not a security boundary here (a non-browser client can call this
// endpoint regardless of headers) -- it's just what lets the browser fetch()
// from the site's own origin succeed instead of being blocked client-side.
const ALLOWED_ORIGIN = "https://heymeyer.com";
const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  let payload: { email?: string; turnstileToken?: string; company_url?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid request body" }, 400);
  }

  const email = (payload.email || "").trim();
  const turnstileToken = payload.turnstileToken || "";
  const honeypot = payload.company_url || "";

  // Honeypot: real users never fill this in. Pretend success, insert nothing.
  if (honeypot !== "") {
    return json({ joined: true });
  }

  if (!email) {
    return json({ error: "email is required" }, 400);
  }
  if (!turnstileToken) {
    return json({ error: "verification failed, please try again" }, 400);
  }

  const verifyRes = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      secret: TURNSTILE_SECRET_KEY,
      response: turnstileToken,
      remoteip: req.headers.get("cf-connecting-ip") ?? undefined,
    }),
  });
  const verifyResult = await verifyRes.json();
  if (!verifyResult.success) {
    return json({ error: "verification failed, please try again" }, 400);
  }

  const { data, error } = await supabase.rpc("waitlist_join", { p_email: email });
  if (error) {
    const msg = error.message.includes("invalid email")
      ? "please enter a valid email address"
      : "something went wrong, please try again";
    return json({ error: msg }, 400);
  }

  return json({ joined: data === true });
});
