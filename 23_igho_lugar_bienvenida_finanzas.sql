-- =====================================================================
-- 23 · Dirección y mapa de cada IGHO · Borrar inscripciones al IGHO ·
--      Editar / borrar personas en Bienvenida · Ingresos (Finanzas)
-- Ejecutar después de 22_stand_igho.sql: Supabase → SQL Editor → Run
-- Al final muestra qué IGHO quedaron SIN dirección (para revisarlos).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Dónde y cuándo se reúne cada IGHO
-- ---------------------------------------------------------------------
alter table igho add column if not exists direccion text;
alter table igho add column if not exists horario   text;
alter table igho add column if not exists mapas     text[];   -- uno o más enlaces de Google Maps

drop table if exists _ub;
create table _ub (tel text, nom text, ape text, direccion text, horario text, mapas text[]);
insert into _ub values
 ('0960214898','Josue','Merchan','"Plaza Roma" · Estocolmo y Copenhague','Jueves · 8:00 pm',
   array['https://maps.app.goo.gl/sKEZYBvJFnaMMLbv8']),
 ('0987525802','David','Luna','Antonio Ricaurte · Subida a Ricaurte (Camino Ricaurte)','Jueves · 8:00 a 10:00 pm · jóvenes de 12 a 14 años',
   array['https://maps.app.goo.gl/CfsB5wKrUpcsCZGj8']),
 ('0989551961','Josue','Luna','Quito y Liribamba · Wayra Plaza','Jueves · 8:00 a 10:00 pm · jóvenes de 15 a 18 años',
   array['https://maps.app.goo.gl/wWfWty6J1egeUwQG6']),
 ('0983062220','Benjamin','Lozano','Victoria del Portete y Batallón Yaguachi (Ciudadela Kennedy) · Totoracocha','Martes · 8:00 pm',
   array['https://goo.gl/maps/SxrWEXeYaPDq3BcE6']),
 ('0986256425','Santiago','Rivera','Lizardo García y Av. Paseo de los Cañaris, detrás del Carbonazo (Monay). Parquear adentro de la urbanización','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/wyw1i7bKx1hdVNKw5']),
 ('0983716104','Esteban','García','Batallón Yaguachi 2-45 y Victoria del Portete. Casa esquinera de 3 pisos. Ciudadela Kennedy','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/L8kzHB6GmEooVSba8']),
 ('0998540743','Miguel','Padilla','Calle Can Can casa 14 y vía a Paccha. Sector Ucubamba','Jueves · 8:00 pm',
   array['https://maps.app.goo.gl/hst7NcuYRMzih7wp8']),
 ('0979502983','Danny','Bermeo','Parque San Francisco, por las 4 esquinas. Barrio San Francisco de Ricaurte','Martes · 7:30 pm',
   array['https://maps.app.goo.gl/3VeAnyeLqStNnytZ7']),
 ('0980714040','Marcelo','Narváez','Av. Max Uhle 4-35, entre Rafael Donoso y Alfredo Diezcanseco. Diagonal al canchón del Consejo Provincial. Altos de la pizzería Boccapiena','Martes · 7:30 pm',
   array['https://maps.app.goo.gl/Fmw7iuw8ZnJY1N5G8']),
 ('0999193244','Germán','Cabrera','Calle Los Bocadillos y Empanadas, esquina. Sector Miraflores, barrio Santa Fe','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/LoPuBjcTwVpC5jdS7']),
 ('0993312072','Eduardo','Vélez','Atahualpa entre Hualcopo y General Eplicachima. Complejo de Totoracocha','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/BDu9CEUsuTFHwG1G8']),
 ('0998194869','Eder','Larez','Calle Moctezuma 1-21 y Av. Los Andes. En el Centro de Cuidado Infantil «Caricias»','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/k46TCxTyqvGTtzM6A']),
 ('0994024958','Justin','Cabrera','Calle Vieja entre Las Laderas y Quillán, sector Parque Jacaranda','Jueves · 8:00 pm',
   array['https://maps.app.goo.gl/B3Ruk7gpW5dtR6377']),
 ('0992270240','Rafael','Moscoso','Urbanización Vista al Río. Calle Barranquilla y Cartagena de Indias. Detrás del Hospital del IESS','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/YKpfbJkNUnnJwJJ18']),
 ('0994907123','Milton','Ortíz','Calle Cultura Imbaya y Pueblo de los Quitus (casa interior s/n). A 200 m de la Megatienda','Viernes · 8:00 pm',
   array['https://maps.app.goo.gl/s2ZJQr2fXy7xEuqHA']),
 ('0984846528','Juan','Marcano','Calle Pueblo Achuar y Av. del Bombero, diagonal al American School','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/VRVCsYHaDZMquP7r9']),
 ('0993799490','Franco','Medina','Freddy Alcívar Toro y Cultura Chaullabamba. Casa de ladrillo visto y piedra, detrás de Villa Juliana','Jueves · 8:00 pm',
   array['https://maps.app.goo.gl/MnBp8C7MEKJXYz2q8']),
 ('0978846297','Diego','Aguilar','Parque La Huaira · Luis Sojos y Vicente Cuesta','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/g21SrYPBnwgLibMC9']),
 ('0987863616','Sandro','Quito','Marco Tulio Erazo, villa #30, frente al parque dentro de la Ciudadela de los Ingenieros','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/vqiGiUhsfDvpgCTGA']),
 ('0983410415','David','Cabrera','Calle del Bombero, pasando la iglesia del pueblo de Challuabamba, a 300 m de Ferrocon. Se turnan entre dos casas: pregunta al líder cuál toca','Viernes · 8:00 pm',
   array['https://maps.app.goo.gl/FNGDVovt6fUmJDJz7','https://maps.app.goo.gl/AXy3dhwmcUfgpFE56']),
 ('0997132173','Juan Carlos','León','Calle Estocolmo y París. Calle de tierra, la segunda casa','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/y5gEF73EweRxPc2v5']),
 ('0991165847','Eugenio','Pesantez','Calle La Privada bloque 3 / 1-32 (C-5). Ingreso por González Suárez. Urbanización Río Sol','Martes · 8:00 pm',
   array['https://maps.app.goo.gl/pstMqGVENS2JH7an7']);

-- a) por el celular del líder (lo más seguro)
update igho g set direccion = u.direccion, horario = u.horario, mapas = u.mapas
from _ub u, personas p
where p.id = g.lider_persona_id and g.activo
  and right(regexp_replace(coalesce(p.telefono, ''), '\D', '', 'g'), 9) = right(u.tel, 9);

-- b) si no coincidió el celular: por nombre y primer apellido del líder (sin tildes)
update igho g set direccion = u.direccion, horario = u.horario, mapas = u.mapas
from _ub u, personas p
where p.id = g.lider_persona_id and g.activo and g.mapas is null
  and translate(lower(split_part(p.nombres, ' ', 1)), 'áéíóúüñ', 'aeiouun') = translate(lower(split_part(u.nom, ' ', 1)), 'áéíóúüñ', 'aeiouun')
  and translate(lower(split_part(coalesce(p.apellidos, ''), ' ', 1)), 'áéíóúüñ', 'aeiouun') = translate(lower(u.ape), 'áéíóúüñ', 'aeiouun');

drop table if exists _ub;

-- El líder (o el Consejo) puede corregir dirección, horario y mapas desde Mi IGHO
create or replace function public.guardar_lugar_igho(p_igho uuid, p_direccion text, p_horario text, p_mapas text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (p_igho in (select public.mis_ighos()) or public.es_anciano_o_admin()) then raise exception 'Sin permiso'; end if;
  update igho set direccion = nullif(btrim(p_direccion), ''), horario = nullif(btrim(p_horario), ''),
         mapas = nullif(array(select btrim(x) from unnest(coalesce(p_mapas, '{}')) x where btrim(x) <> ''), '{}')
  where id = p_igho;
end $$;
grant execute on function public.guardar_lugar_igho(uuid, text, text, text[]) to authenticated;

-- El Stand recibe también dirección, horario y mapas (para el WhatsApp a la persona)
drop function if exists public.stand_ighos();
create function public.stand_ighos()
returns table (id uuid, nombre text, lider text, lider_tel text, ubicacion text, lider_con_app boolean,
               direccion text, horario text, mapas text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.equipo_stand() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  return query
    select g.id, g.nombre, btrim(p.nombres || ' ' || coalesce(split_part(p.apellidos, ' ', 1), '')), p.telefono, g.ubicacion,
           exists (select 1 from usuarios_roles ur where ur.rol = 'lider_igho' and ur.igho_id = g.id)
             or exists (select 1 from perfiles pf where pf.persona_id = g.lider_persona_id),
           g.direccion, g.horario, g.mapas
    from igho g left join personas p on p.id = g.lider_persona_id
    where g.activo order by g.nombre;
end $$;
grant execute on function public.stand_ighos() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Borrar a alguien de la base SOLO si fue un error o una prueba:
--    no está en un IGHO ni aparece en ninguna otra tabla (censo, familia,
--    cuenta, asistencia, Worship, clases, Kidz, Bienvenida, Stand…).
--    Si tiene algo de eso, se queda en la base (no se pierde nada).
-- ---------------------------------------------------------------------
create or replace function public.borrar_persona_si_suelta(p uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare r record; hay boolean;
begin
  if p is null then return false; end if;
  if exists (select 1 from personas where id = p and igho_id is not null) then return false; end if;
  -- Revisa TODAS las tablas que apuntan a personas (censo, familias, cuentas, asistencia, Kidz, Worship…)
  for r in
    select c.conrelid::regclass as tabla, a.attname as col
    from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and c.confrelid = 'public.personas'::regclass and array_length(c.conkey, 1) = 1
  loop
    execute format('select exists (select 1 from %s where %I = $1)', r.tabla, r.col) into hay using p;
    if hay then return false; end if;
  end loop;
  begin
    delete from personas where id = p;
  exception when foreign_key_violation then return false;
  end;
  return true;
end $$;
revoke all on function public.borrar_persona_si_suelta(uuid) from public, anon, authenticated;

-- Borrar una inscripción al IGHO (prueba o error). Quita también el aviso que recibió el líder.
create or replace function public.borrar_interes_igho(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r igho_interesados; v_borrada boolean := false;
begin
  select * into r from igho_interesados where id = p_id;
  if r.id is null then raise exception 'Ya no existe'; end if;
  if not (r.igho_id in (select public.mis_ighos()) or public.es_anciano_o_admin()
          or (public.equipo_stand() and r.creado_en >= now() - interval '1 day')) then
    raise exception 'Sin permiso';
  end if;
  delete from notificaciones_usuarios where notificacion_id in (
    select n.id from notificaciones n where n.tipo = 'igho' and n.destino = 'igho:' || r.igho_id
      and n.cuerpo like r.nombre || ' quiere conocer%' and n.creado_en between r.creado_en - interval '2 minutes' and r.creado_en + interval '2 minutes');
  delete from notificaciones n where n.tipo = 'igho' and n.destino = 'igho:' || r.igho_id
      and n.cuerpo like r.nombre || ' quiere conocer%' and n.creado_en between r.creado_en - interval '2 minutes' and r.creado_en + interval '2 minutes';
  delete from igho_interesados where id = p_id;
  v_borrada := public.borrar_persona_si_suelta(r.persona_id);
  return jsonb_build_object('persona_borrada', v_borrada);
end $$;
grant execute on function public.borrar_interes_igho(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Bienvenida: editar y borrar
-- ---------------------------------------------------------------------
-- La vista suma sexo y año de nacimiento (para el formulario de editar)
create or replace view nuevos_seguimiento as
select n.*, p.nombres, p.apellidos, p.telefono, i.nombre as igho_nombre,
       exists (select 1 from asistencia_igho a where a.persona_id = p.id) as asistio_igho,
       p.sexo::text as sexo, p.anio_nacimiento_aprox
from nuevos n
join personas p on p.id = n.persona_id
left join igho i on i.id = p.igho_id
where public.es_anciano_o_admin() or public.sirve_en('bienvenida') or public.es_conyuge_consejo();
grant select on nuevos_seguimiento to authenticated;

create or replace function public.editar_nuevo(
  p_persona uuid, p_nombres text, p_apellidos text, p_telefono text, p_sexo text, p_edad int,
  p_como_llego text, p_invitado_por text, p_interes_igho text, p_notas text, p_primera_visita date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.es_anciano_o_admin() or public.sirve_en('bienvenida')) then raise exception 'Sin permiso'; end if;
  if coalesce(btrim(p_nombres), '') = '' then raise exception 'Escribe el nombre'; end if;
  if not exists (select 1 from nuevos where persona_id = p_persona) then raise exception 'Esta persona no está en Bienvenida'; end if;
  update personas set nombres = btrim(p_nombres), apellidos = nullif(btrim(p_apellidos), ''),
         telefono = nullif(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), ''),
         sexo = nullif(p_sexo, '')::sexo_t,
         anio_nacimiento_aprox = case when p_edad is not null then extract(year from current_date)::int - p_edad else anio_nacimiento_aprox end
  where id = p_persona;
  update nuevos set como_llego = p_como_llego, invitado_por = nullif(btrim(p_invitado_por), ''),
         interes_igho = p_interes_igho, notas = nullif(btrim(p_notas), ''),
         primera_visita = coalesce(p_primera_visita, primera_visita)
  where persona_id = p_persona;
end $$;
grant execute on function public.editar_nuevo(uuid, text, text, text, text, int, text, text, text, text, date) to authenticated;

-- Borrar de Bienvenida. Si la persona solo existía por este registro (un error), se borra también de la base.
create or replace function public.borrar_nuevo(p_persona uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_borrada boolean;
begin
  if not (public.es_anciano_o_admin() or public.sirve_en('bienvenida')) then raise exception 'Sin permiso'; end if;
  delete from nuevos where persona_id = p_persona;
  v_borrada := public.borrar_persona_si_suelta(p_persona);
  return jsonb_build_object('persona_borrada', v_borrada);
end $$;
grant execute on function public.borrar_nuevo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Finanzas · Ingresos (solo Consejo, admin y el rol Finanzas)
--    tipo 'semana' (semana 1–5 del mes), 'ajuste' (ajustes del mes) o
--    'mes' (solo el total del mes, para enero–junio que no tienen semanas)
-- ---------------------------------------------------------------------
create table if not exists finanzas_ingresos (
  id                 bigint generated always as identity primary key,
  congregacion       text not null default 'rios',
  anio               int  not null,
  mes                int  not null check (mes between 1 and 12),
  tipo               text not null check (tipo in ('semana', 'ajuste', 'mes')),
  semana             int  not null default 0,
  diezmo             numeric(12,2),
  ofrenda            numeric(12,2),
  total              numeric(12,2) not null,
  nota               text,
  creado_por_nombre  text,
  creado_en          timestamptz not null default now(),
  unique (congregacion, anio, mes, tipo, semana)
);
alter table finanzas_ingresos enable row level security;
grant select, insert, update, delete on finanzas_ingresos to authenticated;
grant all on finanzas_ingresos to service_role;
drop policy if exists "finanzas ingresos" on finanzas_ingresos;
create policy "finanzas ingresos" on finanzas_ingresos for all to authenticated
  using (public.es_anciano_o_admin() or public.tiene_rol('finanzas'))
  with check (public.es_anciano_o_admin() or public.tiene_rol('finanzas'));

-- Ingresos de Ríos 2026 (hoja ESTADISTICAS GENERAL 2026 · «Ingresos desde Julio»)
insert into finanzas_ingresos (anio, mes, tipo, semana, diezmo, ofrenda, total, nota, creado_por_nombre) values
 (2026, 1, 'mes', 0, null, null, 10178.00, null, 'Hoja 2026'),
 (2026, 2, 'mes', 0, null, null,  4718.00, null, 'Hoja 2026'),
 (2026, 3, 'mes', 0, null, null,  7841.00, null, 'Hoja 2026'),
 (2026, 4, 'mes', 0, null, null,  3832.00, null, 'Hoja 2026'),
 (2026, 5, 'mes', 0, null, null,  5518.00, null, 'Hoja 2026'),
 (2026, 6, 'mes', 0, null, null,  6400.00, null, 'Hoja 2026'),
 (2026, 7, 'semana', 1, null, null,  720.09, null, 'Hoja 2026'),
 (2026, 7, 'semana', 2, null, null,  937.87, null, 'Hoja 2026'),
 (2026, 7, 'semana', 3, null, null, 3386.51, null, 'Hoja 2026'),
 (2026, 7, 'semana', 4, null, null,  547.42, null, 'Hoja 2026'),
 (2026, 7, 'ajuste', 0, null, null, 1267.11, null, 'Hoja 2026'),
 (2026, 8, 'semana', 1, null, null,  498.15, null, 'Hoja 2026'),
 (2026, 8, 'semana', 2, 330.00, 447.35, 777.35, '4–11 de agosto', 'Hoja 2026'),
 (2026, 8, 'semana', 3, null, null,  387.61, null, 'Hoja 2026'),
 (2026, 8, 'semana', 4, null, null, 1902.64, null, 'Hoja 2026'),
 (2026, 8, 'semana', 5, null, null, 1564.76, null, 'Hoja 2026'),
 (2026, 8, 'ajuste', 0, null, null,  120.49, null, 'Hoja 2026'),
 (2026, 9, 'semana', 1,   20.00, 425.99,  445.99, '1–7 de septiembre', 'Hoja 2026'),
 (2026, 9, 'semana', 2,  312.00, 374.54,  686.54, '8–14 de septiembre', 'Hoja 2026'),
 (2026, 9, 'semana', 3, 1371.18, 318.30, 1689.48, '15–21 de septiembre', 'Hoja 2026'),
 (2026, 9, 'semana', 4,  405.00, 294.87,  699.87, '22–28 de septiembre', 'Hoja 2026'),
 (2026, 9, 'ajuste', 0, null, null,  947.12, null, 'Hoja 2026'),
 (2026, 10, 'semana', 2, null, null, 1020.87, null, 'Hoja 2026'),
 (2026, 10, 'semana', 3, null, null, 1045.97, null, 'Hoja 2026'),
 (2026, 10, 'semana', 4, null, null,  734.63, null, 'Hoja 2026')
on conflict (congregacion, anio, mes, tipo, semana) do nothing;

-- ---------------------------------------------------------------------
-- Revisión: IGHO activos que quedaron SIN dirección (asígnala en Mi IGHO)
-- ---------------------------------------------------------------------
select g.nombre as igho_sin_direccion, btrim(coalesce(p.nombres, '') || ' ' || coalesce(p.apellidos, '')) as lider, p.telefono
from igho g left join personas p on p.id = g.lider_persona_id
where g.activo and g.mapas is null order by g.nombre;
