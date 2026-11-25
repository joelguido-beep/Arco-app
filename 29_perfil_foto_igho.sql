-- =====================================================================
-- 29 · Foto y categorías del IGHO, Mi perfil, solicitudes de ministerio
--  1. Foto del IGHO (la sube el líder; sale a la izquierda de la tarjeta)
--  2. Categorías del IGHO: «Espacio para niños», «IGHO -18 años»
--  3. Mi perfil: ver y corregir mis datos
--  4. Pedir acceso a un ministerio → el administrador aprueba o rechaza
-- Ejecutar después de 28_mi_igho_tarjeta_visitas.sql: SQL Editor → New query → Run
-- Se puede volver a ejecutar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Foto del IGHO (imagen pequeña ya recortada, guardada como texto)
-- ---------------------------------------------------------------------
create table if not exists igho_fotos (
  igho_id         uuid primary key references igho(id) on delete cascade,
  imagen          text not null,                 -- data:image/jpeg;base64,…
  actualizado_en  timestamptz not null default now(),
  actualizado_por text
);
alter table igho_fotos enable row level security;
grant select on igho_fotos to authenticated;
grant all on igho_fotos to service_role;
drop policy if exists "ven fotos igho" on igho_fotos;
create policy "ven fotos igho" on igho_fotos for select to authenticated using (true);

create or replace function public.guardar_foto_igho(p_igho uuid, p_imagen text, p_quien text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (p_igho in (select public.mis_ighos()) or public.es_anciano_o_admin()) then raise exception 'Sin permiso'; end if;
  if p_imagen is null or p_imagen = '' then
    delete from igho_fotos where igho_id = p_igho; return;
  end if;
  if p_imagen not like 'data:image/%' or length(p_imagen) > 900000 then raise exception 'Imagen no válida o muy grande'; end if;
  insert into igho_fotos (igho_id, imagen, actualizado_en, actualizado_por) values (p_igho, p_imagen, now(), p_quien)
  on conflict (igho_id) do update set imagen = excluded.imagen, actualizado_en = now(), actualizado_por = excluded.actualizado_por;
end $$;
grant execute on function public.guardar_foto_igho(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Categorías del IGHO
-- ---------------------------------------------------------------------
alter table igho add column if not exists categorias text[] not null default '{}';

create or replace function public.guardar_categorias_igho(p_igho uuid, p_cats text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (p_igho in (select public.mis_ighos()) or public.es_anciano_o_admin()) then raise exception 'Sin permiso'; end if;
  update igho set categorias = array(select distinct c from unnest(coalesce(p_cats, '{}')) c where c in ('ninos', 'menores18'))
  where id = p_igho;
end $$;
grant execute on function public.guardar_categorias_igho(uuid, text[]) to authenticated;

-- El Stand y Bienvenida reciben también las categorías
drop function if exists public.stand_ighos();
create function public.stand_ighos()
returns table (id uuid, nombre text, lider text, lider_tel text, ubicacion text, lider_con_app boolean,
               direccion text, horario text, mapas text[], presentacion text, categorias text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.puede_conectar_igho() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  return query
    select g.id, g.nombre, btrim(p.nombres || ' ' || coalesce(split_part(p.apellidos, ' ', 1), '')), p.telefono, g.ubicacion,
           exists (select 1 from usuarios_roles ur where ur.rol = 'lider_igho' and ur.igho_id = g.id)
             or exists (select 1 from perfiles pf where pf.persona_id = g.lider_persona_id),
           g.direccion, g.horario, g.mapas, g.presentacion, g.categorias
    from igho g left join personas p on p.id = g.lider_persona_id
    where g.activo order by g.nombre;
end $$;
grant execute on function public.stand_ighos() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Mi perfil
-- ---------------------------------------------------------------------
create or replace function public.mis_datos()
returns table (persona_id uuid, nombres text, apellidos text, telefono text, fecha_nacimiento date)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombres, p.apellidos, p.telefono, p.fecha_nacimiento
  from perfiles pf join personas p on p.id = pf.persona_id where pf.user_id = auth.uid();
$$;
grant execute on function public.mis_datos() to authenticated;

create or replace function public.guardar_mis_datos(p_nombres text, p_apellidos text, p_telefono text, p_fecha_nacimiento date)
returns void language plpgsql security definer set search_path = public as $$
declare v_p uuid;
begin
  select persona_id into v_p from perfiles where user_id = auth.uid();
  if v_p is null then raise exception 'Tu cuenta no está unida a una persona de la base. Pide ayuda al administrador.'; end if;
  if coalesce(btrim(p_nombres), '') = '' then raise exception 'Escribe tu nombre'; end if;
  update personas set nombres = btrim(p_nombres), apellidos = nullif(btrim(p_apellidos), ''),
         telefono = nullif(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), ''),
         fecha_nacimiento = p_fecha_nacimiento,
         anio_nacimiento_aprox = coalesce(extract(year from p_fecha_nacimiento)::int, anio_nacimiento_aprox)
  where id = v_p;
end $$;
grant execute on function public.guardar_mis_datos(text, text, text, date) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Solicitudes para servir en un ministerio
-- ---------------------------------------------------------------------
create table if not exists solicitudes_ministerio (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  nombre        text,
  ministerio    text not null,                      -- código: kidz, worship, anfitriones…
  mensaje       text,
  estado        text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  nivel         text,                               -- servidor | lider_ministerio (al aprobar)
  creado_en     timestamptz not null default now(),
  resuelto_por  text,
  resuelto_en   timestamptz
);
create index if not exists solicitudes_ministerio_estado_idx on solicitudes_ministerio (estado, creado_en);
alter table solicitudes_ministerio enable row level security;
grant select on solicitudes_ministerio to authenticated;
grant all on solicitudes_ministerio to service_role;
drop policy if exists "ve sus solicitudes" on solicitudes_ministerio;
create policy "ve sus solicitudes" on solicitudes_ministerio for select to authenticated
  using (user_id = auth.uid() or public.tiene_rol('admin'));

-- Los avisos pueden ser también de tipo «solicitud»
alter table notificaciones drop constraint if exists notificaciones_tipo_check;
alter table notificaciones add constraint notificaciones_tipo_check check (tipo in ('aviso', 'servicio', 'igho', 'solicitud'));

create or replace function public.solicitar_ministerio(p_ministerio text, p_mensaje text, p_nombre text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_n bigint; n int; v_min text;
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  select nombre into v_min from ministerios where codigo = p_ministerio;
  if v_min is null then raise exception 'Elige un ministerio'; end if;
  if exists (select 1 from solicitudes_ministerio where user_id = auth.uid() and ministerio = p_ministerio and estado = 'pendiente') then
    raise exception 'Ya pediste servir en este ministerio; el administrador lo está revisando.';
  end if;
  insert into solicitudes_ministerio (user_id, nombre, ministerio, mensaje) values (auth.uid(), p_nombre, p_ministerio, nullif(btrim(p_mensaje), ''))
  returning id into v_id;
  insert into notificaciones (titulo, cuerpo, destino, ir_a, tipo, creado_por, creado_por_nombre)
  values ('Solicitud para servir en ' || v_min, coalesce(p_nombre, 'Alguien') || ' pidió acceso a ' || v_min || '.'
            || coalesce(E'\n«' || nullif(btrim(p_mensaje), '') || '»', ''),
          'admin', 'admin', 'solicitud', auth.uid(), coalesce(p_nombre, ''))
  returning id into v_n;
  insert into notificaciones_usuarios (notificacion_id, user_id)
    select v_n, ur.user_id from usuarios_roles ur where ur.rol = 'admin' on conflict do nothing;
  get diagnostics n = row_count;
  update notificaciones set personas = n where id = v_n;
  return jsonb_build_object('id', v_id, 'aviso', v_n, 'personas', n);
end $$;
grant execute on function public.solicitar_ministerio(text, text, text) to authenticated;

-- El administrador aprueba (como siervo o líder) o rechaza; la persona recibe un aviso
create or replace function public.resolver_solicitud(p_id bigint, p_aprobar boolean, p_nivel text, p_quien text)
returns void language plpgsql security definer set search_path = public as $$
declare s record; v_min uuid; v_nmin text; v_n bigint;
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador'; end if;
  select * into s from solicitudes_ministerio where id = p_id;
  if s is null then raise exception 'No se encontró la solicitud'; end if;
  select id, nombre into v_min, v_nmin from ministerios where codigo = s.ministerio;
  if p_aprobar then
    if p_nivel not in ('servidor', 'lider_ministerio') then raise exception 'Elige siervo o líder'; end if;
    if not exists (select 1 from usuarios_roles where user_id = s.user_id and ministerio_id = v_min and rol = p_nivel::rol_t) then
      insert into usuarios_roles (user_id, rol, ministerio_id) values (s.user_id, p_nivel::rol_t, v_min);
    end if;
  end if;
  update solicitudes_ministerio set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
         nivel = case when p_aprobar then p_nivel end, resuelto_por = p_quien, resuelto_en = now()
  where id = p_id;
  insert into notificaciones (titulo, cuerpo, destino, ir_a, tipo, creado_por, creado_por_nombre, personas)
  values (case when p_aprobar then '¡Ya puedes servir en ' || v_nmin || '! 🙌' else 'Tu solicitud para ' || v_nmin end,
          case when p_aprobar then 'Abre la app de nuevo para ver la página de ' || v_nmin || '.'
               else 'Por ahora no se aprobó. Habla con el líder del ministerio o con un anciano.' end,
          'solicitud', case when p_aprobar then (case s.ministerio when 'anuncios' then 'domingo' else s.ministerio end) end, 'solicitud', auth.uid(), coalesce(p_quien, ''), 1)
  returning id into v_n;
  insert into notificaciones_usuarios (notificacion_id, user_id) values (v_n, s.user_id) on conflict do nothing;
end $$;
grant execute on function public.resolver_solicitud(bigint, boolean, text, text) to authenticated;
