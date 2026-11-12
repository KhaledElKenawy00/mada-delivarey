// Edge Function: admin (للسوبر أدمن بس)
// actions:
//   create_company  → شركة + مخازن + حساب مدير + أمين لكل مخزن + مناديب + مفاتيح
//   add_account     → حساب جديد (أمين/مندوب) لشركة موجودة
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function genKey(): string {
  const r = new Uint8Array(12);
  crypto.getRandomValues(r);
  const c = Array.from(r, (b) => ALPHABET[b % ALPHABET.length]).join("");
  return `MDR-${c.slice(0, 4)}-${c.slice(4, 8)}-${c.slice(8, 12)}`;
}
function randomSecret(): string {
  const r = new Uint8Array(32);
  crypto.getRandomValues(r);
  return Array.from(r, (b) => b.toString(16).padStart(2, "0")).join("");
}

function addDuration(unit: string, count: number): Date {
  const d = new Date();
  switch (unit) {
    case "hour": d.setHours(d.getHours() + count); break;
    case "day": d.setDate(d.getDate() + count); break;
    case "week": d.setDate(d.getDate() + 7 * count); break;
    case "year": d.setFullYear(d.getFullYear() + count); break;
    default: d.setMonth(d.getMonth() + count);
  }
  return d;
}

async function createAccount(
  admin: SupabaseClient,
  a: { company_id: string; warehouse_id: string | null; role: string; name: string; phone?: string },
) {
  const email = `${crypto.randomUUID()}@accounts.madar.local`;
  const { data: u, error } = await admin.auth.admin.createUser({
    email, password: randomSecret(), email_confirm: true,
  });
  if (error || !u.user) throw new Error("CREATE_USER_FAILED: " + error?.message);

  const { error: pErr } = await admin.from("profiles").insert({
    id: u.user.id, company_id: a.company_id, warehouse_id: a.warehouse_id,
    role: a.role, full_name: a.name, phone: a.phone ?? null,
  });
  if (pErr) throw new Error("PROFILE_FAILED: " + pErr.message);

  for (let i = 0; i < 5; i++) {
    const key = genKey();
    const { error: lErr } = await admin.from("licenses").insert({
      company_id: a.company_id, profile_id: u.user.id, license_key: key,
    });
    if (!lErr) return { profile_id: u.user.id, role: a.role, name: a.name, key };
    if (lErr.code !== "23505") throw new Error("LICENSE_FAILED: " + lErr.message);
  }
  throw new Error("KEY_COLLISION");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // تأكيد إن اللي بينادي سوبر أدمن
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const { data: caller } = await admin.auth.getUser(jwt);
  if (!caller?.user) return json({ error: "UNAUTHORIZED" }, 401);
  const { data: me } = await admin.from("profiles").select("role, active").eq("id", caller.user.id).single();
  if (me?.role !== "super_admin" || !me.active) return json({ error: "FORBIDDEN" }, 403);

  const body = await req.json();

  try {
    if (body.action === "create_company") {
      const whs: { name: string; reps: number }[] = body.warehouses ?? [];
      if (!body.name || whs.length === 0) return json({ error: "BAD_INPUT" }, 400);

      const { data: seq } = await admin.rpc("nextval_company");
      const code = "CO-" + String(seq ?? Date.now() % 10000).padStart(4, "0");

      const { data: company, error: cErr } = await admin.from("companies").insert({
        code, name: body.name, manager_name: body.manager_name ?? null,
        expires_at: addDuration(body.duration?.unit ?? "month", Number(body.duration?.count ?? 1)).toISOString(),
        max_warehouses: whs.length,
        allow_credit: body.allow_credit ?? true,
      }).select().single();
      if (cErr) throw new Error(cErr.message);

      const accounts: unknown[] = [];
      accounts.push({
        ...(await createAccount(admin, {
          company_id: company.id, warehouse_id: null, role: "manager",
          name: body.manager_name || "مدير الشركة", phone: body.manager_phone,
        })),
        warehouse: null,
      });

      for (const w of whs) {
        const { data: wh, error: wErr } = await admin.from("warehouses").insert({
          company_id: company.id, name: w.name, max_reps: w.reps,
        }).select().single();
        if (wErr) throw new Error(wErr.message);

        accounts.push({
          ...(await createAccount(admin, {
            company_id: company.id, warehouse_id: wh.id, role: "keeper", name: `أمين ${w.name}`,
          })),
          warehouse: w.name,
        });
        for (let i = 1; i <= w.reps; i++) {
          accounts.push({
            ...(await createAccount(admin, {
              company_id: company.id, warehouse_id: wh.id, role: "rep", name: `مندوب ${i} — ${w.name}`,
            })),
            warehouse: w.name,
          });
        }
      }
      return json({ company, accounts });
    }

    if (body.action === "delete_company") {
      const companyId = body.company_id as string | undefined;
      if (!companyId) return json({ error: "BAD_INPUT" }, 400);
      const { data: profs } = await admin.from("profiles").select("id").eq("company_id", companyId);
      const { error } = await admin.rpc("admin_delete_company", { p_company: companyId });
      if (error) throw new Error(error.message);
      for (const p of profs ?? []) {
        try { await admin.auth.admin.deleteUser(p.id); } catch { /* الحساب ممكن يكون مش موجود — نكمل */ }
      }
      return json({ ok: true });
    }

    if (body.action === "add_account") {
      const acc = await createAccount(admin, {
        company_id: body.company_id, warehouse_id: body.warehouse_id ?? null,
        role: body.role, name: body.name, phone: body.phone,
      });
      if (body.role === "rep" && body.warehouse_id) {
        // زوّد الحد المسموح للمخزن لو اتملى
        const { count } = await admin.from("profiles").select("*", { count: "exact", head: true })
          .eq("warehouse_id", body.warehouse_id).eq("role", "rep");
        await admin.from("warehouses").update({ max_reps: count ?? 0 })
          .eq("id", body.warehouse_id).lt("max_reps", count ?? 0);
      }
      return json(acc);
    }

    return json({ error: "UNKNOWN_ACTION" }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
