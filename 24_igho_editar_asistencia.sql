-- =====================================================================
-- 24 · Editar y crear IGHO desde la app · Jamie Díaz líder (antes Andrés Torres) ·
--      Corrige la dirección de los IGHO (David Luna / Josué Luna) ·
--      Asistencia de los domingos 2026 de Ríos (de la hoja)
-- Ejecutar después de 23: Supabase → SQL Editor → New query → pegar todo → Run
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Editar un IGHO (nombre, líder, dirección, horario, mapas): Consejo y admin
--    Crear un IGHO nuevo: admin
-- ---------------------------------------------------------------------
create or replace function public.editar_igho(p_igho uuid, p_nombre text, p_lider uuid,
                                              p_direccion text, p_horario text, p_mapas text[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_antes uuid; v_cambio boolean;
begin
  if not public.es_anciano_o_admin() then raise exception 'Solo el Consejo o el administrador'; end if;
  if coalesce(btrim(p_nombre), '') = '' then raise exception 'Escribe el nombre del IGHO'; end if;
  select lider_persona_id into v_antes from igho where id = p_igho;
  v_cambio := v_antes is distinct from p_lider;
  update igho set nombre = btrim(p_nombre), lider_persona_id = p_lider,
         direccion = nullif(btrim(p_direccion), ''), horario = nullif(btrim(p_horario), ''),
         mapas = nullif(array(select btrim(x) from unnest(coalesce(p_mapas, '{}')) x where btrim(x) <> ''), '{}')
  where id = p_igho;
  if v_cambio then
    -- el líder anterior ya no lidera este IGHO en la app
    delete from usuarios_roles ur using perfiles pf
      where ur.rol = 'lider_igho' and ur.igho_id = p_igho and pf.user_id = ur.user_id and pf.persona_id = v_antes;
    -- el nuevo líder queda como miembro del IGHO si no estaba en ninguno
    update personas set igho_id = p_igho where id = p_lider and igho_id is null;
  end if;
  return jsonb_build_object('lider_cambio', v_cambio,
    'tiene_cuenta', exists (select 1 from perfiles where persona_id = p_lider),
    'es_lider_app', exists (select 1 from usuarios_roles ur join perfiles pf on pf.user_id = ur.user_id
                            where ur.rol = 'lider_igho' and ur.igho_id = p_igho and pf.persona_id = p_lider));
end $$;
grant execute on function public.editar_igho(uuid, text, uuid, text, text, text[]) to authenticated;

create or replace function public.crear_igho(p_nombre text, p_lider uuid, p_direccion text, p_horario text, p_mapas text[])
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador crea un IGHO'; end if;
  if coalesce(btrim(p_nombre), '') = '' then raise exception 'Escribe el nombre del IGHO'; end if;
  insert into igho (nombre, lider_persona_id, direccion, horario, mapas)
  values (btrim(p_nombre), p_lider, nullif(btrim(p_direccion), ''), nullif(btrim(p_horario), ''),
          nullif(array(select btrim(x) from unnest(coalesce(p_mapas, '{}')) x where btrim(x) <> ''), '{}'))
  returning id into v;
  if p_lider is not null then update personas set igho_id = v where id = p_lider and igho_id is null; end if;
  return v;
end $$;
grant execute on function public.crear_igho(text, uuid, text, text, text[]) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Corrige las direcciones: ahora gana el NOMBRE del líder y solo después
--    el celular (David Luna y Josué Luna comparten celular en la base).
--    Corre esto antes de editar direcciones en la app (las vuelve a poner).
-- ---------------------------------------------------------------------
with u (tel, nom, ape, direccion, horario, mapas) as (values
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
   array['https://maps.app.goo.gl/pstMqGVENS2JH7an7'])
),
m as (
  select distinct on (g.id) g.id, u.direccion, u.horario, u.mapas
  from igho g
  join personas p on p.id = g.lider_persona_id
  join u on right(regexp_replace(coalesce(p.telefono, ''), '\D', '', 'g'), 9) = right(u.tel, 9)
         or (translate(lower(split_part(p.nombres, ' ', 1)), 'áéíóúüñ', 'aeiouun') = translate(lower(split_part(u.nom, ' ', 1)), 'áéíóúüñ', 'aeiouun')
             and translate(lower(split_part(coalesce(p.apellidos, ''), ' ', 1)), 'áéíóúüñ', 'aeiouun') = translate(lower(u.ape), 'áéíóúüñ', 'aeiouun'))
  where g.activo
  order by g.id,
    (translate(lower(split_part(p.nombres, ' ', 1)), 'áéíóúüñ', 'aeiouun') = translate(lower(split_part(u.nom, ' ', 1)), 'áéíóúüñ', 'aeiouun')
     and translate(lower(split_part(coalesce(p.apellidos, ''), ' ', 1)), 'áéíóúüñ', 'aeiouun') = translate(lower(u.ape), 'áéíóúüñ', 'aeiouun')) desc
)
update igho g set direccion = m.direccion, horario = m.horario, mapas = m.mapas
from m where m.id = g.id;

-- ---------------------------------------------------------------------
-- 3. Jamie Díaz es el líder del IGHO que lideraba Andrés Torres
-- ---------------------------------------------------------------------
do $$
declare v_igho uuid; v_jamie uuid; v_andres uuid;
begin
  select g.id, g.lider_persona_id into v_igho, v_andres
  from igho g left join personas p on p.id = g.lider_persona_id
  where g.activo and (
        (translate(lower(split_part(p.nombres, ' ', 1)), 'áéíóú', 'aeiou') = 'andres' and lower(split_part(coalesce(p.apellidos, ''), ' ', 1)) = 'torres')
     or translate(lower(g.nombre), 'áéíóú', 'aeiou') like '%andres%torres%')
  limit 1;
  if v_igho is null then raise notice 'No se encontró el IGHO de Andrés Torres: cámbialo en la app (Mi IGHO → Editar IGHO).'; return; end if;

  select id into v_jamie from personas where right(regexp_replace(coalesce(telefono, ''), '\D', '', 'g'), 9) = '963098533' limit 1;
  if v_jamie is null then
    select id into v_jamie from personas
    where translate(lower(split_part(nombres, ' ', 1)), 'áéíóú', 'aeiou') in ('jamie', 'jaime')
      and translate(lower(split_part(coalesce(apellidos, ''), ' ', 1)), 'áéíóú', 'aeiou') = 'diaz' limit 1;
  end if;
  if v_jamie is null then
    insert into personas (nombres, apellidos, telefono, igho_id) values ('Jamie', 'Díaz', '0963098533', v_igho) returning id into v_jamie;
  else
    update personas set telefono = coalesce(nullif(telefono, ''), '0963098533'), igho_id = coalesce(igho_id, v_igho) where id = v_jamie;
  end if;

  update igho set lider_persona_id = v_jamie,
         nombre = case when translate(lower(nombre), 'áéíóú', 'aeiou') like '%andres%torres%' then 'Jamie Díaz' else nombre end,
         direccion = 'Octavio Paz y J. Donoso', horario = 'Martes · 8:00 pm',
         mapas = array['https://maps.app.goo.gl/xQG4uQtcEwMDnjoD9']
  where id = v_igho;
  delete from usuarios_roles ur using perfiles pf
    where ur.rol = 'lider_igho' and ur.igho_id = v_igho and pf.user_id = ur.user_id and pf.persona_id = v_andres;
end $$;

-- ---------------------------------------------------------------------
-- 4. Asistencia de los domingos 2026 · Arco Ríos (hoja «asistencia», solo Ríos)
--    Adultos → adultos; Niños → niños en el auditorio (la hoja no separa Kidz);
--    Nuevos solo de enero a abril. No toca los domingos que ya se contaron en la app.
-- ---------------------------------------------------------------------
insert into conteo_anfitriones (fecha, adultos, ninos_auditorio, nuevos, registrado_nombre, registrado_por, actualizado_en)
select v.fecha::date, v.adultos, v.ninos, v.nuevos, 'Hoja de asistencia 2026',
       (select user_id from usuarios_roles where rol = 'admin' order by id limit 1), now()
from (values
  ('2026-01-04', 375, 47, 3),
  ('2026-01-11', 356, 77, 4),
  ('2026-01-18', 331, 72, 6),
  ('2026-01-25', 415, 55, 2),
  ('2026-02-01', 340, 80, 8),
  ('2026-02-08', 384, 66, 5),
  ('2026-02-15', 274, 26, 0),
  ('2026-02-22', 370, 74, 3),
  ('2026-03-01', 332, 73, 0),
  ('2026-03-08', 379, 74, 5),
  ('2026-03-15', 363, 76, 4),
  ('2026-03-22', 408, 69, 6),
  ('2026-03-29', 367, 73, 1),
  ('2026-04-05', 468, 55, 6),
  ('2026-04-19', 380, 65, 2),
  ('2026-04-26', 312, 62, 4),
  ('2026-05-03', 298, 59, 0),
  ('2026-05-10', 303, 67, 0),
  ('2026-05-17', 336, 89, 0),
  ('2026-05-24', 281, 88, 0),
  ('2026-05-31', 316, 75, 0),
  ('2026-06-07', 366, 78, 0),
  ('2026-06-14', 312, 74, 0),
  ('2026-06-21', 285, 88, 0),
  ('2026-06-28', 368, 45, 0),
  ('2026-07-05', 285, 53, 0),
  ('2026-07-12', 327, 72, 0),
  ('2026-07-19', 324, 53, 0),
  ('2026-07-26', 356, 56, 0),
  ('2026-08-02', 310, 71, 0),
  ('2026-08-09', 251, 48, 0),
  ('2026-08-16', 332, 55, 0),
  ('2026-08-23', 335, 59, 0),
  ('2026-08-30', 315, 57, 0),
  ('2026-09-06', 360, 65, 0),
  ('2026-09-13', 325, 71, 0),
  ('2026-09-20', 342, 60, 0),
  ('2026-09-27', 332, 86, 0),
  ('2026-10-04', 334, 76, 0),
  ('2026-10-11', 354, 55, 0),
  ('2026-10-18', 331, 66, 0),
  ('2026-10-25', 372, 79, 0),
  ('2026-11-08', 350, 60, 0),
  ('2026-11-15', 297, 71, 0),
  ('2026-11-22', 337, 68, 0)
) as v(fecha, adultos, ninos, nuevos)
where not exists (select 1 from conteo_kidz k where k.fecha = v.fecha::date)
on conflict (fecha) do nothing;

-- Revisión: IGHO activos sin dirección
select g.nombre as igho_sin_direccion, btrim(coalesce(p.nombres, '') || ' ' || coalesce(p.apellidos, '')) as lider, p.telefono
from igho g left join personas p on p.id = g.lider_persona_id
where g.activo and g.mapas is null order by g.nombre;
