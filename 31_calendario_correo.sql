-- =====================================================================
-- 31 · Calendario del Consejo, recordatorios por correo, agenda de la
--      Reunión del Consejo (Tarea / Decisión / Reporte) y resumen del lunes
-- Ejecutar después de 30_sugerencias.sql: SQL Editor → New query → Run
-- Se puede volver a ejecutar.
-- Los correos los envía la Edge Function «correo» (correo.ts) con Resend.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Correo de cada persona
-- ---------------------------------------------------------------------
alter table personas add column if not exists email text;

-- Mi perfil: leer / guardar mi correo
create or replace function public.mi_correo() returns text
language sql stable security definer set search_path = public as $$
  select p.email from perfiles pf join personas p on p.id = pf.persona_id where pf.user_id = auth.uid();
$$;
grant execute on function public.mi_correo() to authenticated;

create or replace function public.guardar_mi_correo(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare v_p uuid; v_e text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  select persona_id into v_p from perfiles where user_id = auth.uid();
  if v_p is null then raise exception 'Tu cuenta no está unida a una persona de la base. Pide ayuda al administrador.'; end if;
  if v_e is not null and v_e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Ese correo no parece válido'; end if;
  update personas set email = v_e where id = v_p;
end $$;
grant execute on function public.guardar_mi_correo(text) to authenticated;

-- Administración: correos del Consejo y de los líderes (admin o secretaría)
create or replace function public.correos_equipo()
returns table (persona_id uuid, nombre text, roles text, email text, email_cuenta text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.tiene_rol('admin') or public.tiene_rol('secretaria')) then raise exception 'Solo el administrador o secretaría'; end if;
  return query
  select p.id, btrim(p.nombres || ' ' || coalesce(p.apellidos, '')),
         string_agg(distinct case ur.rol::text
           when 'admin' then 'Administrador' when 'anciano' then 'Consejo' when 'secretaria' then 'Secretaría'
           when 'finanzas' then 'Finanzas' when 'lider_igho' then 'Líder de IGHO'
           when 'lider_ministerio' then 'Líder ' || coalesce(m.codigo, '') when 'servidor' then 'Siervo ' || coalesce(m.codigo, '')
           else ur.rol::text end, ', '),
         p.email,
         max(case when u.email not like '%@arcorios.app' then u.email end)
  from usuarios_roles ur
  join perfiles pf on pf.user_id = ur.user_id
  join personas p on p.id = pf.persona_id
  left join ministerios m on m.id = ur.ministerio_id
  left join auth.users u on u.id = ur.user_id
  where ur.rol::text in ('admin', 'anciano', 'secretaria', 'finanzas', 'lider_ministerio', 'lider_igho')
  group by p.id, p.nombres, p.apellidos, p.email
  order by 2;
end $$;
grant execute on function public.correos_equipo() to authenticated;

create or replace function public.guardar_correo_persona(p_persona uuid, p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare v_e text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  if not (public.tiene_rol('admin') or public.tiene_rol('secretaria')) then raise exception 'Solo el administrador o secretaría'; end if;
  if v_e is not null and v_e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Ese correo no parece válido'; end if;
  update personas set email = v_e where id = p_persona;
end $$;
grant execute on function public.guardar_correo_persona(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Calendario
-- ---------------------------------------------------------------------
create table if not exists cal_eventos (
  id           bigint generated always as identity primary key,
  titulo       text not null check (length(btrim(titulo)) > 0),
  tipo         text not null default 'evento' check (tipo in ('evento', 'actividad', 'predica', 'reunion', 'otro')),
  fecha        date not null,
  hora         time,
  fecha_fin    date,
  lugar        text,
  ministerio   text,                 -- código del ministerio responsable (opcional)
  responsable  text,                 -- quién lo lleva / quién predica
  descripcion  text,
  creado_por_nombre text,
  creado_en    timestamptz not null default now()
);
create index if not exists cal_eventos_fecha_idx on cal_eventos (fecha);

-- Recordatorios por correo de cada evento
create table if not exists cal_recordatorios (
  id          bigint generated always as identity primary key,
  evento_id   bigint not null references cal_eventos(id) on delete cascade,
  clase       text not null default 'anunciar' check (clase in ('anunciar', 'planificar', 'otro')),
  cuando      text,                  -- cómo se eligió: miercoles2 | 1s | 2s | p4 | p6 | p8 | fecha
  envio       date not null,         -- día en que sale (a las 7:00 de Ecuador)
  destinos    text[] not null default '{}',   -- consejo | lideres_min | min:<codigo> | lideres_igho
  personas    uuid[] not null default '{}',   -- personas elegidas una por una
  mensaje     text,
  enviado_en  timestamptz,
  enviados    int,
  error       text,
  creado_en   timestamptz not null default now()
);
create index if not exists cal_recordatorios_envio_idx on cal_recordatorios (envio) where enviado_en is null;

-- ---------------------------------------------------------------------
-- 3. Reunión del Consejo: agenda, reuniones y vencimiento de pendientes
-- ---------------------------------------------------------------------
alter table consejo_tareas add column if not exists vence date;

create table if not exists consejo_reuniones (
  fecha   date primary key,
  tipo    text not null default 'Consejo' check (tipo in ('Consejo', 'Consejo ampliado', 'No hay reunión')),
  hora    time,
  lugar   text,
  notas   text,
  resumen_enviado_en timestamptz
);

-- Cuándo se reúne normalmente (una sola fila)
create table if not exists consejo_config (
  id          int primary key default 1 check (id = 1),
  dia_semana  int check (dia_semana between 0 and 6),   -- 0 = domingo … 6 = sábado
  hora        time,
  tipo        text not null default 'Consejo',
  lugar       text,
  resumen_lunes boolean not null default true
);
insert into consejo_config (id) values (1) on conflict do nothing;

create table if not exists consejo_agenda (
  id           bigint generated always as identity primary key,
  titulo       text not null check (length(btrim(titulo)) > 0),
  detalle      text,
  categoria    text not null default 'tarea' check (categoria in ('tarea', 'decision', 'reporte')),
  reunion_fecha date,                -- null = la próxima reunión
  estado       text not null default 'pendiente' check (estado in ('pendiente', 'tratado', 'descartado')),
  quien        text,                 -- quién lo presenta
  creado_por_nombre text,
  creado_en    timestamptz not null default now(),
  tratado_en   date
);
create index if not exists consejo_agenda_estado_idx on consejo_agenda (estado, reunion_fecha);

-- Registro de correos enviados
create table if not exists correos_enviados (
  id         bigint generated always as identity primary key,
  tipo       text not null,          -- recordatorio | resumen | prueba
  asunto     text,
  personas   int,
  detalle    text,
  creado_en  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4. Permisos: Consejo y admin
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['cal_eventos', 'cal_recordatorios', 'consejo_reuniones', 'consejo_config', 'consejo_agenda', 'correos_enviados'] loop
    execute format('alter table %I enable row level security', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('drop policy if exists "consejo maneja" on %I', t);
    execute format('create policy "consejo maneja" on %I for all to authenticated using (public.es_anciano_o_admin()) with check (public.es_anciano_o_admin())', t);
  end loop;
end $$;
-- La Edge Function lee también los pendientes y el programa del domingo
grant select on consejo_tareas, programa_domingo, personas, perfiles, usuarios_roles to service_role;

-- ---------------------------------------------------------------------
-- 5. ¿A quién le llega? (lo usa la Edge Function con service_role)
--    Usuarios: correo de su persona, o el de su cuenta si es un correo real.
-- ---------------------------------------------------------------------
create or replace function public.correo_destinatarios(p_destinos text[], p_personas uuid[])
returns table (nombre text, email text)
language sql stable security definer set search_path = public as $$
  with usuarios as (
    select ur.user_id from usuarios_roles ur where 'consejo' = any(p_destinos) and ur.rol::text in ('admin', 'anciano')
    union select ur.user_id from usuarios_roles ur where 'lideres_min' = any(p_destinos) and ur.rol::text = 'lider_ministerio'
    union select ur.user_id from usuarios_roles ur join ministerios m on m.id = ur.ministerio_id
           where ur.rol::text = 'lider_ministerio' and ('min:' || m.codigo) = any(p_destinos)
    union select ur.user_id from usuarios_roles ur where 'lideres_igho' = any(p_destinos) and ur.rol::text = 'lider_igho'
  ),
  todos as (
    select btrim(p.nombres || ' ' || coalesce(p.apellidos, '')) as nombre,
           coalesce(p.email, case when au.email not like '%@arcorios.app' then au.email end) as email
    from usuarios u
    left join perfiles pf on pf.user_id = u.user_id
    left join personas p on p.id = pf.persona_id
    left join auth.users au on au.id = u.user_id
    union all
    select btrim(p.nombres || ' ' || coalesce(p.apellidos, '')), p.email
    from personas p where p.id = any(p_personas)
  )
  select distinct on (lower(email)) coalesce(nullif(nombre, ''), email), lower(email)
  from todos where email is not null and email like '%@%'
  order by lower(email), nombre;
$$;
revoke all on function public.correo_destinatarios(text[], uuid[]) from public, anon, authenticated;
grant execute on function public.correo_destinatarios(text[], uuid[]) to service_role;

-- La app muestra cuántos tienen correo antes de guardar un recordatorio
create or replace function public.contar_destinatarios(p_destinos text[], p_personas uuid[])
returns table (con_correo int, nombres text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.es_anciano_o_admin() then raise exception 'Solo el Consejo'; end if;
  return query select count(*)::int, string_agg(d.nombre, ', ' order by d.nombre)
    from public.correo_destinatarios(p_destinos, p_personas) d;
end $$;
grant execute on function public.contar_destinatarios(text[], uuid[]) to authenticated;

-- Quiénes del equipo NO tienen correo (para pedírselo)
create or replace function public.sin_correo(p_destinos text[])
returns table (nombre text)
language sql stable security definer set search_path = public as $$
  select distinct btrim(p.nombres || ' ' || coalesce(p.apellidos, ''))
  from usuarios_roles ur
  left join ministerios m on m.id = ur.ministerio_id
  join perfiles pf on pf.user_id = ur.user_id
  join personas p on p.id = pf.persona_id
  left join auth.users au on au.id = ur.user_id
  where public.es_anciano_o_admin()
    and p.email is null and (au.email is null or au.email like '%@arcorios.app')
    and (('consejo' = any(p_destinos) and ur.rol::text in ('admin', 'anciano'))
      or ('lideres_min' = any(p_destinos) and ur.rol::text = 'lider_ministerio')
      or (ur.rol::text = 'lider_ministerio' and ('min:' || m.codigo) = any(p_destinos))
      or ('lideres_igho' = any(p_destinos) and ur.rol::text = 'lider_igho'));
$$;
grant execute on function public.sin_correo(text[]) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Cron: todos los días a las 7:00 de Ecuador (12:00 UTC).
--    Envía los recordatorios del día; los lunes, también el resumen de la reunión.
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;
do $$
begin
  if exists (select 1 from cron.job where jobname = 'correo-diario') then perform cron.unschedule('correo-diario'); end if;
end $$;
select cron.schedule('correo-diario', '0 12 * * *', $cron$
  select net.http_post(
    url := 'https://lmitwnfvelwbbkjkvmtb.supabase.co/functions/v1/correo',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secreto', (select valor from public.ajustes_privados where clave = 'cron_secreto')),
    body := jsonb_build_object('accion', 'diario'),
    timeout_milliseconds := 60000);
$cron$);
