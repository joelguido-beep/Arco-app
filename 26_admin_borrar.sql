-- =====================================================================
-- 26 · El administrador puede borrar datos equivocados o de prueba
-- Da permiso de BORRAR al rol admin en casi todas las tablas (conteos,
-- Kidz, IGHO, Formación, avisos, Worship, anuncios, finanzas…).
-- No toca: personas (se borran con admin_borrar_persona, que es segura),
-- cuentas y roles, cobertura del Consejo y ajustes privados.
-- Ejecutar después de 25: Supabase → SQL Editor → New query → pegar todo → Run
-- =====================================================================

do $$
declare t record;
begin
  for t in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
      and c.relname not in ('personas', 'perfiles', 'usuarios_roles', 'ajustes_privados', 'cobertura_consejo', 'conyuges_consejo')
  loop
    execute format('drop policy if exists "admin borra" on public.%I', t.relname);
    execute format('create policy "admin borra" on public.%I for delete to authenticated using (public.tiene_rol(''admin''))', t.relname);
    execute format('grant delete on public.%I to authenticated', t.relname);
  end loop;
end $$;

-- Borrar a una persona: si no aparece en ninguna otra parte, se borra de la base.
-- Si tiene historia (censo, asistencia, familia, cuenta…), se DESACTIVA: deja de
-- aparecer en las listas y sale de su IGHO, pero no se pierde su historia.
create or replace function public.admin_borrar_persona(p uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not public.tiene_rol('admin') then raise exception 'Solo el administrador'; end if;
  if exists (select 1 from perfiles where persona_id = p) then
    raise exception 'Esta persona tiene cuenta en la app. Quítale el acceso primero (Administración → Con acceso).';
  end if;
  if exists (select 1 from igho where lider_persona_id = p and activo) then
    raise exception 'Esta persona es líder de un IGHO. Cambia el líder primero (Mi IGHO → Editar IGHO).';
  end if;
  if public.borrar_persona_si_suelta(p) then return 'borrada'; end if;
  update personas set activo = false, igho_id = null where id = p;
  return 'desactivada';
end $$;
grant execute on function public.admin_borrar_persona(uuid) to authenticated;
