-- =====================================================================
-- 21 · Censo: al elegir «Es esta persona», el formulario se llena con lo
--      que ya está en la base (datos personales y familia). La persona
--      solo revisa y corrige.
-- Ejecutar una vez: Supabase → SQL Editor → New query → Run
-- =====================================================================

create or replace function public.censo_datos_persona(p uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'persona_id', x.id, 'nombres', x.nombres, 'apellidos', x.apellidos, 'telefono', x.telefono,
    'fecha_nacimiento', x.fecha_nacimiento, 'sexo', x.sexo, 'estado_civil', x.estado_civil,
    'bautizado', case when x.bautizado then 'si' when x.bautizado = false then 'no' end,
    'igho_id', x.igho_id))
  from personas x where x.id = p;
$$;
revoke all on function public.censo_datos_persona(uuid) from public, anon, authenticated;

create or replace function public.censo_persona(p_codigo text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  yo jsonb; mi_hogar uuid; mi_rol text; fam jsonb; dir text;
begin
  if public.censo_abierto(p_codigo) is null then raise exception 'El censo no está abierto'; end if;
  if not exists (select 1 from personas where id = p_id and activo) then return null; end if;

  select hogar_id, rol into mi_hogar, mi_rol from persona_hogar where persona_id = p_id;
  select direccion into dir from hogares where id = mi_hogar;

  yo := public.censo_datos_persona(p_id)
    || jsonb_build_object('cursos', coalesce((select jsonb_agg(curso_id::text) from persona_cursos where persona_id = p_id), '[]'))
    || coalesce((select jsonb_build_object('tiempo_en_arco', c.tiempo_en_arco) from censos c
                 where c.persona_id = p_id and c.tiempo_en_arco is not null order by c.anio desc limit 1), '{}');

  -- Familia: quienes viven en el mismo hogar y los lazos (cónyuge, padres, hijos)
  with gente as (
    select ph.persona_id as id, true as vive, ph.rol from persona_hogar ph
      where mi_hogar is not null and ph.hogar_id = mi_hogar and ph.persona_id <> p_id
    union
    select case when k.persona_a = p_id then k.persona_b else k.persona_a end, false, null
      from parentescos k where (k.persona_a = p_id or k.persona_b = p_id)
  ), una as (
    select id, bool_or(vive) as vive, max(rol) as rol from gente group by id
  ), con_rel as (
    select u.id, u.vive,
      case
        when exists (select 1 from parentescos k where k.tipo = 'conyuge' and least(k.persona_a, k.persona_b) = least(u.id, p_id) and greatest(k.persona_a, k.persona_b) = greatest(u.id, p_id)) then 'conyuge'
        when exists (select 1 from parentescos k where k.tipo = 'padre_madre' and k.persona_a = p_id and k.persona_b = u.id) then 'hijo'
        when exists (select 1 from parentescos k where k.tipo = 'padre_madre' and k.persona_a = u.id and k.persona_b = p_id) then 'padre_madre'
        when mi_rol in ('cabeza', 'conyuge') and u.rol in ('cabeza', 'conyuge') then 'conyuge'
        when mi_rol in ('cabeza', 'conyuge') and u.rol = 'hijo' then 'hijo'
        when mi_rol = 'hijo' and u.rol in ('cabeza', 'conyuge') then 'padre_madre'
        when mi_rol = 'hijo' and u.rol = 'hijo' then 'hermano'
        else 'otro'
      end as relacion
    from una u join personas pp on pp.id = u.id and pp.activo
  )
  select coalesce(jsonb_agg(public.censo_datos_persona(c.id) || jsonb_build_object('relacion', c.relacion, 'vive_conmigo', c.vive)
           order by array_position(array['conyuge', 'hijo', 'padre_madre', 'hermano', 'otro'], c.relacion)), '[]')
    into fam from con_rel c;

  return jsonb_build_object('yo', yo, 'direccion', dir, 'familia', fam);
end $$;
revoke all on function public.censo_persona(text, uuid) from public;
grant execute on function public.censo_persona(text, uuid) to anon, authenticated;
