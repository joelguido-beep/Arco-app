-- =====================================================================
-- 25 · Bienvenida también conecta a las personas nuevas con un IGHO
--      (igual que el Stand: aviso al líder + WhatsApp con el mapa)
-- Ejecutar después de 24: Supabase → SQL Editor → New query → pegar todo → Run
-- =====================================================================

create or replace function public.puede_conectar_igho() returns boolean
language sql stable security definer set search_path = public as $$
  select public.equipo_stand() or public.sirve_en('bienvenida') or public.es_anciano_o_admin();
$$;
grant execute on function public.puede_conectar_igho() to authenticated;

drop function if exists public.stand_ighos();
create function public.stand_ighos()
returns table (id uuid, nombre text, lider text, lider_tel text, ubicacion text, lider_con_app boolean,
               direccion text, horario text, mapas text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.puede_conectar_igho() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  return query
    select g.id, g.nombre, btrim(p.nombres || ' ' || coalesce(split_part(p.apellidos, ' ', 1), '')), p.telefono, g.ubicacion,
           exists (select 1 from usuarios_roles ur where ur.rol = 'lider_igho' and ur.igho_id = g.id)
             or exists (select 1 from perfiles pf where pf.persona_id = g.lider_persona_id),
           g.direccion, g.horario, g.mapas
    from igho g left join personas p on p.id = g.lider_persona_id
    where g.activo order by g.nombre;
end $$;
grant execute on function public.stand_ighos() to authenticated;

create or replace function public.stand_igho_interes(p_igho uuid, p_persona uuid, p_nombres text, p_apellidos text,
                                                     p_telefono text, p_notas text, p_quien text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_p uuid := p_persona; v_nombre text; v_tel text; v_igho text; v_n bigint; n int;
begin
  if not public.puede_conectar_igho() then raise exception 'Solo el equipo del Stand o de Bienvenida'; end if;
  select nombre into v_igho from igho where id = p_igho and activo;
  if v_igho is null then raise exception 'Elige un IGHO'; end if;
  if v_p is null then
    if coalesce(btrim(p_nombres), '') = '' then raise exception 'Escribe el nombre de la persona'; end if;
    insert into personas (nombres, apellidos, telefono)
    values (btrim(p_nombres), nullif(btrim(p_apellidos), ''), nullif(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), ''))
    returning id into v_p;
  elsif nullif(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), '') is not null then
    update personas set telefono = coalesce(telefono, regexp_replace(p_telefono, '\D', '', 'g')) where id = v_p;
  end if;
  select btrim(nombres || ' ' || coalesce(apellidos, '')), telefono into v_nombre, v_tel from personas where id = v_p;

  insert into igho_interesados (igho_id, persona_id, nombre, telefono, notas, inscrito_por_nombre)
  values (p_igho, v_p, v_nombre, v_tel, nullif(btrim(p_notas), ''), p_quien);

  insert into notificaciones (titulo, cuerpo, destino, ir_a, tipo, creado_por_nombre)
  values ('Alguien quiere ir a tu IGHO 🏠',
          v_nombre || ' quiere conocer ' || v_igho || '. Por favor contáctale' || coalesce(' al ' || v_tel, '') || '.'
            || coalesce(E'\nNota: ' || nullif(btrim(p_notas), ''), ''),
          'igho:' || p_igho, 'igho', 'igho', 'Stand · ' || coalesce(p_quien, ''))
  returning id into v_n;
  insert into notificaciones_usuarios (notificacion_id, user_id)
    select v_n, x.user_id from (
      select ur.user_id from usuarios_roles ur where ur.rol = 'lider_igho' and ur.igho_id = p_igho
      union select pf.user_id from igho g join perfiles pf on pf.persona_id = g.lider_persona_id where g.id = p_igho
    ) x on conflict do nothing;
  get diagnostics n = row_count;
  update notificaciones set personas = n where id = v_n;
  return jsonb_build_object('aviso', v_n, 'personas', n);
end $$;
grant execute on function public.stand_igho_interes(uuid, uuid, text, text, text, text, text) to authenticated;

create or replace function public.borrar_interes_igho(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r igho_interesados; v_borrada boolean := false;
begin
  select * into r from igho_interesados where id = p_id;
  if r.id is null then raise exception 'Ya no existe'; end if;
  if not (r.igho_id in (select public.mis_ighos()) or public.es_anciano_o_admin()
          or (public.puede_conectar_igho() and r.creado_en >= now() - interval '1 day')) then
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
