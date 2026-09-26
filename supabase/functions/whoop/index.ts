// WHOOP bridge. The client secret and tokens never leave the server.
// Actions (POST JSON, caller must send their Supabase JWT):
//   { action: "exchange", code, redirect_uri }   -> stores tokens after OAuth
//   { action: "get", path, params? }             -> proxies an allow-listed WHOOP v2 GET
//   { action: "disconnect" }                     -> revokes access and deletes tokens
import { createClient } from "npm:@supabase/supabase-js@2";

const WHOOP_BASE = "https://api.prod.whoop.com";
const TOKEN_URL = `${WHOOP_BASE}/oauth/oauth2/token`;
const ALLOWED_PATHS = new Set([
  "/v2/recovery",
  "/v2/activity/sleep",
  "/v2/activity/workout",
  "/v2/cycle",
  "/v2/user/profile/basic",
]);

// Trimmed: a stray space or newline pasted into the dashboard breaks client authentication.
const CLIENT_ID = (Deno.env.get("WHOOP_CLIENT_ID") ?? "").trim();
const CLIENT_SECRET = (Deno.env.get("WHOOP_CLIENT_SECRET") ?? "").trim();
const REDIRECT_URIS = (Deno.env.get("WHOOP_REDIRECT_URIS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "form" },
  auth: { persistSession: false },
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// WHOOP's OAuth server accepts client credentials either in the form body (client_secret_post)
// or as HTTP Basic auth (client_secret_basic), depending on how the app is registered.
// Try the body first; on invalid_client retry with Basic. Never send both at once.
async function tokenRequest(params: Record<string, string>) {
  const attempt = (mode: "post" | "basic") => {
    const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded" };
    const form: Record<string, string> = { ...params };
    if (mode === "post") {
      form.client_id = CLIENT_ID;
      form.client_secret = CLIENT_SECRET;
    } else {
      headers.Authorization = `Basic ${btoa(`${encodeURIComponent(CLIENT_ID)}:${encodeURIComponent(CLIENT_SECRET)}`)}`;
    }
    return fetch(TOKEN_URL, { method: "POST", headers, body: new URLSearchParams(form) });
  };

  if (!CLIENT_ID || !CLIENT_SECRET) throw new Error("WHOOP_CLIENT_ID or WHOOP_CLIENT_SECRET secret is missing");

  let res = await attempt("post");
  let body = await res.json().catch(() => ({}));
  if (res.status === 401 && body.error === "invalid_client") {
    res = await attempt("basic");
    body = await res.json().catch(() => ({}));
  }
  if (!res.ok) {
    // Diagnostics stay in the function logs; the client only sees the WHOOP error code.
    console.error(
      `WHOOP token error ${res.status}: ${body.error_description ?? body.error ?? "unknown"} ` +
        `(client_id ends …${CLIENT_ID.slice(-4)}, secret length ${CLIENT_SECRET.length})`,
    );
    throw new Error(`WHOOP sign-in failed (${res.status} ${body.error ?? "error"})`);
  }
  return body as { access_token: string; refresh_token?: string; expires_in: number };
}

async function saveTokens(userId: string, t: { access_token: string; refresh_token?: string; expires_in: number }, previousRefresh?: string) {
  const { error } = await admin.from("whoop_connections").upsert({
    user_id: userId,
    access_token: t.access_token,
    refresh_token: t.refresh_token ?? previousRefresh ?? "",
    expires_at: new Date(Date.now() + t.expires_in * 1000).toISOString(),
    updated_at: new Date().toISOString(),
  });
  if (error) throw error;
}

async function accessToken(userId: string): Promise<string | null> {
  const { data, error } = await admin.from("whoop_connections").select("*").eq("user_id", userId).maybeSingle();
  if (error) throw error;
  if (!data) return null;
  if (new Date(data.expires_at).getTime() - Date.now() > 60_000) return data.access_token;
  const refreshed = await tokenRequest({ grant_type: "refresh_token", refresh_token: data.refresh_token, scope: "offline" });
  await saveTokens(userId, refreshed, data.refresh_token);
  return refreshed.access_token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  const { data: auth } = await admin.auth.getUser(jwt);
  const userId = auth?.user?.id;
  if (!userId) return json({ error: "Not signed in" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  try {
    switch (body.action) {
      case "exchange": {
        const code = String(body.code ?? "");
        const redirect = String(body.redirect_uri ?? "");
        if (!code || !REDIRECT_URIS.includes(redirect)) return json({ error: "Bad code or redirect_uri" }, 400);
        const tokens = await tokenRequest({ grant_type: "authorization_code", code, redirect_uri: redirect });
        await saveTokens(userId, tokens);
        return json({ connected: true });
      }

      case "get": {
        const path = String(body.path ?? "");
        if (!ALLOWED_PATHS.has(path)) return json({ error: "Path not allowed" }, 400);
        const token = await accessToken(userId);
        if (!token) return json({ error: "WHOOP not connected" }, 409);
        const query = new URLSearchParams(
          Object.entries((body.params ?? {}) as Record<string, unknown>).map(([k, v]) => [k, String(v)]),
        );
        const res = await fetch(`${WHOOP_BASE}/developer${path}?${query}`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        const text = await res.text();
        return new Response(text, { status: res.status, headers: { "Content-Type": "application/json" } });
      }

      case "disconnect": {
        const token = await accessToken(userId).catch(() => null);
        if (token) {
          await fetch(`${WHOOP_BASE}/developer/v2/user/access`, {
            method: "DELETE",
            headers: { Authorization: `Bearer ${token}` },
          }).catch(() => {});
        }
        await admin.from("whoop_connections").delete().eq("user_id", userId);
        return json({ connected: false });
      }

      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : (e as { message?: string })?.message ?? JSON.stringify(e);
    console.error(`whoop ${String(body.action)} failed:`, message);
    return json({ error: message }, 502);
  }
});
