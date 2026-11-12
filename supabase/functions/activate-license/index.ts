// Edge Function: activate-license
// أول تشغيل للتطبيق: بيستقبل مفتاح الترخيص + بصمة الجهاز، يربطهم مرة واحدة،
// ويرجّع بيانات دخول خاصة بالجهاز ده بس (الباسورد بيتغير مع كل تفعيل).
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function fail(code: string, status = 400) {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function randomSecret(len = 40): string {
  const bytes = new Uint8Array(len);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replace(/[^A-Za-z0-9]/g, "").slice(0, len);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("METHOD_NOT_ALLOWED", 405);

  let body: Record<string, string>;
  try {
    body = await req.json();
  } catch {
    return fail("BAD_JSON");
  }
  const key = String(body.key ?? "").trim().toUpperCase();
  const fingerprint = String(body.fingerprint ?? "").trim();
  if (!key || fingerprint.length < 16) return fail("BAD_INPUT");

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: lic } = await admin
    .from("licenses")
    .select("id, profile_id, company_id, fingerprint, active")
    .eq("license_key", key)
    .maybeSingle();
  if (!lic) return fail("INVALID_KEY", 404);
  if (!lic.active) return fail("LICENSE_SUSPENDED", 403);
  if (lic.fingerprint && lic.fingerprint !== fingerprint) return fail("ALREADY_BOUND", 409);

  const { data: profile } = await admin
    .from("profiles").select("id, role, active").eq("id", lic.profile_id).single();
  if (!profile?.active) return fail("USER_SUSPENDED", 403);

  if (profile.role !== "super_admin") {
    const { data: company } = await admin
      .from("companies").select("active, expires_at").eq("id", lic.company_id).single();
    if (!company?.active) return fail("COMPANY_SUSPENDED", 403);
    if (new Date(company.expires_at) < new Date()) return fail("LICENSE_EXPIRED", 403);
  }

  // باسورد جديد للجهاز ده: أي جهاز قديم معاه باسورد قديم مش هيعرف يدخل
  const password = randomSecret();
  const { data: user, error: upErr } = await admin.auth.admin.updateUserById(lic.profile_id, { password });
  if (upErr || !user?.user?.email) return fail("AUTH_UPDATE_FAILED", 500);

  const { error: bindErr } = await admin.from("licenses").update({
    fingerprint,
    device_serial: String(body.serial ?? "").slice(0, 120),
    device_name: String(body.device_name ?? "").slice(0, 120),
    platform: String(body.platform ?? "").slice(0, 20),
    activated_at: new Date().toISOString(),
  }).eq("id", lic.id);
  if (bindErr) return fail("BIND_FAILED", 500);

  return new Response(JSON.stringify({ email: user.user.email, password }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
