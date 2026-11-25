// =====================================================================
// Edge Function «notificar» · Avisos de la app Arco Ríos
// Supabase → Edge Functions → Deploy a new function → nombre: notificar
// Pegar este archivo completo. En Settings de la función, apagar
// «Verify JWT with legacy secret» (la función revisa los permisos sola).
//
// Acciones (POST con JSON):
//   { accion: "clave" }                  → clave pública para activar avisos en el teléfono
//   { accion: "enviar", id }             → envía al teléfono un aviso ya creado con crear_aviso()
//   { accion: "prueba" }                 → aviso de prueba solo para quien lo pide
//   { accion: "recordatorios" }          → lo llama el sábado en la noche el cron (con x-cron-secreto)
//
// Las notificaciones push se cifran aquí mismo (RFC 8291 + VAPID RFC 8292),
// sin librerías externas. Las claves VAPID se crean solas la primera vez y
// se guardan en la tabla ajustes_privados.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_APP = "https://joelguido-beep.github.io/Arco-app/";
const CONTACTO = "mailto:arcorios.app@gmail.com";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secreto",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

// ---------- base64url ----------
const b64u = (buf: ArrayBuffer | Uint8Array) => {
  const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = ""; for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const deB64u = (s: string): Uint8Array<ArrayBuffer> => {
  s = s.replace(/-/g, "+").replace(/_/g, "/"); while (s.length % 4) s += "=";
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
};
const concat = (...xs: Uint8Array[]): Uint8Array<ArrayBuffer> => { const out = new Uint8Array(xs.reduce((a, x) => a + x.length, 0)); let o = 0; for (const x of xs) { out.set(x, o); o += x.length; } return out; };
const txt = (s: string): Uint8Array<ArrayBuffer> => new TextEncoder().encode(s) as Uint8Array<ArrayBuffer>;

// ---------- Claves VAPID (se crean una sola vez) ----------
type Vapid = { publica: string; privada: CryptoKey };
let vapidCache: Vapid | null = null;
async function vapid(): Promise<Vapid> {
  if (vapidCache) return vapidCache;
  const leer = async () => {
    const { data } = await admin.from("ajustes_privados").select("clave, valor").in("clave", ["vapid_publica", "vapid_privada"]);
    const m = Object.fromEntries((data || []).map((r) => [r.clave, r.valor]));
    return m.vapid_publica && m.vapid_privada ? m : null;
  };
  let m = await leer();
  if (!m) {
    const par = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const pub = b64u(await crypto.subtle.exportKey("raw", par.publicKey));
    const jwk = JSON.stringify(await crypto.subtle.exportKey("jwk", par.privateKey));
    // Si otra llamada las creó al mismo tiempo, se quedan las primeras
    await admin.from("ajustes_privados").upsert([{ clave: "vapid_publica", valor: pub }, { clave: "vapid_privada", valor: jwk }], { onConflict: "clave", ignoreDuplicates: true });
    m = await leer();
  }
  const privada = await crypto.subtle.importKey("jwk", JSON.parse(m!.vapid_privada), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  vapidCache = { publica: m!.vapid_publica, privada };
  return vapidCache;
}

async function jwtVapid(aud: string, v: Vapid) {
  const head = b64u(txt(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const body = b64u(txt(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: CONTACTO })));
  const firma = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, v.privada, txt(`${head}.${body}`));
  return `${head}.${body}.${b64u(firma)}`;
}

// ---------- Cifrado aes128gcm (RFC 8291) ----------
const hmac = async (clave: BufferSource, datos: BufferSource) =>
  new Uint8Array(await crypto.subtle.sign("HMAC", await crypto.subtle.importKey("raw", clave, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]), datos));

export async function cifrar(p256dh: string, authSecret: string, mensaje: Uint8Array<ArrayBuffer>) {
  const uaPub = deB64u(p256dh), auth = deB64u(authSecret);
  const local = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const asPub = new Uint8Array(await crypto.subtle.exportKey("raw", local.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPub, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, local.privateKey, 256));
  const prkKey = await hmac(auth, ecdh);
  const ikm = await hmac(prkKey, concat(txt("WebPush: info\0"), uaPub, asPub, new Uint8Array([1])));
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmac(salt, ikm);
  const cek = (await hmac(prk, concat(txt("Content-Encoding: aes128gcm\0"), new Uint8Array([1])))).slice(0, 16);
  const nonce = (await hmac(prk, concat(txt("Content-Encoding: nonce\0"), new Uint8Array([1])))).slice(0, 12);
  const clave = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const cifrado = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, clave, concat(mensaje, new Uint8Array([2]))));
  const rs = new Uint8Array([0, 0, 0x10, 0]); // 4096
  return concat(salt, rs, new Uint8Array([asPub.length]), asPub, cifrado);
}

type Sus = { id: number; endpoint: string; p256dh: string; auth: string };
async function enviarPush(s: Sus, datos: Record<string, unknown>, v: Vapid): Promise<"ok" | "borrar" | "error"> {
  try {
    const cuerpo = await cifrar(s.p256dh, s.auth, txt(JSON.stringify(datos)));
    const aud = new URL(s.endpoint).origin;
    const r = await fetch(s.endpoint, {
      method: "POST",
      headers: { "Content-Encoding": "aes128gcm", "Content-Type": "application/octet-stream", TTL: "86400", Urgency: "high",
                 Authorization: `vapid t=${await jwtVapid(aud, v)}, k=${v.publica}` },
      body: cuerpo,
    });
    if (r.status === 404 || r.status === 410) return "borrar";
    if (!r.ok) { console.error("push", r.status, await r.text()); return "error"; }
    return "ok";
  } catch (e) { console.error("push", e); return "error"; }
}

// Envía al teléfono las notificaciones dadas a todos sus destinatarios
async function despachar(ids: number[]) {
  if (!ids.length) return { enviados: 0 };
  const v = await vapid();
  const { data: ns } = await admin.from("notificaciones").select("id, titulo, cuerpo, ir_a, tipo").in("id", ids);
  const { data: dest } = await admin.from("notificaciones_usuarios").select("notificacion_id, user_id").in("notificacion_id", ids);
  const users = [...new Set((dest || []).map((d) => d.user_id))];
  const sus: (Sus & { user_id: string })[] = [];
  for (let i = 0; i < users.length; i += 200) {
    const { data } = await admin.from("push_suscripciones").select("id, user_id, endpoint, p256dh, auth").in("user_id", users.slice(i, i + 200));
    sus.push(...(data || []));
  }
  let total = 0; const borrar: number[] = [];
  for (const n of ns || []) {
    const quienes = new Set((dest || []).filter((d) => d.notificacion_id === n.id).map((d) => d.user_id));
    const lista = sus.filter((s) => quienes.has(s.user_id));
    const datos = { titulo: n.titulo, cuerpo: n.cuerpo || "", url: `${URL_APP}?ir=${n.ir_a || "avisos"}&aviso=${n.id}`, tag: `aviso-${n.id}` };
    let ok = 0;
    for (let i = 0; i < lista.length; i += 20) {
      const res = await Promise.all(lista.slice(i, i + 20).map((s) => enviarPush(s, datos, v)));
      res.forEach((r, k) => { if (r === "ok") ok++; if (r === "borrar") borrar.push(lista[i + k].id); });
    }
    total += ok;
    await admin.from("notificaciones").update({ push_enviados: ok }).eq("id", n.id);
  }
  if (borrar.length) await admin.from("push_suscripciones").delete().in("id", borrar);
  return { enviados: total };
}

// ¿Quién llama? (usuario de la app)
async function usuario(req: Request) {
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data } = await admin.auth.getUser(token);
  return data.user || null;
}
async function puedeAvisar(uid: string) {
  const { data } = await admin.from("usuarios_roles").select("rol").eq("user_id", uid).in("rol", ["admin", "anciano"]);
  return !!data?.length;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));

    // Cron del sábado
    if (body.accion === "recordatorios") {
      const { data: s } = await admin.from("ajustes_privados").select("valor").eq("clave", "cron_secreto").single();
      if (!s?.valor || req.headers.get("x-cron-secreto") !== s.valor) return resp({ error: "Sin permiso" }, 401);
      // Mañana, según la hora de Ecuador
      const hoyEc = new Date(Date.now() - 5 * 3600 * 1000);
      hoyEc.setUTCDate(hoyEc.getUTCDate() + 1);
      const fecha = body.fecha || hoyEc.toISOString().slice(0, 10);
      const { data: ids, error } = await admin.rpc("crear_recordatorios_servicio", { p_fecha: fecha });
      if (error) throw error;
      const r = await despachar((ids || []).map((x: unknown) => Number(typeof x === "object" && x ? Object.values(x)[0] : x)));
      return resp({ fecha, avisos: (ids || []).length, ...r });
    }

    const u = await usuario(req);
    if (!u) return resp({ error: "Inicia sesión" }, 401);

    if (body.accion === "clave") return resp({ clave: (await vapid()).publica });

    if (body.accion === "prueba") {
      const { data: n, error } = await admin.from("notificaciones").insert({ titulo: "Avisos activados ✓", cuerpo: "Así te llegarán los avisos de Arco Ríos.", destino: "prueba", tipo: "aviso", creado_por: u.id, creado_por_nombre: "Prueba", personas: 1 }).select("id").single();
      if (error) throw error;
      await admin.from("notificaciones_usuarios").insert({ notificacion_id: n.id, user_id: u.id });
      return resp(await despachar([n.id]));
    }

    // Aviso al líder de IGHO desde el Stand, o solicitud de ministerio al admin: solo el aviso que esa misma persona acaba de crear
    if (body.accion === "enviar_interes") {
      const { data: n } = await admin.from("notificaciones").select("id, tipo, creado_en, creado_por").eq("id", Number(body.id)).maybeSingle();
      if (!n || !["igho", "solicitud", "sugerencia"].includes(n.tipo) || n.creado_por !== u.id || Date.now() - new Date(n.creado_en).getTime() > 10 * 60 * 1000) return resp({ error: "Sin permiso" }, 403);
      return resp(await despachar([n.id]));
    }

    if (body.accion === "enviar") {
      if (!(await puedeAvisar(u.id))) return resp({ error: "Solo el administrador y el Consejo envían avisos" }, 403);
      return resp(await despachar([Number(body.id)]));
    }

    return resp({ error: "Acción desconocida" }, 400);
  } catch (e) {
    console.error(e);
    return resp({ error: (e as Error).message || String(e) }, 500);
  }
});
