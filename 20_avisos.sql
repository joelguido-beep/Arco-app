-- =====================================================================
-- 20 · Avisos (notificaciones)
--  · El administrador y el Consejo envían un aviso a toda la iglesia o a
--    un grupo («Este domingo no nos reunimos aquí»).
--  · Cada sábado a las 20:00 (hora de Ecuador) cada siervo recibe
--    «Mañana sirves en…» según Worship, Kidz y Anuncios.
--  · Llegan como notificación al teléfono (si la persona las activó) y
--    siempre quedan en la campana de la app.
-- ANTES de ejecutar: crear la Edge Function «notificar» (ver la guía).
-- Ejecutar una vez: Supabase → SQL Editor → New query → Run
-- =====================================================================

create table if not exists notificaciones (
  id                 bigint generated always as identity primary key,
  titulo             text not null check (length(btrim(titulo)) > 0),
  cuerpo             text,
  destino            text not null,          -- todos · equipo · consejo · lideres_igho · padres · min:<código> · servicio
  ir_a               text,                   -- página que abre al tocarla (ej. domingo, kidz)
  tipo               text not null default 'aviso' check (tipo in ('aviso', 'servicio')),
  clave              text unique,            -- evita repetir el recordatorio del sábado
  creado_por         uuid default auth.uid() references auth.users(id) on delete set null,
  creado_por_nombre  text,
  creado_en          timestamptz not null default now(),
  personas           int not null default 0,
  push_enviados      int not null default 0
);
create table if not exists notificaciones_usuarios (
  notificacion_id  bigint not null references notificaciones(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  leida_en         timestamptz,
  primary key (notificacion_id, user_id)
);
create index if not exists notif_usuario_idx on notificaciones_usuarios (user_id, leida_en);

create table if not exists push_suscripciones (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  endpoint     text not null unique,
  p256dh       text not null,
  auth         text not null,
  agente       text,
  creado_en    timestamptz not null default now(),
  ultimo_uso   timestamptz
);
create index if not exists push_user_idx on push_suscripciones (user_id);

-- Claves privadas de la app (nadie las lee desde la app; solo la Edge Function)
create table if not exists ajustes_privados (clave text primary key, valor text not null);
alter table ajustes_privados enable row level security;
revoke all on ajustes_privados from anon, authenticated;
grant all on ajustes_privados to service_role;
insert into ajustes_privados (clave, valor)
  values ('cron_secreto', md5(random()::text || clock_timestamp()::text) || md5(random()::text))
  on conflict do nothing;

create or replace function public.puede_avisar() returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_anciano_o_admin();
$$;
grant execute on function public.puede_avisar() to authenticated;

alter table notificaciones          enable row level security;
alter table notificaciones_usuarios enable row level security;
alter table push_suscripciones      enable row level security;
grant select on notificaciones to authenticated;
grant select, update on notificaciones_usuarios to authenticated;
grant select, insert, update, delete on push_suscripciones to authenticated;
grant all on notificaciones, notificaciones_usuarios, push_suscripciones to service_role;

drop policy if exists "ver mis avisos" on notificaciones;
create policy "ver mis avisos" on notificaciones for select to authenticated
  using (public.puede_avisar() or exists (select 1 from notificaciones_usuarios u where u.notificacion_id = notificaciones.id and u.user_id = auth.uid()));
drop policy if exists "mis avisos" on notificaciones_usuarios;
drop policy if exists "marcar leido" on notificaciones_usuarios;
create policy "mis avisos" on notificaciones_usuarios for select to authenticated using (user_id = auth.uid() or public.puede_avisar());
create policy "marcar leido" on notificaciones_usuarios for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "mis telefonos" on push_suscripciones;
create policy "mis telefonos" on push_suscripciones for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Quiénes reciben un aviso según el destino
create or replace function public.destinatarios_aviso(p_destino text) returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from auth.users where p_destino = 'todos'
  union
  select user_id from usuarios_roles where p_destino = 'equipo'
  union
  select user_id from conyuges_consejo where p_destino in ('equipo', 'consejo')
  union
  select user_id from usuarios_roles where p_destino = 'consejo' and rol in ('admin', 'anciano')
  union
  select user_id from usuarios_roles where p_destino = 'lideres_igho' and rol = 'lider_igho'
  union
  select pf.user_id from igho i join perfiles pf on pf.persona_id = i.lider_persona_id where p_destino = 'lideres_igho' and i.activo
  union
  select user_id from kidz_familias where p_destino = 'padres' and user_id is not null
  union
  select ur.user_id from usuarios_roles ur join ministerios m on m.id = ur.ministerio_id where p_destino = 'min:' || m.codigo;
$$;
revoke all on function public.destinatarios_aviso(text) from public, anon, authenticated;

-- Crear un aviso (el envío al teléfono lo hace la Edge Function)
create or replace function public.crear_aviso(p_titulo text, p_cuerpo text, p_destino text, p_ir_a text, p_quien text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint; n int;
begin
  if not public.puede_avisar() then raise exception 'Solo el administrador y el Consejo envían avisos'; end if;
  if coalesce(btrim(p_titulo), '') = '' then raise exception 'Escribe el título del aviso'; end if;
  insert into notificaciones (titulo, cuerpo, destino, ir_a, creado_por_nombre)
  values (btrim(p_titulo), nullif(btrim(p_cuerpo), ''), p_destino, nullif(p_ir_a, ''), p_quien) returning id into v;
  insert into notificaciones_usuarios (notificacion_id, user_id)
    select v, d from public.destinatarios_aviso(p_destino) d where d is not null on conflict do nothing;
  get diagnostics n = row_count;
  update notificaciones set personas = n where id = v;
  return v;
end $$;
grant execute on function public.crear_aviso(text, text, text, text, text) to authenticated;

-- ¿Quién sirve el domingo p_fecha y dónde? (Worship, Kidz y Anuncios)
create or replace function public.servicio_del_domingo(p_fecha date)
returns table (user_id uuid, area text, detalle text, ir_a text)
language sql stable security definer set search_path = public as $$
  select pf.user_id, 'Arco Worship', string_agg(distinct we.funcion, ', '), 'worship'
    from worship_equipo we join perfiles pf on pf.persona_id = we.persona_id
    where we.fecha = p_fecha group by pf.user_id
  union all
  select kt.user_id, 'Kidz', string_agg(distinct coalesce(kc.nombre, 'clase por confirmar'), ', '), 'kidz'
    from kidz_turnos kt left join kidz_clases kc on kc.id = kt.clase_id
    where kt.fecha = p_fecha group by kt.user_id
  union all
  select u, 'Anuncios', 'Das los anuncios', 'domingo'
    from anuncios_domingo ad, unnest(coalesce(ad.anunciantes, array[ad.anunciante_user])) u
    where ad.fecha = p_fecha and u is not null;
$$;

-- Crea los recordatorios del sábado (uno por persona, con todas sus áreas).
-- No se repiten si se ejecuta dos veces. Devuelve los ids creados.
create or replace function public.crear_recordatorios_servicio(p_fecha date) returns setof bigint
language plpgsql security definer set search_path = public as $$
declare r record; v bigint;
begin
  for r in
    select s.user_id, string_agg(s.area || coalesce(' · ' || nullif(s.detalle, ''), ''), E'\n' order by s.area) as texto, min(s.ir_a) as ir_a
    from public.servicio_del_domingo(p_fecha) s where s.user_id is not null group by s.user_id
  loop
    insert into notificaciones (titulo, cuerpo, destino, ir_a, tipo, clave, creado_por, creado_por_nombre, personas)
    values ('Mañana sirves en Arco 🙌', r.texto, 'servicio', r.ir_a, 'servicio', 'servicio:' || p_fecha || ':' || r.user_id, null, 'Recordatorio automático', 1)
    on conflict (clave) do nothing returning id into v;
    if v is not null then
      insert into notificaciones_usuarios (notificacion_id, user_id) values (v, r.user_id) on conflict do nothing;
      return next v;
    end if;
  end loop;
end $$;
revoke all on function public.servicio_del_domingo(date), public.crear_recordatorios_servicio(date) from public, anon, authenticated;
grant execute on function public.servicio_del_domingo(date), public.crear_recordatorios_servicio(date) to service_role;

-- ---------------------------------------------------------------------
-- Recordatorio automático: cada sábado 20:00 en Ecuador = domingo 01:00 UTC
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'recordatorio-siervos') then
    perform cron.unschedule('recordatorio-siervos');
  end if;
end $$;

select cron.schedule('recordatorio-siervos', '0 1 * * 0', $cron$
  select net.http_post(
    url := 'https://lmitwnfvelwbbkjkvmtb.supabase.co/functions/v1/swift-action',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secreto', (select valor from public.ajustes_privados where clave = 'cron_secreto')),
    body := jsonb_build_object('accion', 'recordatorios'),
    timeout_milliseconds := 30000);
$cron$);
