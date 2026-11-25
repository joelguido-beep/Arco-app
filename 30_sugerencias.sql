-- =====================================================================
-- 30 · Sugerencias de quienes prueban la app
-- Botón 💬 arriba a la derecha en cada página → el mensaje llega a
-- Administración → Sugerencias (y a la campana de los administradores).
-- Ejecutar después de 29_perfil_foto_igho.sql: SQL Editor → New query → Run
-- Se puede volver a ejecutar.
-- =====================================================================

create table if not exists sugerencias_app (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users(id) on delete set null,
  nombre      text,
  pagina      text,                 -- página y sección donde estaba (ej.: «Mi IGHO › Asistencia»)
  texto       text not null check (length(btrim(texto)) > 0),
  version     text,                 -- versión de la app
  estado      text not null default 'nueva' check (estado in ('nueva', 'hecha', 'descartada')),
  nota_admin  text,
  creado_en   timestamptz not null default now(),
  resuelto_en timestamptz
);
create index if not exists sugerencias_app_estado_idx on sugerencias_app (estado, creado_en desc);
alter table sugerencias_app enable row level security;
grant select on sugerencias_app to authenticated;
grant all on sugerencias_app to service_role;
drop policy if exists "admin ve sugerencias" on sugerencias_app;
create policy "admin ve sugerencias" on sugerencias_app for select to authenticated
  using (public.tiene_rol('admin') or user_id = auth.uid());

alter table notificaciones drop constraint if exists notificaciones_tipo_check;
alter table notificaciones add constraint notificaciones_tipo_check check (tipo in ('aviso', 'servicio', 'igho', 'solicitud', 'sugerencia'));

-- Cualquier usuario con cuenta envía una sugerencia; los administradores reciben el aviso en la campana
create or replace function public.enviar_sugerencia(p_texto text, p_pagina text, p_nombre text, p_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_n bigint; n int;
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if coalesce(btrim(p_texto), '') = '' then raise exception 'Escribe tu sugerencia'; end if;
  insert into sugerencias_app (user_id, nombre, pagina, texto, version)
  values (auth.uid(), nullif(btrim(p_nombre), ''), nullif(btrim(p_pagina), ''), left(btrim(p_texto), 2000), p_version)
  returning id into v_id;
  insert into notificaciones (titulo, cuerpo, destino, ir_a, tipo, creado_por, creado_por_nombre)
  values ('💬 Sugerencia: ' || coalesce(nullif(btrim(p_pagina), ''), 'la app'),
          coalesce(nullif(btrim(p_nombre), ''), 'Alguien') || ': «' || left(btrim(p_texto), 160) || case when length(btrim(p_texto)) > 160 then '…' else '' end || '»',
          'admin', 'admin', 'sugerencia', auth.uid(), coalesce(p_nombre, ''))
  returning id into v_n;
  insert into notificaciones_usuarios (notificacion_id, user_id)
    select v_n, ur.user_id from usuarios_roles ur where ur.rol = 'admin' and ur.user_id <> auth.uid() on conflict do nothing;
  get diagnostics n = row_count;
  update notificaciones set personas = n where id = v_n;
  return jsonb_build_object('id', v_id, 'aviso', v_n);
end $$;
grant execute on function public.enviar_sugerencia(text, text, text, text) to authenticated;

-- Administración: marcar hecha / descartada / nueva, con nota opcional; o borrar
create or replace function public.estado_sugerencia(p_id bigint, p_estado text, p_nota text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador'; end if;
  if p_estado = 'borrar' then delete from sugerencias_app where id = p_id; return; end if;
  if p_estado not in ('nueva', 'hecha', 'descartada') then raise exception 'Estado no válido'; end if;
  update sugerencias_app set estado = p_estado, nota_admin = coalesce(nullif(btrim(p_nota), ''), nota_admin),
         resuelto_en = case when p_estado = 'nueva' then null else now() end
  where id = p_id;
end $$;
grant execute on function public.estado_sugerencia(bigint, text, text) to authenticated;
