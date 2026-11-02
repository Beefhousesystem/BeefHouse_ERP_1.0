// 牛室炙烤牛排 ERP · 后台推送函数 send-order-push
// 作用：有人下单时，向所有已订阅的老板/区域副经理设备发送 Web Push（关掉网页也能收到）。
// 部署（Supabase 控制台 → Edge Functions）：粘贴本文件为函数 send-order-push，
//   并在 Settings → Functions secrets 设 VAPID_PUBLIC / VAPID_PRIVATE / VAPID_SUBJECT，
//   （可选）ALLOWED_ORIGINS = 牛室网页网址，多个用逗号隔开，例如 https://beefhousesystem.github.io
//   部署时「Verify JWT」仍然保持关闭——登录验证改由本函数自己做（见下面 authorize）。详见 PUSH_SETUP.md。
//
// 2026-11-02 安全加固：
//   1) 必须带牛室 ERP 的登录令牌，且邮箱在白名单(erp_users)里并且是启用状态，否则 403（以前谁都能调用）。
//   2) 推送标题固定由服务器决定；内容限长并去掉 < > 和控制字符；图标不收客户端的值。
//   3) CORS 只放行 ALLOWED_ORIGINS（默认 https://beefhousesystem.github.io），不再是 *。
//   4) GET ?health=1：只检查密钥和订阅表，绝不发推送。
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC") ?? "";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@beefhouse.local";
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "https://beefhousesystem.github.io")
  .split(",").map((s) => s.trim()).filter(Boolean);

let vapidOk = false;
try {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);
  vapidOk = true;
} catch (_e) { /* 密钥缺失或格式不对：health 会报告，发送时会拒绝 */ }

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const h: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
  if (ALLOWED_ORIGINS.includes(origin)) h["Access-Control-Allow-Origin"] = origin;
  return h;
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsFor(req), "Content-Type": "application/json" },
  });
}

// 清理文字：去控制字符、去 < >、压缩空白、限长
function clean(v: unknown, max: number): string {
  return String(v ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/[<>]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}

// 验证调用者：登录令牌有效 + 邮箱在白名单且启用
async function authorize(req: Request): Promise<string | null> {
  const auth = req.headers.get("authorization") ?? "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const { data, error } = await supabase.auth.getUser(m[1]);
  const email = data?.user?.email?.toLowerCase();
  if (error || !email) return null;
  const { data: row } = await supabase
    .from("erp_users").select("email").eq("email", email).eq("active", true).maybeSingle();
  return row ? email : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(req) });

  // 健康检查：只看密钥和订阅表，绝不发推送
  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.get("health") === "1") {
    const problems: string[] = [];
    if (!VAPID_PUBLIC) problems.push("VAPID_PUBLIC 未设置");
    if (!VAPID_PRIVATE) problems.push("VAPID_PRIVATE 未设置");
    if (VAPID_PUBLIC && VAPID_PRIVATE && !vapidOk) problems.push("VAPID 密钥格式不对");
    const { error } = await supabase.from("erp_push_subs").select("endpoint", { head: true, count: "exact" });
    if (error) problems.push("订阅表 erp_push_subs 读取失败");
    return problems.length
      ? json(req, { ok: false, problems }, 503)
      : json(req, { ok: true });
  }

  if (req.method !== "POST") return json(req, { error: "method not allowed" }, 405);

  try {
    const who = await authorize(req);
    if (!who) return json(req, { error: "forbidden" }, 403);
    if (!vapidOk) return json(req, { error: "push not configured" }, 503);

    const input = await req.json().catch(() => ({}));
    const payload = JSON.stringify({
      title: "🔔 新订单 New Order", // 标题由服务器决定，不收客户端的值
      body: clean(input?.body, 120),
      icon: "icon-192.png",          // 图标固定，不收客户端的值
      url: "./",
    });

    const { data: subs } = await supabase.from("erp_push_subs").select("endpoint, sub");
    let sent = 0;
    await Promise.allSettled(
      (subs ?? []).map(async (row: any) => {
        try {
          await webpush.sendNotification(row.sub, payload);
          sent++;
        } catch (e: any) {
          if (e?.statusCode === 404 || e?.statusCode === 410) {
            await supabase.from("erp_push_subs").delete().eq("endpoint", row.endpoint);
          }
        }
      })
    );
    return json(req, { sent, total: (subs ?? []).length });
  } catch (_e) {
    return json(req, { error: "bad request" }, 400);
  }
});
