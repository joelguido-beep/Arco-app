-- =====================================================================
-- 28 · Mi IGHO por mosaicos
--  1. Rol de cada persona en su IGHO: líder, apoyo, anfitrión, asistente
--  2. Tarjeta del IGHO para compartir (presentación); el Stand y Bienvenida
--     la reciben para el WhatsApp a la persona
--  3. Visitas en la asistencia: el esposo/a de cada miembro del Consejo se
--     elige en Administración, y quien tenga «todos los IGHO» (el anciano
--     presidente) aparece en la asistencia de cada IGHO
-- Ejecutar después de 27_clase_bienvenida.sql: SQL Editor → New query → Run
-- Se puede volver a ejecutar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Rol en el IGHO
-- ---------------------------------------------------------------------
alter table personas add column if not exists igho_rol text;
alter table personas drop constraint if exists personas_igho_rol_check;
alter table personas add constraint personas_igho_rol_check check (igho_rol in ('lider', 'apoyo', 'anfitrion', 'asistente'));
-- El líder de cada IGHO empieza como «Líder»
update personas p set igho_rol = 'lider' from igho g where g.lider_persona_id = p.id and p.igho_rol is null;

create or replace function public.guardar_rol_igho(p_persona uuid, p_rol text)
returns void language plpgsql security definer set search_path = public as $$
declare v_igho uuid;
begin
  select igho_id into v_igho from personas where id = p_persona;
  if v_igho is null then raise exception 'Esta persona no está en un IGHO'; end if;
  if not (v_igho in (select public.mis_ighos()) or public.es_anciano_o_admin()) then raise exception 'Sin permiso'; end if;
  if p_rol is not null and p_rol not in ('lider', 'apoyo', 'anfitrion', 'asistente') then raise exception 'Rol no válido'; end if;
  update personas set igho_rol = p_rol where id = p_persona;
end $$;
grant execute on function public.guardar_rol_igho(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Tarjeta del IGHO
-- ---------------------------------------------------------------------
alter table igho add column if not exists presentacion text;

create or replace function public.guardar_tarjeta_igho(p_igho uuid, p_presentacion text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (p_igho in (select public.mis_ighos()) or public.es_anciano_o_admin()) then raise exception 'Sin permiso'; end if;
  update igho set presentacion = nullif(btrim(p_presentacion), '') where id = p_igho;
end $$;
grant execute on function public.guardar_tarjeta_igho(uuid, text) to authenticated;

-- El Stand y Bienvenida reciben también la presentación
drop function if exists public.stand_ighos();
create function public.stand_ighos()
returns table (id uuid, nombre text, lider text, lider_tel text, ubicacion text, lider_con_app boolean,
               direccion text, horario text, mapas text[], presentacion text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.puede_conectar_igho() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  return query
    select g.id, g.nombre, btrim(p.nombres || ' ' || coalesce(split_part(p.apellidos, ' ', 1), '')), p.telefono, g.ubicacion,
           exists (select 1 from usuarios_roles ur where ur.rol = 'lider_igho' and ur.igho_id = g.id)
             or exists (select 1 from perfiles pf where pf.persona_id = g.lider_persona_id),
           g.direccion, g.horario, g.mapas, g.presentacion
    from igho g left join personas p on p.id = g.lider_persona_id
    where g.activo order by g.nombre;
end $$;
grant execute on function public.stand_ighos() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Visitas del Consejo en la asistencia del IGHO
-- ---------------------------------------------------------------------
create table if not exists consejo_visitantes (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  conyuge_persona_id  uuid references personas(id) on delete set null,
  todos_los_igho      boolean not null default false,
  actualizado_en      timestamptz not null default now()
);
-- sin_conyuge: su esposo/a NO aparece en la asistencia (no asiste a los IGHO por ahora)
alter table consejo_visitantes add column if not exists sin_conyuge boolean not null default false;
alter table consejo_visitantes enable row level security;
grant select on consejo_visitantes to authenticated;
grant all on consejo_visitantes to service_role;
drop policy if exists "consejo ve visitantes" on consejo_visitantes;
create policy "consejo ve visitantes" on consejo_visitantes for select to authenticated using (public.es_anciano_o_admin());

-- Administración: esposo/a de un miembro del Consejo y si visita todos los IGHO
drop function if exists public.guardar_visitante_consejo(uuid, uuid, boolean);
create or replace function public.guardar_visitante_consejo(p_user uuid, p_conyuge uuid, p_todos boolean, p_sin_conyuge boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_yo uuid;
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador'; end if;
  insert into consejo_visitantes (user_id, conyuge_persona_id, todos_los_igho, sin_conyuge, actualizado_en)
  values (p_user, p_conyuge, coalesce(p_todos, false), coalesce(p_sin_conyuge, false), now())
  on conflict (user_id) do update set conyuge_persona_id = excluded.conyuge_persona_id, todos_los_igho = excluded.todos_los_igho,
                                      sin_conyuge = excluded.sin_conyuge, actualizado_en = now();
  -- También queda en el árbol familiar
  select persona_id into v_yo from perfiles where user_id = p_user;
  if v_yo is not null and p_conyuge is not null and v_yo <> p_conyuge then
    insert into parentescos (persona_a, persona_b, tipo) values (least(v_yo, p_conyuge), greatest(v_yo, p_conyuge), 'conyuge')
    on conflict do nothing;
  end if;
end $$;
grant execute on function public.guardar_visitante_consejo(uuid, uuid, boolean, boolean) to authenticated;

-- Esposo/a actual de un usuario (el elegido en Administración o, si no, el del árbol familiar)
drop function if exists public.conyuge_de_usuario(uuid);
create or replace function public.conyuge_de_usuario(p_user uuid)
returns table (persona_id uuid, nombre text, todos_los_igho boolean, sin_conyuge boolean)
language sql stable security definer set search_path = public as $$
  select x.pid, btrim(p.nombres || ' ' || coalesce(p.apellidos, '')), coalesce(cv.todos_los_igho, false), coalesce(cv.sin_conyuge, false)
  from (select coalesce(
          (select conyuge_persona_id from consejo_visitantes where user_id = p_user),
          (select case when k.persona_a = pf.persona_id then k.persona_b else k.persona_a end
             from perfiles pf join parentescos k on k.tipo = 'conyuge' and pf.persona_id in (k.persona_a, k.persona_b)
             where pf.user_id = p_user limit 1)) as pid) x
  left join personas p on p.id = x.pid
  left join consejo_visitantes cv on cv.user_id = p_user
  where public.tiene_rol('admin');
$$;
grant execute on function public.conyuge_de_usuario(uuid) to authenticated;

-- Quién aparece como visita en la asistencia de un IGHO:
-- la cobertura de ese IGHO y quien visita todos los IGHO, cada uno con su esposo/a
drop function if exists public.cobertura_de_igho(uuid, date);
create function public.cobertura_de_igho(p_igho uuid, p_fecha date)
returns table (persona_id uuid, nombre text, user_id uuid, es_conyuge boolean, vino boolean, tipo text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.puede_igho(p_igho) then raise exception 'Sin permiso'; end if;
  return query
  with usuarios as (
    select distinct on (u.uid) u.uid, u.tipo from (
      select c.user_id as uid, 'cobertura'::text as tipo, 1 as orden from cobertura_consejo c where c.igho_id = p_igho
      union all
      select v.user_id, 'presidente', 2 from consejo_visitantes v where v.todos_los_igho
    ) u order by u.uid, u.orden
  ), cons as (
    select us.uid, us.tipo, pf.persona_id from usuarios us join perfiles pf on pf.user_id = us.uid where pf.persona_id is not null
  ), todos as (
    select cons.persona_id as pid, cons.uid, false as conyuge, cons.tipo from cons
    union
    select cv.conyuge_persona_id, cons.uid, true, cons.tipo
      from cons join consejo_visitantes cv on cv.user_id = cons.uid where cv.conyuge_persona_id is not null and not cv.sin_conyuge
    union
    select case when k.persona_a = cons.persona_id then k.persona_b else k.persona_a end, cons.uid, true, cons.tipo
      from cons join parentescos k on k.tipo = 'conyuge' and (k.persona_a = cons.persona_id or k.persona_b = cons.persona_id)
      where not exists (select 1 from consejo_visitantes cv where cv.user_id = cons.uid and (cv.conyuge_persona_id is not null or cv.sin_conyuge))
  ), unicos as (
    select distinct on (t.pid) t.pid, t.uid, t.conyuge, t.tipo from todos t order by t.pid, t.conyuge, t.tipo
  )
  select t.pid, btrim(p.nombres || ' ' || coalesce(p.apellidos, '')), t.uid, t.conyuge,
    exists (select 1 from visitas_igho v where v.igho_id = p_igho and v.fecha = p_fecha and t.pid = any(v.personas)),
    t.tipo
  from unicos t join personas p on p.id = t.pid
  where p.igho_id is distinct from p_igho        -- si ya es miembro del IGHO, se marca como miembro
  order by t.tipo, t.uid, t.conyuge;
end $$;
grant execute on function public.cobertura_de_igho(uuid, date) to authenticated;

-- Guarda las visitas marcadas en la asistencia (reemplaza las de esa fecha)
create or replace function public.registrar_visitas_cobertura(p_igho uuid, p_fecha date, p_personas uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.puede_igho(p_igho) then raise exception 'Sin permiso'; end if;
  delete from visitas_igho where igho_id = p_igho and fecha = p_fecha and origen = 'asistencia';
  for r in
    select x.user_id, array_agg(x.persona_id) as ps, string_agg(x.nombre, ' y ' order by x.es_conyuge) as nombres
    from public.cobertura_de_igho(p_igho, p_fecha) x
    where x.persona_id = any(coalesce(p_personas, '{}'))
    group by x.user_id
  loop
    insert into visitas_igho (igho_id, fecha, user_id, nombre, personas, origen, notas)
    values (p_igho, p_fecha, r.user_id, r.nombres, r.ps, 'asistencia', 'Registrada en la asistencia del IGHO');
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.registrar_visitas_cobertura(uuid, date, uuid[]) to authenticated;

-- Joel Guido (anciano presidente) aparece en la asistencia de todos los IGHO
-- (su esposa no aparece: no asiste a los IGHO por ahora)
insert into consejo_visitantes (user_id, todos_los_igho, sin_conyuge)
select pf.user_id, true, true from perfiles pf join personas p on p.id = pf.persona_id
where public.fam_norm(p.nombres) like 'joel%' and public.fam_norm(p.apellidos) like 'guido%'
on conflict (user_id) do update set todos_los_igho = true, sin_conyuge = true, actualizado_en = now();

-- Revisa: quién visita todos los IGHO (y si su esposo/a aparece)
select p.nombres || ' ' || coalesce(p.apellidos, '') as visita_todos_los_igho,
       case when cv.sin_conyuge then 'no aparece' else 'aparece si está en el árbol familiar' end as esposo_a
from consejo_visitantes cv join perfiles pf on pf.user_id = cv.user_id join personas p on p.id = pf.persona_id
where cv.todos_los_igho;
