// =====================================================================
// Edge Function «correo» · Correos de la app Arco Ríos (con Resend)
// Supabase → Edge Functions → Deploy a new function → nombre: correo
// Pegar este archivo completo. En Settings de la función, apagar
// «Verify JWT with legacy secret» (la función revisa los permisos sola).
//
// Secrets (Edge Functions → Secrets / Manage secrets):
//   RESEND_API_KEY = la clave de Resend (empieza con re_)
//   CORREO_DE      = remitente, ej.: Arco Ríos <consejo@tudominio.org>
//                    (el dominio debe estar verificado en Resend)
//
// Acciones (POST con JSON):
//   { accion: "diario" }                 → cron de cada día 7:00 (con x-cron-secreto):
//                                          recordatorios del día y, los lunes, el resumen de la reunión
//   { accion: "prueba" }                 → correo de prueba a quien lo pide
//   { accion: "vista_resumen" }          → arma el resumen sin enviarlo (para verlo en la app)
//   { accion: "enviar_resumen" }         → envía ya el resumen al Consejo
//   { accion: "enviar_recordatorio", id } → envía ya un recordatorio
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_APP = "https://joelguido-beep.github.io/Arco-app/";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secreto",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

// ---------- Fechas (hora de Ecuador, UTC-5) ----------
const hoyEc = () => new Date(Date.now() - 5 * 3600 * 1000).toISOString().slice(0, 10);
const dt = (f: string) => new Date(f + "T12:00:00Z");
const ymd = (d: Date) => d.toISOString().slice(0, 10);
const sumar = (f: string, n: number) => { const d = dt(f); d.setUTCDate(d.getUTCDate() + n); return ymd(d); };
const dow = (f: string) => dt(f).getUTCDay();
const fmtLargo = (f: string) => { const s = new Intl.DateTimeFormat("es-EC", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(dt(f)); return s[0].toUpperCase() + s.slice(1); };
const fmtCorto = (f: string) => new Intl.DateTimeFormat("es-EC", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(dt(f));
const hhmm = (h?: string | null) => (h ? h.slice(0, 5) : "");
// Los dos domingos antes del evento (para anunciarlo)
const domingosAntes = (f: string) => { let d = sumar(f, -1); while (dow(d) !== 0) d = sumar(d, -1); return [sumar(d, -7), d]; };

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const TIPO_EV: Record<string, string> = { evento: "Evento", actividad: "Actividad", predica: "Prédica", reunion: "Reunión", otro: "Otro" };

// ---------- Plantilla ----------
const plantilla = (titulo: string, cuerpo: string) => `<!doctype html><html><body style="margin:0;background:#F4F1EC;font-family:Arial,Helvetica,sans-serif;color:#111144">
<div style="max-width:600px;margin:0 auto;padding:24px 16px">
  <div style="background:#223382;color:#F4F1EC;padding:20px 22px"><div style="font-size:12px;letter-spacing:2px;opacity:.8">ARCO RÍOS</div>
    <div style="font-size:22px;font-weight:bold;margin-top:6px">${esc(titulo)}</div></div>
  <div style="background:#fff;border:1px solid #DAD1C8;border-top:0;padding:20px 22px;font-size:15px;line-height:1.5">${cuerpo}
    <p style="margin:24px 0 0"><a href="${URL_APP}" style="background:#223382;color:#F4F1EC;padding:10px 16px;text-decoration:none;border-radius:4px;display:inline-block">Abrir la app</a></p></div>
  <div style="font-size:12px;color:#6b6f8f;padding:12px 4px">Enviado por la app de Arco Ríos.</div>
</div></body></html>`;
const h3 = (t: string) => `<h3 style="font-size:15px;margin:22px 0 8px;padding-bottom:4px;border-bottom:2px solid #F98513">${t}</h3>`;
const ul = (xs: string[]) => `<ul style="margin:0;padding-left:20px">${xs.map((x) => `<li style="margin:4px 0">${x}</li>`).join("")}</ul>`;

// ---------- Envío con Resend ----------
type Dest = { nombre: string; email: string };
async function enviar(dest: Dest[], asunto: string, html: string) {
  const key = Deno.env.get("RESEND_API_KEY"), de = Deno.env.get("CORREO_DE");
  if (!key || !de) throw new Error("Falta configurar RESEND_API_KEY y CORREO_DE en los secrets de la función");
  let ok = 0;
  for (let i = 0; i < dest.length; i += 100) {
    const lote = dest.slice(i, i + 100).map((d) => ({ from: de, to: [d.email], subject: asunto, html }));
    const r = await fetch("https://api.resend.com/emails/batch", {
      method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify(lote),
    });
    if (!r.ok) throw new Error(`Resend ${r.status}: ${await r.text()}`);
    ok += lote.length;
  }
  return ok;
}
async function destinatarios(destinos: string[], personas: string[]): Promise<Dest[]> {
  const { data, error } = await admin.rpc("correo_destinatarios", { p_destinos: destinos || [], p_personas: personas || [] });
  if (error) throw error;
  return (data || []) as Dest[];
}
const registrar = (tipo: string, asunto: string, personas: number, detalle?: string) =>
  admin.from("correos_enviados").insert({ tipo, asunto, personas, detalle: detalle || null });

// ---------- Recordatorio de un evento ----------
async function enviarRecordatorio(id: number) {
  const { data: r } = await admin.from("cal_recordatorios").select("*, cal_eventos(*)").eq("id", id).maybeSingle();
  if (!r || !r.cal_eventos) throw new Error("Recordatorio no encontrado");
  const e = r.cal_eventos;
  const etiqueta = r.clase === "anunciar" ? "Para anunciar" : r.clase === "planificar" ? "Para planificar" : "Recordatorio";
  const asunto = `${etiqueta}: ${e.titulo} · ${fmtCorto(e.fecha)}`;
  const [d1, d2] = domingosAntes(e.fecha);
  const cuerpo = `
    ${r.mensaje ? `<p style="margin:0 0 14px;padding:12px 14px;background:#FFF4EA;border-left:4px solid #F98513">${esc(r.mensaje).replace(/\n/g, "<br>")}</p>` : ""}
    <table style="border-collapse:collapse;width:100%;font-size:15px">
      <tr><td style="padding:4px 12px 4px 0;color:#6b6f8f">Qué</td><td><b>${esc(e.titulo)}</b> · ${TIPO_EV[e.tipo] || ""}</td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b6f8f">Cuándo</td><td>${fmtLargo(e.fecha)}${e.hora ? ", " + hhmm(e.hora) : ""}${e.fecha_fin && e.fecha_fin !== e.fecha ? " al " + fmtLargo(e.fecha_fin) : ""}</td></tr>
      ${e.lugar ? `<tr><td style="padding:4px 12px 4px 0;color:#6b6f8f">Dónde</td><td>${esc(e.lugar)}</td></tr>` : ""}
      ${e.responsable ? `<tr><td style="padding:4px 12px 4px 0;color:#6b6f8f">${e.tipo === "predica" ? "Predica" : "Responsable"}</td><td>${esc(e.responsable)}</td></tr>` : ""}
    </table>
    ${e.descripcion ? `<p style="margin:14px 0 0">${esc(e.descripcion).replace(/\n/g, "<br>")}</p>` : ""}
    ${r.clase === "anunciar" ? `<p style="margin:14px 0 0">Se anuncia los domingos <b>${fmtLargo(d1)}</b> y <b>${fmtLargo(d2)}</b>.</p>` : ""}
    ${r.clase === "planificar" ? `<p style="margin:14px 0 0">Faltan ${Math.round((dt(e.fecha).getTime() - dt(hoyEc()).getTime()) / 86400000 / 7)} semanas. Es buen momento para planificarlo.</p>` : ""}`;
  const dest = await destinatarios(r.destinos, r.personas);
  if (!dest.length) {
    await admin.from("cal_recordatorios").update({ enviado_en: new Date().toISOString(), enviados: 0, error: "Nadie de la lista tiene correo" }).eq("id", id);
    return 0;
  }
  const n = await enviar(dest, asunto, plantilla(asunto, cuerpo));
  await admin.from("cal_recordatorios").update({ enviado_en: new Date().toISOString(), enviados: n, error: null }).eq("id", id);
  await registrar("recordatorio", asunto, n);
  return n;
}

// ---------- Resumen del lunes para el Consejo ----------
async function armarResumen(hoy: string) {
  const { data: cfg } = await admin.from("consejo_config").select("*").eq("id", 1).maybeSingle();
  const { data: rs } = await admin.from("consejo_reuniones").select("*").gte("fecha", hoy).lte("fecha", sumar(hoy, 6)).order("fecha").limit(1);
  let reu = rs?.[0] || null;
  if (!reu && cfg?.dia_semana != null) {
    let f = hoy; while (dow(f) !== cfg.dia_semana) f = sumar(f, 1);
    reu = { fecha: f, tipo: cfg.tipo || "Consejo", hora: cfg.hora, lugar: cfg.lugar, notas: null, resumen_enviado_en: null, _config: true };
  }
  if (reu?.tipo === "No hay reunión") return { sinReunion: true, reu, asunto: "", html: "" };
  const hasta = reu?.fecha || sumar(hoy, 7);

  const [ag, ta, ev, rec, pr] = await Promise.all([
    admin.from("consejo_agenda").select("*").eq("estado", "pendiente").order("creado_en"),
    admin.from("consejo_tareas").select("descripcion, responsables, fecha, vence, completado, descartada_en").eq("completado", false).is("descartada_en", null),
    admin.from("cal_eventos").select("*").gte("fecha", hoy).lte("fecha", sumar(hoy, 42)).order("fecha"),
    admin.from("cal_recordatorios").select("envio, clase, cal_eventos(titulo, fecha)").is("enviado_en", null).gte("envio", hoy).lte("envio", sumar(hoy, 6)).order("envio"),
    admin.from("programa_domingo").select("fecha, predicador").gte("fecha", hoy).lte("fecha", sumar(hoy, 28)).order("fecha"),
  ]);
  const agenda = (ag.data || []).filter((a) => !a.reunion_fecha || a.reunion_fecha <= hasta);
  const cat = (c: string) => agenda.filter((a) => a.categoria === c);
  const item = (a: { titulo: string; detalle?: string; quien?: string }) => `<b>${esc(a.titulo)}</b>${a.quien ? ` <span style="color:#6b6f8f">(${esc(a.quien)})</span>` : ""}${a.detalle ? `<br><span style="color:#3B3F6B">${esc(a.detalle)}</span>` : ""}`;
  const tareas = ta.data || [];
  const vencen = tareas.filter((t) => t.vence && t.vence <= hasta).sort((a, b) => (a.vence! < b.vence! ? -1 : 1));
  const viejas = tareas.filter((t) => !t.vence && t.fecha && t.fecha <= sumar(hoy, -30)).length;
  const eventos = ev.data || [];
  // Lo que hay que anunciar este domingo y el siguiente
  const dom1 = (() => { let d = hoy; while (dow(d) !== 0) d = sumar(d, 1); return d; })();
  const anunciar = eventos.filter((e) => { const [a, b] = domingosAntes(e.fecha); return a === dom1 || b === dom1; });

  const tipoReu = reu?.tipo || "Consejo";
  const cuando = reu ? `${fmtLargo(reu.fecha)}${reu.hora ? ", " + hhmm(reu.hora) : ""}` : "Fecha por confirmar";
  const asunto = `Reunión ${tipoReu === "Consejo ampliado" ? "del Consejo ampliado" : "del Consejo"} · ${reu ? fmtCorto(reu.fecha) : "esta semana"}`;
  const vacio = '<p style="margin:0;color:#6b6f8f">Nada por ahora.</p>';
  const cuerpo = `
    <table style="border-collapse:collapse;width:100%;font-size:15px;margin-bottom:6px">
      <tr><td style="padding:4px 12px 4px 0;color:#6b6f8f;width:90px">Reunión</td><td><b>${esc(tipoReu)}</b></td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#6b6f8f">Cuándo</td><td>${esc(cuando)}</td></tr>
      ${reu?.lugar ? `<tr><td style="padding:4px 12px 4px 0;color:#6b6f8f">Dónde</td><td>${esc(reu.lugar)}</td></tr>` : ""}
    </table>
    ${reu?.notas ? `<p style="margin:8px 0 0">${esc(reu.notas).replace(/\n/g, "<br>")}</p>` : ""}
    ${h3(`Decisiones por tomar (${cat("decision").length})`)}${cat("decision").length ? ul(cat("decision").map(item)) : vacio}
    ${h3(`Reportes (${cat("reporte").length})`)}${cat("reporte").length ? ul(cat("reporte").map(item)) : vacio}
    ${h3(`Tareas para revisar (${cat("tarea").length + vencen.length})`)}
    ${cat("tarea").length || vencen.length ? ul([
      ...cat("tarea").map(item),
      ...vencen.map((t) => `<b>${esc(t.descripcion)}</b>${t.responsables ? ` <span style="color:#6b6f8f">(${esc(t.responsables)})</span>` : ""} · <span style="color:${t.vence! < hoy ? "#C0392B" : "#F98513"}">${t.vence! < hoy ? "venció" : "vence"} ${fmtCorto(t.vence!)}</span>`),
    ]) : vacio}
    ${viejas ? `<p style="margin:8px 0 0;color:#6b6f8f">Además hay ${viejas} pendiente(s) sin fecha con más de 30 días.</p>` : ""}
    ${h3("Anunciar este domingo")}${anunciar.length ? ul(anunciar.map((e) => `<b>${esc(e.titulo)}</b> · ${fmtCorto(e.fecha)}`)) : vacio}
    ${h3("Próximas 6 semanas")}${eventos.length ? ul(eventos.map((e) => `${fmtCorto(e.fecha)}${e.hora ? " " + hhmm(e.hora) : ""} · <b>${esc(e.titulo)}</b> <span style="color:#6b6f8f">${TIPO_EV[e.tipo] || ""}${e.responsable ? " · " + esc(e.responsable) : ""}</span>`)) : vacio}
    ${(pr.data || []).filter((p) => p.predicador).length ? h3("Quién predica") + ul((pr.data || []).filter((p) => p.predicador).map((p) => `${fmtCorto(p.fecha)} · ${esc(p.predicador)}`)) : ""}
    ${(rec.data || []).length ? h3("Recordatorios que salen esta semana") + ul((rec.data || []).map((r: any) => `${fmtCorto(r.envio)} · ${r.clase === "anunciar" ? "Anunciar" : r.clase === "planificar" ? "Planificar" : "Recordatorio"}: ${esc(r.cal_eventos?.titulo)}`)) : ""}`;
  return { sinReunion: false, reu, asunto, html: plantilla(asunto, cuerpo) };
}

async function enviarResumen(hoy: string, forzar: boolean) {
  const r = await armarResumen(hoy);
  if (r.sinReunion) return { enviados: 0, nota: "Esta semana no hay reunión" };
  if (!forzar && r.reu?.resumen_enviado_en) return { enviados: 0, nota: "Ya se envió" };
  const dest = await destinatarios(["consejo"], []);
  const n = dest.length ? await enviar(dest, r.asunto, r.html) : 0;
  if (r.reu) await admin.from("consejo_reuniones").upsert({
    fecha: r.reu.fecha, tipo: r.reu.tipo, hora: r.reu.hora, lugar: r.reu.lugar, notas: r.reu.notas, resumen_enviado_en: new Date().toISOString(),
  }, { onConflict: "fecha" });
  await registrar("resumen", r.asunto, n);
  return { enviados: n };
}

// ---------- ¿Quién llama? ----------
async function usuario(req: Request) {
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data } = await admin.auth.getUser(token);
  return data.user || null;
}
async function esConsejo(uid: string) {
  const { data } = await admin.from("usuarios_roles").select("rol").eq("user_id", uid).in("rol", ["admin", "anciano"]);
  return !!data?.length;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const hoy = hoyEc();

    if (body.accion === "diario") {
      const { data: s } = await admin.from("ajustes_privados").select("valor").eq("clave", "cron_secreto").single();
      if (!s?.valor || req.headers.get("x-cron-secreto") !== s.valor) return resp({ error: "Sin permiso" }, 401);
      const out: Record<string, unknown> = { fecha: hoy, recordatorios: 0 };
      const { data: due } = await admin.from("cal_recordatorios").select("id, cal_eventos(fecha)").is("enviado_en", null).lte("envio", hoy);
      for (const r of due || []) {
        if ((r as any).cal_eventos?.fecha < hoy) {
          await admin.from("cal_recordatorios").update({ enviado_en: new Date().toISOString(), enviados: 0, error: "El evento ya pasó" }).eq("id", r.id);
          continue;
        }
        try { await enviarRecordatorio(r.id); out.recordatorios = (out.recordatorios as number) + 1; }
        catch (e) { console.error(e); await admin.from("cal_recordatorios").update({ error: String((e as Error).message || e) }).eq("id", r.id); }
      }
      const { data: cfg } = await admin.from("consejo_config").select("resumen_lunes").eq("id", 1).maybeSingle();
      if (dow(hoy) === 1 && cfg?.resumen_lunes !== false) out.resumen = await enviarResumen(hoy, false);
      return resp(out);
    }

    const u = await usuario(req);
    if (!u) return resp({ error: "Inicia sesión" }, 401);
    if (!(await esConsejo(u.id))) return resp({ error: "Solo el Consejo y el administrador" }, 403);

    if (body.accion === "prueba") {
      const { data: pf } = await admin.from("perfiles").select("persona_id").eq("user_id", u.id).maybeSingle();
      const dest = await destinatarios([], pf?.persona_id ? [pf.persona_id] : []);
      if (!dest.length && u.email && !u.email.endsWith("@arcorios.app")) dest.push({ nombre: "", email: u.email });
      if (!dest.length) return resp({ error: "No tienes correo guardado. Agrégalo en Mi perfil." }, 400);
      const n = await enviar(dest, "Correos de Arco Ríos ✓", plantilla("Correos activados ✓", "<p style=\"margin:0\">Así te llegarán los recordatorios y el resumen de la reunión del Consejo.</p>"));
      await registrar("prueba", "Prueba", n, dest[0].email);
      return resp({ enviados: n, a: dest[0].email });
    }
    if (body.accion === "vista_resumen") {
      const r = await armarResumen(hoy);
      const dest = await destinatarios(["consejo"], []);
      return resp({ ...r, para: dest.map((d) => d.nombre) });
    }
    if (body.accion === "enviar_resumen") return resp(await enviarResumen(hoy, true));
    if (body.accion === "enviar_recordatorio") return resp({ enviados: await enviarRecordatorio(Number(body.id)) });

    return resp({ error: "Acción desconocida" }, 400);
  } catch (e) {
    console.error(e);
    return resp({ error: (e as Error).message || String(e) }, 500);
  }
});
