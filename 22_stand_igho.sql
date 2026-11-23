-- =====================================================================
-- 22 · Stand: inscribir a alguien que quiere ir a una Iglesia de hogar
-- Se guarda la persona (si es nueva, se crea en la base sin IGHO todavía)
-- y el líder de ese IGHO recibe un aviso: «Contacta a esta persona».
-- El líder lo ve en Mi IGHO → Miembros → «Quieren unirse».
-- Ejecutar después de 20_avisos.sql: Supabase → SQL Editor → Run
-- =====================================================================

create table if not exists igho_interesados (
  id                   bigint generated always as identity primary key,
  igho_id              uuid not null references igho(id) on delete cascade,
  persona_id           uuid references personas(id) on delete set null,
  nombre               text not null,
  telefono             text,
  notas                text,
  inscrito_por_nombre  text,
  creado_en            timestamptz not null default now(),
  contactado_en        timestamptz,
  contactado_por       text
);
create index if not exists igho_interesados_igho_idx on igho_interesados (igho_id, contactado_en);

alter table igho_interesados enable row level security;
grant select, update on igho_interesados to authenticated;
grant all on igho_interesados to service_role;
drop policy if exists "lider ve interesados" on igho_interesados;
drop policy if exists "lider marca contactado" on igho_interesados;
create policy "lider ve interesados" on igho_interesados for select to authenticated
  using (igho_id in (select public.mis_ighos()) or public.es_anciano_o_admin() or public.es_conyuge_consejo() or public.equipo_stand());
create policy "lider marca contactado" on igho_interesados for update to authenticated
  using (igho_id in (select public.mis_ighos()) or public.es_anciano_o_admin())
  with check (igho_id in (select public.mis_ighos()) or public.es_anciano_o_admin());

-- Los avisos ahora también pueden ser de tipo «igho»
alter table notificaciones drop constraint if exists notificaciones_tipo_check;
alter table notificaciones add constraint notificaciones_tipo_check check (tipo in ('aviso', 'servicio', 'igho'));

-- IGHO para elegir en el Stand (con su líder)
create or replace function public.stand_ighos()
returns table (id uuid, nombre text, lider text, lider_tel text, ubicacion text, lider_con_app boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.equipo_stand() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  return query
    select g.id, g.nombre, btrim(p.nombres || ' ' || coalesce(split_part(p.apellidos, ' ', 1), '')), p.telefono, g.ubicacion,
           exists (select 1 from usuarios_roles ur where ur.rol = 'lider_igho' and ur.igho_id = g.id)
             or exists (select 1 from perfiles pf where pf.persona_id = g.lider_persona_id)
    from igho g left join personas p on p.id = g.lider_persona_id
    where g.activo order by g.nombre;
end $$;
grant execute on function public.stand_ighos() to authenticated;

-- Inscribir: guarda al interesado y crea el aviso para el líder.
-- Devuelve el id del aviso (para mandarlo al teléfono) y a cuántos les llega.
create or replace function public.stand_igho_interes(p_igho uuid, p_persona uuid, p_nombres text, p_apellidos text,
                                                     p_telefono text, p_notas text, p_quien text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_p uuid := p_persona; v_nombre text; v_tel text; v_igho text; v_n bigint; n int;
begin
  if not public.equipo_stand() then raise exception 'Solo el equipo del Stand inscribe'; end if;
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
