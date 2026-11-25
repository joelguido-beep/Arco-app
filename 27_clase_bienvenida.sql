-- =====================================================================
-- 27 · Clase «Bienvenido a la familia»
-- Cada dos meses, dos domingos seguidos por la mañana.
--  · bv_clases: cada clase (domingo 1 y domingo 2, hora, lugar)
--  · bv_inscritos: quién se inscribió (desde Bienvenida o el Stand)
--  · bv_asistencia: quién vino cada día (1 o 2)
-- Quien vino los DOS días (en esta clase o completando en otra) queda
-- con nuevos.clase_bienvenida = true y fecha_clase = el último día.
-- Ejecutar después de 26_admin_borrar.sql: Supabase → SQL Editor → New query → Run
-- =====================================================================

create table if not exists bv_clases (
  id          bigint generated always as identity primary key,
  fecha1      date not null,
  fecha2      date not null,
  hora        text,
  lugar       text,
  notas       text,
  abierta     boolean not null default true,
  creado_por  text,
  creado_en   timestamptz not null default now(),
  check (fecha2 > fecha1)
);
create unique index if not exists bv_clases_fecha1_idx on bv_clases (fecha1);

create table if not exists bv_inscritos (
  id                   bigint generated always as identity primary key,
  clase_id             bigint not null references bv_clases(id) on delete cascade,
  persona_id           uuid not null references personas(id) on delete cascade,
  origen               text not null default 'bienvenida' check (origen in ('bienvenida', 'stand', 'clase')),
  notas                text,
  inscrito_por_nombre  text,
  creado_en            timestamptz not null default now(),
  unique (clase_id, persona_id)
);
create index if not exists bv_inscritos_persona_idx on bv_inscritos (persona_id);

create table if not exists bv_asistencia (
  clase_id     bigint not null references bv_clases(id) on delete cascade,
  persona_id   uuid not null references personas(id) on delete cascade,
  sesion       smallint not null check (sesion in (1, 2)),
  marcado_por  text,
  creado_en    timestamptz not null default now(),
  primary key (clase_id, persona_id, sesion)
);
create index if not exists bv_asistencia_persona_idx on bv_asistencia (persona_id);

-- Quién organiza la clase (fechas, lista, asistencia) y quién solo inscribe
create or replace function public.edita_clase_bv() returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_anciano_o_admin() or public.sirve_en('bienvenida');
$$;
create or replace function public.inscribe_clase_bv() returns boolean
language sql stable security definer set search_path = public as $$
  select public.edita_clase_bv() or public.equipo_stand();
$$;
grant execute on function public.edita_clase_bv(), public.inscribe_clase_bv() to authenticated;

alter table bv_clases     enable row level security;
alter table bv_inscritos  enable row level security;
alter table bv_asistencia enable row level security;
grant select on bv_clases, bv_inscritos, bv_asistencia to authenticated;
grant all on bv_clases, bv_inscritos, bv_asistencia to service_role;

drop policy if exists "bv clases ven" on bv_clases;
drop policy if exists "bv inscritos ven" on bv_inscritos;
drop policy if exists "bv asistencia ven" on bv_asistencia;
create policy "bv clases ven" on bv_clases for select to authenticated
  using (public.inscribe_clase_bv() or public.es_conyuge_consejo());
create policy "bv inscritos ven" on bv_inscritos for select to authenticated
  using (public.inscribe_clase_bv() or public.es_conyuge_consejo());
create policy "bv asistencia ven" on bv_asistencia for select to authenticated
  using (public.inscribe_clase_bv() or public.es_conyuge_consejo());

-- ---------------------------------------------------------------------
-- Crear / editar / borrar una clase
-- ---------------------------------------------------------------------
create or replace function public.bv_guardar_clase(p_id bigint, p_fecha1 date, p_fecha2 date, p_hora text,
                                                   p_lugar text, p_notas text, p_abierta boolean, p_quien text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := p_id;
begin
  if not public.edita_clase_bv() then raise exception 'Solo el equipo de Bienvenida o el Consejo'; end if;
  if p_fecha1 is null or p_fecha2 is null then raise exception 'Elige las dos fechas'; end if;
  if p_fecha2 <= p_fecha1 then raise exception 'El segundo domingo tiene que ser después del primero'; end if;
  if v_id is null then
    insert into bv_clases (fecha1, fecha2, hora, lugar, notas, abierta, creado_por)
    values (p_fecha1, p_fecha2, nullif(btrim(p_hora), ''), nullif(btrim(p_lugar), ''), nullif(btrim(p_notas), ''), coalesce(p_abierta, true), p_quien)
    returning id into v_id;
  else
    update bv_clases set fecha1 = p_fecha1, fecha2 = p_fecha2, hora = nullif(btrim(p_hora), ''), lugar = nullif(btrim(p_lugar), ''),
           notas = nullif(btrim(p_notas), ''), abierta = coalesce(p_abierta, abierta)
    where id = v_id;
    if not found then raise exception 'No se encontró la clase'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Ya hay una clase que empieza ese domingo';
end $$;
grant execute on function public.bv_guardar_clase(bigint, date, date, text, text, text, boolean, text) to authenticated;

create or replace function public.bv_borrar_clase(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.edita_clase_bv() then raise exception 'Sin permiso'; end if;
  if exists (select 1 from bv_asistencia where clase_id = p_id) and not public.es_anciano_o_admin() then
    raise exception 'Esta clase ya tiene asistencia. Solo el administrador o el Consejo pueden borrarla.';
  end if;
  delete from bv_clases where id = p_id;
end $$;
grant execute on function public.bv_borrar_clase(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- Inscribir (de la lista de Bienvenida, del Stand o el mismo día)
-- Si la persona no está en la base, se crea; y como es nueva, entra
-- también a la lista de Bienvenida para su seguimiento.
-- ---------------------------------------------------------------------
create or replace function public.bv_inscribir(p_clase bigint, p_persona uuid, p_nombres text, p_apellidos text,
                                               p_telefono text, p_notas text, p_origen text, p_quien text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_p uuid := p_persona; v_tel text := nullif(regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g'), '');
begin
  if not public.inscribe_clase_bv() then raise exception 'Sin permiso para inscribir'; end if;
  if not exists (select 1 from bv_clases where id = p_clase) then raise exception 'Elige la clase'; end if;
  if v_p is null then
    if coalesce(btrim(p_nombres), '') = '' then raise exception 'Escribe el nombre de la persona'; end if;
    insert into personas (nombres, apellidos, telefono)
    values (btrim(p_nombres), nullif(btrim(p_apellidos), ''), v_tel)
    returning id into v_p;
    begin
      insert into nuevos (persona_id, primera_visita, como_llego, interes_igho, notas)
      values (v_p, current_date, 'otro', 'tal_vez',
              case coalesce(p_origen, 'bienvenida') when 'stand' then 'Se inscribió a la clase de bienvenida en el Stand'
                                                    else 'Llegó a la clase de bienvenida' end);
    exception when others then null;  -- si la lista de Bienvenida pide otros datos, la inscripción sigue igual
    end;
  elsif v_tel is not null then
    update personas set telefono = coalesce(telefono, v_tel) where id = v_p;
  end if;
  insert into bv_inscritos (clase_id, persona_id, origen, notas, inscrito_por_nombre)
  values (p_clase, v_p, coalesce(p_origen, 'bienvenida'), nullif(btrim(p_notas), ''), p_quien)
  on conflict (clase_id, persona_id) do nothing;
  return v_p;
end $$;
grant execute on function public.bv_inscribir(bigint, uuid, text, text, text, text, text, text) to authenticated;

create or replace function public.bv_quitar(p_clase bigint, p_persona uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.edita_clase_bv() then raise exception 'Sin permiso'; end if;
  delete from bv_asistencia where clase_id = p_clase and persona_id = p_persona;
  delete from bv_inscritos where clase_id = p_clase and persona_id = p_persona;
  perform public.bv_actualizar_nuevo(p_persona);
end $$;

-- ---------------------------------------------------------------------
-- Asistencia: marcar / desmarcar un día. Actualiza Bienvenida.
-- ---------------------------------------------------------------------
create or replace function public.bv_actualizar_nuevo(p_persona uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_d1 date; v_d2 date;
begin
  select max(c.fecha1) into v_d1 from bv_asistencia a join bv_clases c on c.id = a.clase_id where a.persona_id = p_persona and a.sesion = 1;
  select max(c.fecha2) into v_d2 from bv_asistencia a join bv_clases c on c.id = a.clase_id where a.persona_id = p_persona and a.sesion = 2;
  if v_d1 is not null and v_d2 is not null then
    update nuevos set clase_bienvenida = true, fecha_clase = greatest(v_d1, v_d2) where persona_id = p_persona;
  else
    -- Solo se desmarca si la marca vino de la asistencia (una fecha de clase), no si alguien la puso a mano antes
    update nuevos set clase_bienvenida = false, fecha_clase = null
    where persona_id = p_persona and clase_bienvenida
      and fecha_clase in (select fecha1 from bv_clases union select fecha2 from bv_clases);
  end if;
end $$;
revoke execute on function public.bv_actualizar_nuevo(uuid) from public, anon, authenticated;
grant execute on function public.bv_quitar(bigint, uuid) to authenticated;

create or replace function public.bv_marcar(p_clase bigint, p_persona uuid, p_sesion int, p_vino boolean, p_quien text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.edita_clase_bv() then raise exception 'Solo el equipo de Bienvenida pasa lista'; end if;
  if p_sesion not in (1, 2) then raise exception 'Día 1 o día 2'; end if;
  if p_vino then
    -- quien llega sin inscribirse queda inscrito también
    insert into bv_inscritos (clase_id, persona_id, origen, inscrito_por_nombre)
    values (p_clase, p_persona, 'clase', p_quien) on conflict (clase_id, persona_id) do nothing;
    insert into bv_asistencia (clase_id, persona_id, sesion, marcado_por)
    values (p_clase, p_persona, p_sesion, p_quien) on conflict do nothing;
  else
    delete from bv_asistencia where clase_id = p_clase and persona_id = p_persona and sesion = p_sesion;
  end if;
  perform public.bv_actualizar_nuevo(p_persona);
end $$;
grant execute on function public.bv_marcar(bigint, uuid, int, boolean, text) to authenticated;

-- ---------------------------------------------------------------------
-- Lista de una clase con lo que hace falta para pasar lista
-- ---------------------------------------------------------------------
create or replace function public.bv_lista(p_clase bigint)
returns table (persona_id uuid, nombre text, telefono text, origen text, notas text, inscrito_por text, creado_en timestamptz,
               es_nuevo boolean, igho text, dia1 boolean, dia2 boolean, dia1_otra boolean, dia2_otra boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.inscribe_clase_bv() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  return query
    select i.persona_id, btrim(p.nombres || ' ' || coalesce(p.apellidos, '')), p.telefono, i.origen, i.notas, i.inscrito_por_nombre, i.creado_en,
           exists (select 1 from nuevos n where n.persona_id = p.id), g.nombre,
           exists (select 1 from bv_asistencia a where a.clase_id = p_clase and a.persona_id = p.id and a.sesion = 1),
           exists (select 1 from bv_asistencia a where a.clase_id = p_clase and a.persona_id = p.id and a.sesion = 2),
           exists (select 1 from bv_asistencia a where a.clase_id <> p_clase and a.persona_id = p.id and a.sesion = 1),
           exists (select 1 from bv_asistencia a where a.clase_id <> p_clase and a.persona_id = p.id and a.sesion = 2)
    from bv_inscritos i join personas p on p.id = i.persona_id left join igho g on g.id = p.igho_id
    where i.clase_id = p_clase
    order by p.nombres, p.apellidos;
end $$;
grant execute on function public.bv_lista(bigint) to authenticated;

-- Buscar personas para inscribir (mismo resultado que en Formación)
create or replace function public.bv_buscar(q text)
returns table (id uuid, nombre text, telefono text, igho text)
language plpgsql stable security definer set search_path = public as $$
declare t text := translate(lower(btrim(coalesce(q, ''))), 'áéíóúüñ', 'aeiouun'); d text := regexp_replace(coalesce(q, ''), '\D', '', 'g');
begin
  if not public.inscribe_clase_bv() then raise exception 'Sin permiso'; end if;
  if length(t) < 2 then return; end if;
  return query
    select p.id, btrim(p.nombres || ' ' || coalesce(p.apellidos, '')), p.telefono, g.nombre
    from personas p left join igho g on g.id = p.igho_id
    where coalesce(p.activo, true)
      and ((length(d) >= 4 and p.telefono like '%' || d || '%')
        or translate(lower(p.nombres || ' ' || coalesce(p.apellidos, '')), 'áéíóúüñ', 'aeiouun') like '%' || t || '%')
    order by p.nombres limit 15;
end $$;
grant execute on function public.bv_buscar(text) to authenticated;
