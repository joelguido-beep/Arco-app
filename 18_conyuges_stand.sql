-- =====================================================================
-- 18 · Cónyuges del Consejo, páginas solo del administrador e
--      inscripciones en el Stand desde los anuncios
-- Ejecutar una vez: Supabase → SQL Editor → New query → Run
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CÓNYUGES DEL CONSEJO
-- Ven todo lo de la app menos Finanzas, el Tablero y la Reunión del Consejo.
-- Solo leen. Si además tienen un rol (ej. Líder de Kidz), ese rol les deja
-- editar su página como a cualquier otro líder.
-- ---------------------------------------------------------------------
create table if not exists conyuges_consejo (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  creado_en  timestamptz not null default now()
);
alter table conyuges_consejo enable row level security;
grant select on conyuges_consejo to authenticated;
drop policy if exists "ver la marca" on conyuges_consejo;
create policy "ver la marca" on conyuges_consejo for select to authenticated
  using (user_id = auth.uid() or public.tiene_rol('admin'));

create or replace function public.es_conyuge_consejo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from conyuges_consejo where user_id = auth.uid());
$$;
grant execute on function public.es_conyuge_consejo() to authenticated;

-- El administrador marca o desmarca a alguien como cónyuge del Consejo
create or replace function public.marcar_conyuge_consejo(p_user uuid, p_si boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador puede cambiar esto'; end if;
  if p_si then insert into conyuges_consejo (user_id) values (p_user) on conflict do nothing;
  else delete from conyuges_consejo where user_id = p_user; end if;
end $$;
grant execute on function public.marcar_conyuge_consejo(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 2. MENSAJES POR WHATSAPP y FAMILIAS: solo el administrador
-- ---------------------------------------------------------------------
create or replace function public.edita_familias() returns boolean
language sql stable security definer set search_path = public as $$
  select public.tiene_rol('admin');
$$;

do $$
declare r record;
begin
  for r in select p.oid, pg_get_function_arguments(p.oid) as args
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'puede_difusion' and p.prorettype = 'boolean'::regtype
  loop
    execute format('create or replace function public.puede_difusion(%s) returns boolean language sql stable security definer set search_path = public as $f$ select public.tiene_rol(''admin'') $f$', r.args);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. STAND DE INFORMACIÓN: inscripciones que nacen de un anuncio
-- Al escribir los anuncios se marca «Inscripciones en el Stand». Eso crea
-- una actividad (ej. «Presentación de niños») donde el Stand inscribe.
-- Si el anuncio se copia al domingo siguiente, sigue siendo la misma lista.
-- ---------------------------------------------------------------------
create table if not exists stand_actividades (
  id                 bigint generated always as identity primary key,
  titulo             text not null check (length(btrim(titulo)) > 0),
  tipo               text not null default 'personas' check (tipo in ('personas', 'ninos')),
  detalle            text,
  abierta            boolean not null default true,
  creado_por_nombre  text,
  creado_en          timestamptz not null default now()
);
alter table anuncios_items add column if not exists stand_actividad_id bigint references stand_actividades(id) on delete set null;

create table if not exists stand_registros (
  id                   bigint generated always as identity primary key,
  actividad_id         bigint not null references stand_actividades(id) on delete cascade,
  persona_id           uuid references personas(id) on delete set null,
  nino_ref             text,          -- id del niño en Kidz, si se eligió de la lista
  nombre               text not null, -- la persona o el niño
  fecha_nacimiento     date,          -- niños
  responsable          text,          -- papá o mamá
  telefono             text,
  notas                text,
  inscrito_por_nombre  text,
  creado_en            timestamptz not null default now()
);
create index if not exists stand_registros_act_idx on stand_registros (actividad_id);

-- ¿Sirve en este ministerio? (líder o siervo)
create or replace function public.en_ministerio(cod text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from usuarios_roles ur join ministerios m on m.id = ur.ministerio_id
                 where ur.user_id = auth.uid() and m.codigo = cod);
$$;
create or replace function public.lidera_ministerio(cod text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from usuarios_roles ur join ministerios m on m.id = ur.ministerio_id
                 where ur.user_id = auth.uid() and ur.rol = 'lider_ministerio' and m.codigo = cod);
$$;
create or replace function public.edita_anuncios() returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_anciano_o_admin() or public.tiene_rol('secretaria') or public.lidera_ministerio('anuncios');
$$;
create or replace function public.equipo_stand() returns boolean
language sql stable security definer set search_path = public as $$
  select public.edita_anuncios() or public.en_ministerio('stand') or public.lidera_ministerio('formacion');
$$;
grant execute on function public.en_ministerio(text), public.lidera_ministerio(text), public.edita_anuncios(), public.equipo_stand() to authenticated;

alter table stand_actividades enable row level security;
alter table stand_registros   enable row level security;
grant select, insert, update, delete on stand_actividades, stand_registros to authenticated;
grant all on stand_actividades, stand_registros to service_role;

drop policy if exists "equipo ve actividades" on stand_actividades;
drop policy if exists "anuncios crea actividades" on stand_actividades;
drop policy if exists "anuncios cambia actividades" on stand_actividades;
drop policy if exists "anuncios borra actividades" on stand_actividades;
create policy "equipo ve actividades" on stand_actividades for select to authenticated using (true);
create policy "anuncios crea actividades" on stand_actividades for insert to authenticated with check (public.edita_anuncios());
create policy "anuncios cambia actividades" on stand_actividades for update to authenticated using (public.edita_anuncios() or public.equipo_stand()) with check (public.edita_anuncios() or public.equipo_stand());
create policy "anuncios borra actividades" on stand_actividades for delete to authenticated using (public.edita_anuncios());

drop policy if exists "stand ve inscritos" on stand_registros;
drop policy if exists "stand inscribe" on stand_registros;
drop policy if exists "stand corrige" on stand_registros;
drop policy if exists "stand quita" on stand_registros;
create policy "stand ve inscritos" on stand_registros for select to authenticated using (public.equipo_stand() or public.en_ministerio('kidz'));
create policy "stand inscribe" on stand_registros for insert to authenticated with check (public.equipo_stand());
create policy "stand corrige" on stand_registros for update to authenticated using (public.equipo_stand()) with check (public.equipo_stand());
create policy "stand quita" on stand_registros for delete to authenticated using (public.equipo_stand());

-- Buscar niños de Kidz para inscribirlos (el Stand no lee Kidz directamente)
create or replace function public.stand_buscar_ninos(q text)
returns table (id text, nombre text, fecha_nacimiento date, responsable text, telefono text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.equipo_stand() or public.es_conyuge_consejo()) then raise exception 'Sin permiso'; end if;
  if length(btrim(coalesce(q, ''))) < 2 then return; end if;
  return query
    select n.id::text, btrim(n.nombres || ' ' || coalesce(n.apellidos, '')), n.fecha_nacimiento, f.tutores, f.telefono
    from kidz_ninos n left join kidz_familias f on f.id = n.familia_id
    where n.activo and (n.nombres || ' ' || coalesce(n.apellidos, '') || ' ' || coalesce(n.apodo, '')) ilike '%' || btrim(q) || '%'
    order by n.nombres limit 12;
end $$;
grant execute on function public.stand_buscar_ninos(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. LECTURA PARA CÓNYUGES DEL CONSEJO
-- Una política de lectura en cada tabla, menos las del Consejo, los
-- mensajes por WhatsApp y las cuentas. Las tablas que se creen después
-- (por ejemplo Finanzas) no quedan incluidas.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  for t in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relrowsecurity
      and c.relname not in ('consejo_tareas', 'consejo_notas', 'consejo_decisiones', 'difusion_envios',
                            'usuarios_roles', 'perfiles', 'conyuges_consejo', 'sugerencias_descartadas', 'cobertura_consejo')
      and c.relname not like 'finanz%'
  loop
    execute format('grant select on %I to authenticated', t);
    execute format('drop policy if exists "conyuge del consejo ve" on %I', t);
    execute format('create policy "conyuge del consejo ve" on %I for select to authenticated using (public.es_conyuge_consejo())', t);
  end loop;
end $$;

-- PDFs de canciones, fotos de Kidz y diapositivas de la prédica
drop policy if exists "conyuge del consejo ve archivos" on storage.objects;
create policy "conyuge del consejo ve archivos" on storage.objects for select to authenticated
  using (bucket_id in ('canciones', 'kidz', 'predicas') and public.es_conyuge_consejo());
