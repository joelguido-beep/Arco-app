-- =====================================================================
-- 19 · Censo por enlace
-- Cualquier persona con el enlace se busca a sí misma (o se agrega como
-- nueva), completa sus datos y agrega a su familia. Las respuestas NO
-- cambian la base directamente: quedan en «censo_respuestas» hasta que
-- el administrador las revisa y las aplica en Administración → Censo.
-- Ejecutar una vez: Supabase → SQL Editor → New query → Run
-- =====================================================================

create table if not exists censo_campanas (
  id         bigint generated always as identity primary key,
  anio       smallint not null,
  codigo     text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 10),
  abierta    boolean not null default true,
  creado_en  timestamptz not null default now()
);

create table if not exists censo_respuestas (
  id                   bigint generated always as identity primary key,
  campana_id           bigint not null references censo_campanas(id) on delete cascade,
  datos                jsonb not null,
  estado               text not null default 'pendiente' check (estado in ('pendiente', 'aplicada', 'descartada')),
  creado_en            timestamptz not null default now(),
  revisado_en          timestamptz,
  revisado_por_nombre  text
);
create index if not exists censo_respuestas_estado_idx on censo_respuestas (estado, creado_en);

alter table censo_campanas   enable row level security;
alter table censo_respuestas enable row level security;
grant select on censo_campanas to authenticated;
grant select on censo_respuestas to authenticated;
grant all on censo_campanas, censo_respuestas to service_role;

drop policy if exists "equipo ve el censo" on censo_campanas;
create policy "equipo ve el censo" on censo_campanas for select to authenticated
  using (public.tiene_algun_rol() or public.es_conyuge_consejo());
drop policy if exists "admin ve respuestas" on censo_respuestas;
create policy "admin ve respuestas" on censo_respuestas for select to authenticated using (public.tiene_rol('admin'));

-- El primer censo por enlace
insert into censo_campanas (anio) select 2027 where not exists (select 1 from censo_campanas);

-- ---------- Para el formulario público (sin iniciar sesión) ----------
create or replace function public.censo_abierto(p_codigo text) returns bigint
language sql stable security definer set search_path = public as $$
  select id from censo_campanas where codigo = p_codigo and abierta limit 1;
$$;

create or replace function public.censo_info(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select * into c from censo_campanas where codigo = p_codigo and abierta;
  if not found then return null; end if;
  return jsonb_build_object(
    'anio', c.anio,
    'ighos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by nombre) from igho where activo), '[]'),
    'cursos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by orden) from cursos), '[]'));
end $$;

-- Busca por nombre y apellido. Solo devuelve el nombre, el IGHO y los
-- últimos dígitos del teléfono, para que la persona se reconozca.
create or replace function public.censo_buscar(p_codigo text, p_nombre text, p_apellido text)
returns table (id uuid, nombre text, igho text, tel_fin text)
language plpgsql stable security definer set search_path = public as $$
declare
  n text := lower(translate(btrim(coalesce(p_nombre, '')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
  a text := lower(translate(btrim(coalesce(p_apellido, '')), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
begin
  if public.censo_abierto(p_codigo) is null then raise exception 'El censo no está abierto'; end if;
  if length(n) < 2 or length(a) < 2 then return; end if;
  return query
    select p.id, btrim(p.nombres || ' ' || coalesce(p.apellidos, '')), g.nombre,
           case when length(regexp_replace(coalesce(p.telefono, ''), '\D', '', 'g')) >= 4
                then right(regexp_replace(p.telefono, '\D', '', 'g'), 3) end
    from personas p left join igho g on g.id = p.igho_id
    where p.activo
      and lower(translate(p.nombres, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) like '%' || n || '%'
      and lower(translate(coalesce(p.apellidos, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) like '%' || a || '%'
    order by p.nombres, p.apellidos limit 8;
end $$;

-- Guarda la respuesta para revisión
create or replace function public.censo_enviar(p_codigo text, p_datos jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_camp bigint := public.censo_abierto(p_codigo); v_id bigint;
begin
  if v_camp is null then raise exception 'El censo no está abierto'; end if;
  if p_datos is null or jsonb_typeof(p_datos -> 'yo') <> 'object' or coalesce(btrim(p_datos -> 'yo' ->> 'nombres'), '') = '' then
    raise exception 'Faltan tus nombres';
  end if;
  if length(p_datos::text) > 30000 or jsonb_array_length(coalesce(p_datos -> 'familia', '[]')) > 15 then
    raise exception 'La respuesta es demasiado grande';
  end if;
  if (select count(*) from censo_respuestas where creado_en > now() - interval '10 minutes') > 120 then
    raise exception 'Hay muchas respuestas en este momento. Intenta de nuevo en unos minutos.';
  end if;
  insert into censo_respuestas (campana_id, datos) values (v_camp, p_datos) returning id into v_id;
  return v_id;
end $$;

revoke all on function public.censo_abierto(text), public.censo_info(text), public.censo_buscar(text, text, text), public.censo_enviar(text, jsonb) from public;
grant execute on function public.censo_info(text), public.censo_buscar(text, text, text), public.censo_enviar(text, jsonb) to anon, authenticated;

-- ---------- Para Mi IGHO: quiénes ya respondieron ----------
create or replace function public.censo_respondieron(p_igho uuid) returns setof uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.es_anciano_o_admin() or public.es_conyuge_consejo() or p_igho in (select public.mis_ighos())) then
    raise exception 'Sin permiso';
  end if;
  return query
    select distinct x.pid from (
      select (r.datos -> 'yo' ->> 'persona_id') as pid_t, r.campana_id from censo_respuestas r where r.estado <> 'descartada'
      union all
      select (m ->> 'persona_id'), r.campana_id from censo_respuestas r, jsonb_array_elements(coalesce(r.datos -> 'familia', '[]')) m where r.estado <> 'descartada'
    ) s
    cross join lateral (select case when s.pid_t ~ '^[0-9a-f-]{36}$' then s.pid_t::uuid end as pid) x
    join personas p on p.id = x.pid
    where p.igho_id = p_igho
      and s.campana_id = (select max(id) from censo_campanas where abierta);
end $$;
grant execute on function public.censo_respondieron(uuid) to authenticated;

-- ---------- Administración: aplicar o descartar una respuesta ----------
-- Guarda una persona del censo: si trae persona_id actualiza lo que se
-- llenó; si no, la crea. Devuelve el id.
create or replace function public.censo_guardar_persona(m jsonb, p_igho uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v uuid := case when coalesce(m ->> 'persona_id', '') ~ '^[0-9a-f-]{36}$' then (m ->> 'persona_id')::uuid end;
  tel text := nullif(regexp_replace(coalesce(m ->> 'telefono', ''), '\D', '', 'g'), '');
  fn date := nullif(m ->> 'fecha_nacimiento', '')::date;
  bau boolean := case m ->> 'bautizado' when 'si' then true when 'no' then false end;
  ig uuid := case when coalesce(m ->> 'igho_id', '') ~ '^[0-9a-f-]{36}$' then (m ->> 'igho_id')::uuid else p_igho end;
begin
  if tel is not null and left(tel, 3) = '593' and length(tel) = 12 then tel := '0' || substr(tel, 4); end if;
  if v is not null and exists (select 1 from personas where id = v) then
    update personas set
      nombres = coalesce(nullif(btrim(m ->> 'nombres'), ''), nombres),
      apellidos = coalesce(nullif(btrim(m ->> 'apellidos'), ''), apellidos),
      telefono = coalesce(tel, telefono),
      fecha_nacimiento = coalesce(fn, fecha_nacimiento),
      anio_nacimiento_aprox = coalesce(extract(year from fn)::smallint, anio_nacimiento_aprox),
      sexo = coalesce(nullif(m ->> 'sexo', '')::sexo_t, sexo),
      estado_civil = coalesce(nullif(m ->> 'estado_civil', '')::estado_civil_t, estado_civil),
      bautizado = coalesce(bau, bautizado),
      igho_id = case when m ->> 'igho_id' = 'ninguno' then null else coalesce(ig, igho_id) end,
      actualizado_en = now()
    where id = v;
  else
    insert into personas (nombres, apellidos, telefono, fecha_nacimiento, anio_nacimiento_aprox, sexo, estado_civil, bautizado, igho_id)
    values (btrim(m ->> 'nombres'), nullif(btrim(m ->> 'apellidos'), ''), tel, fn, extract(year from fn)::smallint,
            nullif(m ->> 'sexo', '')::sexo_t, nullif(m ->> 'estado_civil', '')::estado_civil_t, bau,
            case when m ->> 'igho_id' = 'ninguno' then null else ig end)
    returning id into v;
  end if;
  -- Clases de Formación Cristiana que ya tomó
  insert into persona_cursos (persona_id, curso_id)
    select v, c::smallint from jsonb_array_elements_text(coalesce(m -> 'cursos', '[]')) c
    where c ~ '^\d+$' and exists (select 1 from cursos where id = c::smallint)
  on conflict do nothing;
  return v;
end $$;
revoke all on function public.censo_guardar_persona(jsonb, uuid) from public, anon, authenticated;

-- p_datos: la respuesta ya revisada (el administrador puede haber unido a
-- una persona "nueva" con alguien que ya estaba en la base).
create or replace function public.censo_aplicar(p_id bigint, p_datos jsonb, p_quien text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r record; yo jsonb := p_datos -> 'yo'; m jsonb;
  v_yo uuid; v_m uuid; v_hogar uuid; v_igho uuid; v_anio smallint;
  conyuges uuid[] := '{}'; hijos uuid[] := '{}'; c uuid; h uuid; nuevos int := 0; antes int; fam_out jsonb := '[]';
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador aplica el censo'; end if;
  select cr.*, cc.anio into r from censo_respuestas cr join censo_campanas cc on cc.id = cr.campana_id where cr.id = p_id for update of cr;
  if not found then raise exception 'No existe esa respuesta'; end if;
  if r.estado = 'aplicada' then raise exception 'Esta respuesta ya se aplicó'; end if;
  v_anio := r.anio;

  select count(*) into antes from personas;
  v_yo := public.censo_guardar_persona(yo, null);
  select igho_id into v_igho from personas where id = v_yo;

  -- Censo del año
  insert into censos (anio, persona_id, igho_id, respondido_en, edad, tiempo_en_arco, bautizado, estado_civil)
  select v_anio, p.id, p.igho_id, now(),
         case when p.fecha_nacimiento is not null then extract(year from age(p.fecha_nacimiento))::smallint end,
         nullif(yo ->> 'tiempo_en_arco', '')::tiempo_arco_t, p.bautizado, p.estado_civil
  from personas p where p.id = v_yo
  on conflict (anio, persona_id) do update set igho_id = excluded.igho_id, respondido_en = excluded.respondido_en, edad = excluded.edad,
    tiempo_en_arco = coalesce(excluded.tiempo_en_arco, censos.tiempo_en_arco), bautizado = excluded.bautizado, estado_civil = excluded.estado_civil;

  -- Hogar: el de la persona, o uno nuevo si alguien vive con ella
  select hogar_id into v_hogar from persona_hogar where persona_id = v_yo;
  if v_hogar is null and exists (select 1 from jsonb_array_elements(coalesce(p_datos -> 'familia', '[]')) x where (x ->> 'vive_conmigo')::boolean) then
    insert into hogares (nombre, direccion)
    values ('Hogar ' || coalesce(nullif(split_part(btrim(yo ->> 'apellidos'), ' ', 1), ''), btrim(yo ->> 'nombres')), nullif(btrim(p_datos ->> 'direccion'), ''))
    returning id into v_hogar;
    insert into persona_hogar (persona_id, hogar_id, rol) values (v_yo, v_hogar, 'cabeza');
  elsif v_hogar is not null and nullif(btrim(p_datos ->> 'direccion'), '') is not null then
    update hogares set direccion = btrim(p_datos ->> 'direccion'), actualizado_en = now() where id = v_hogar;
  end if;

  for m in select * from jsonb_array_elements(coalesce(p_datos -> 'familia', '[]')) loop
    if coalesce(btrim(m ->> 'nombres'), '') = '' then continue; end if;
    -- Quien vive con la persona y no dijo su IGHO va al mismo IGHO
    v_m := public.censo_guardar_persona(m, case when (m ->> 'vive_conmigo')::boolean then v_igho end);
    fam_out := fam_out || jsonb_build_array(m || jsonb_build_object('persona_id', v_m));
    if v_m = v_yo then continue; end if;
    if m ->> 'relacion' = 'conyuge' then
      insert into parentescos (persona_a, persona_b, tipo) values (least(v_yo, v_m), greatest(v_yo, v_m), 'conyuge') on conflict do nothing;
      conyuges := conyuges || v_m;
    elsif m ->> 'relacion' = 'hijo' then
      if not exists (select 1 from parentescos where persona_a = v_m and persona_b = v_yo and tipo = 'padre_madre') then
        insert into parentescos (persona_a, persona_b, tipo) values (v_yo, v_m, 'padre_madre') on conflict do nothing;
      end if;
      hijos := hijos || v_m;
    elsif m ->> 'relacion' = 'padre_madre' then
      if not exists (select 1 from parentescos where persona_a = v_yo and persona_b = v_m and tipo = 'padre_madre') then
        insert into parentescos (persona_a, persona_b, tipo) values (v_m, v_yo, 'padre_madre') on conflict do nothing;
      end if;
    end if;
    if v_hogar is not null and (m ->> 'vive_conmigo')::boolean then
      insert into persona_hogar (persona_id, hogar_id, rol)
      values (v_m, v_hogar, case m ->> 'relacion' when 'conyuge' then 'conyuge' when 'hijo' then 'hijo' else 'otro' end)
      on conflict (persona_id) do nothing;
    end if;
  end loop;

  -- El cónyuge también es padre o madre de los hijos
  foreach c in array conyuges loop
    foreach h in array hijos loop
      if not exists (select 1 from parentescos where persona_a = h and persona_b = c and tipo = 'padre_madre') then
        insert into parentescos (persona_a, persona_b, tipo) values (c, h, 'padre_madre') on conflict do nothing;
      end if;
    end loop;
  end loop;

  select count(*) - antes into nuevos from personas;
  update censo_respuestas set estado = 'aplicada',
    datos = p_datos || jsonb_build_object('yo', yo || jsonb_build_object('persona_id', v_yo), 'familia', fam_out), revisado_en = now(), revisado_por_nombre = p_quien where id = p_id;
  return jsonb_build_object('persona_id', v_yo, 'hogar_id', v_hogar, 'nuevas', nuevos);
end $$;

create or replace function public.censo_descartar(p_id bigint, p_quien text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador'; end if;
  update censo_respuestas set estado = 'descartada', revisado_en = now(), revisado_por_nombre = p_quien where id = p_id and estado = 'pendiente';
end $$;

-- Abrir o cerrar el censo
create or replace function public.censo_abrir_cerrar(p_abierta boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador'; end if;
  update censo_campanas set abierta = p_abierta where id = (select max(id) from censo_campanas);
end $$;

grant execute on function public.censo_aplicar(bigint, jsonb, text), public.censo_descartar(bigint, text), public.censo_abrir_cerrar(boolean) to authenticated;
