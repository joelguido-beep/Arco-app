# App Iglesia Arco Ríos: project summary (to start a new chat)

Attach this file when you start a new chat. The code lives in GitHub: **`joelguido-beep/Arco-app`** (branch `main`, served by GitHub Pages at https://joelguido-beep.github.io/Arco-app/). The Claude GitHub App is installed, so Claude can clone the repo and push changes directly (no need to attach `index.html`). **Joel's standing instruction: push every finished update straight to `main` on GitHub automatically, without asking first** (index.html, new SQL files and this summary). Joel still runs the SQL in Supabase himself. Current version: **25-nov v18** (shown under the title of the Avisos page; constant `VERSION_APP` in index.html; update both on each release).

## What it is
A web app in Spanish for Arco Ríos (Cuenca). It's a single `index.html` file hosted on **GitHub Pages**, and the data lives in **Supabase** (project `lmitwnfvelwbbkjkvmtb`).
- Supabase URL: `https://lmitwnfvelwbbkjkvmtb.supabase.co`
- Publishable key (safe to keep in the app): `sb_publishable_hCMTSR9Rnacl85NXiQpn5Q_L9JlmJ3m`
- Never put the service_role / secret key in the app.
- Edge Functions: shown as **notificar** but its URL slug is **`swift-action`** (FUNCION_AVISOS in index.html and the cron URL use swift-action) (code: `notificar.ts`, "Verify JWT" off): sends push notifications (Avisos and the Saturday reminder). VAPID keys create themselves the first time and live in `ajustes_privados` with the cron secret.
- Edge Function: named **`hyper-api`** in Supabase (code: `admin-usuarios.ts`), with "Verify JWT with legacy secret" turned **off**. Admin actions check the admin role in code; `registro_padre` is public (parents create their own account); `crear_lider_igho` is allowed for admin or the Consejo member who covers that IGHO, and only gives the `lider_igho` role to that IGHO's registered leader.

## Design (v14: light theme, Arco Ríos palette)
- Palette only: Luster White #F4F1EC (background), Aster Flower Blue #9BACD8, Habañero #F98513 (accent: things that need attention), Jodhpur Tan #DAD1C8, **Deep Space Royal #223382 (main color: buttons, selections)**, Deadly Depths #111144 (text). CSS variables --luster, --aster, --habanero, --tan, --royal, --depths; --orange now means the main color (royal).
- White panels with a thin tan line; tiles, cards and panels have square corners; buttons and inputs 4px. Card classes map to the palette (c-orange/c-sky → royal, c-lilac → depths, c-yellow → habañero, c-green/c-peach → aster, c-sand → tan, c-grey → white); royal/depths cards switch their text to light. Mi IGHO tiles use p-royal / p-hab / p-aster / p-tan / p-depths / p-white.
- Exceptions kept on purpose: the five Formación course colors (book covers), yellow/red attendance warnings, red for errors.
- IGHO icon is now a vector (Aster circle, Deadly Depths house). App icons recolored to royal. Phone first; Font: Outfit.

## Database (SQL files run in this order)
1. `01_esquema.sql`: personas, igho, ministerios, cursos, censos, perfiles, usuarios_roles, reuniones_igho, asistencia_igho, and RLS
2. `02_datos_censo_2026.sql`: 405 people / 22 IGHOs from the January 2026 census
3. Grants for `authenticated` (run by hand)
4. `03_anfitriones.sql`: conteo_anfitriones, conteo_kidz, asistencia_domingo view, notas_anfitriones
5. `04_domingo_worship_bienvenida_igho.sql`: Sunday program, worship v1, nuevos (Bienvenida), IGHO functions
6. `05_admin.sql`: lista_usuarios, guardar_roles, IGHO leaders can edit their members
7. `06_consejo_worship.sql`: cobertura_consejo, PDFs in Storage ("canciones" bucket), series, teams
8. Grants for `service_role` (run by hand; the Edge Function needs them)
9. `07_persona_nueva.sql`: crear_persona (replaced by 08)
10. `08_persona_nueva_worship.sql`: crear_persona for admin, Consejo and Worship leaders
11. `09_worship_ausencias.sql`: worship_ausencias ("No puedo ese domingo"), lidera_worship(), mi_persona()
12. `10_kidz.sql`: kidz_clases (2–3, 4–7, 8–11, S78 12–15), kidz_familias, kidz_ninos, kidz_checkins, kidz_siervos_dia, kidz_planes, kidz_turnos, kidz_notas_padres, kidz_anuncios, kidz_escanear(), trigger that fills conteo_kidz, private "kidz" photo bucket
13. `11_familias_multiplicar.sql`: hogares, persona_hogar, parentescos, sugerencias_descartadas, kidz_familias.hogar_id, fam_* functions (admin/secretaría edit; census suggestions); igho.igho_madre_id + fecha_inicio, persona_igho_historial (trigger on personas.igho_id), multiplicar_igho, mover_a_igho, cambiar_cobertura, consejo_lista, tablero_cobertura, visitas_igho; secretaría can read personas/igho
14. `12_anuncios_formacion.sql`: ministries anuncios / formacion / stand; conteo_anfitriones.manteles; anuncios_domingo + anuncios_items (+ anuncios_equipo()); fc_ofertas, fc_inscripciones, fc_buscar_personas, fc_inscribir (creates the person if new), fc_estado (completing a course class adds it to persona_cursos)
15. `13_consejo_cobertura.sql`: visitas_igho.personas/origen, cobertura_de_igho(), registrar_visitas_cobertura() (coverage + spouse in IGHO attendance → Consejo visit); consejo_tareas, consejo_notas, consejo_decisiones (decisions: Consejo adds, only admin corrects, original text kept); imports the 73 tasks from the council sheet the first time
16. `14_anuncios_v2.sql`: anuncios_domingo.anunciantes (several people, e.g. a couple) + anunciantes_nombres; anuncios_items.nota (note for the announcer, not read aloud); anuncios_fijos (recordatorio / importante / inicio / final, shown every Sunday); seeds the weekly items and 22-Nov's two new ones
17. `15_worship_areas_predica.sql`: worship_equipos.area (alabanza / consola / multimedia) + teams "Consola" and "Multimedia"; predica_archivos (sermon slides per Sunday: file or link, note for Multimedia, "descargado por"), sube_predica(), ve_predica(), predica_descargada(); private "predicas" Storage bucket (50 MB per file)
18. `16_difusion_formacion.sql`: cursos.color + se_ofrece, adds Alpha Matrimonios (codes: alpha_matrimonios, raices, herencia_1, herencia_2, legado); fc_ofertas.modalidad ('semanal' | 'intensivo') + sesiones date[] + grupo; puede_difusion(), difusion_lista() (kidz / no_bautizados / sin_curso / inscritos / lideres_igho); difusion_envios (log of messages sent)
19. `17_cumpleanos.sql`: mi_cumpleanos() and guardar_mi_cumpleanos(fecha) (a user reads / saves their own birth date through their perfil → persona)
20. `18_conyuges_stand.sql`: conyuges_consejo + es_conyuge_consejo() + marcar_conyuge_consejo(); a read policy "conyuge del consejo ve" on every table except consejo_*, difusion_envios, usuarios_roles, perfiles, cobertura_consejo, finanz*; storage read for canciones/kidz/predicas; edita_familias() and puede_difusion() now admin only; stand_actividades, anuncios_items.stand_actividad_id, stand_registros, en_ministerio(), lidera_ministerio(), edita_anuncios(), equipo_stand(), stand_buscar_ninos()
21. `19_censo_publico.sql`: censo_campanas (one row per census, random `codigo` for the link), censo_respuestas (staging, jsonb), anon RPCs censo_info / censo_buscar / censo_enviar, censo_respondieron(igho), censo_aplicar (admin: updates or creates people, censos row, hogar, parentescos, cursos), censo_descartar, censo_abrir_cerrar
22. `20_avisos.sql`: notificaciones, notificaciones_usuarios (inbox + read), push_suscripciones, ajustes_privados, puede_avisar(), destinatarios_aviso(destino), crear_aviso(), servicio_del_domingo(fecha), crear_recordatorios_servicio(fecha), pg_cron job `recordatorio-siervos` (Sunday 01:00 UTC = Saturday 20:00 Ecuador) calling `notificar`
23. `21_censo_rellenar.sql`: censo_persona(codigo, id) (anon): when someone picks «Es esta persona», returns their data, courses, tiempo en Arco, address and family (household + parentescos) so the form comes prefilled
24. `22_stand_igho.sql`: igho_interesados, stand_ighos(), stand_igho_interes() (creates the person if new, notifies the IGHO leader: notificaciones.tipo 'igho'); function action `enviar_interes`
25. `23_igho_lugar_bienvenida_finanzas.sql`: igho.direccion / horario / mapas text[] (fills the 22 IGHO by leader phone, then leader name; last query lists IGHO left without address), guardar_lugar_igho(); stand_ighos() now returns direccion/horario/mapas; borrar_persona_si_suelta() (deletes a person only if no IGHO and no row in any table that references personas); borrar_interes_igho() (also removes the leader's notice); nuevos_seguimiento view + sexo, anio_nacimiento_aprox (spouses can read); editar_nuevo(), borrar_nuevo(); finanzas_ingresos (Consejo/admin/finanzas; tipo semana/ajuste/mes) + Ríos 2026 income from the sheet (Jan–Jun monthly, Jul–Oct weekly)
26. `24_igho_editar_asistencia.sql`: editar_igho() (Consejo/admin: name, leader, place; removes the old leader's lider_igho role), crear_igho() (admin); re-applies IGHO addresses with leader NAME first, then phone (David/Josué Luna share a phone); Jamie Díaz replaces Andrés Torres as leader (Octavio Paz y J. Donoso, Martes 20:00); Ríos Sunday attendance 2026 from the sheet into conteo_anfitriones (children → ninos_auditorio; nuevos Jan–Apr; skips Sundays already counted in the app or with a Kidz count). Sur numbers are NOT imported.
27. `25_bienvenida_igho.sql`: puede_conectar_igho() (Stand team, Bienvenida, Consejo/admin); stand_ighos(), stand_igho_interes() and borrar_interes_igho() now allow Bienvenida too
28. `26_admin_borrar.sql`: policy «admin borra» (delete for admin) on every public RLS table except personas, perfiles, usuarios_roles, ajustes_privados, cobertura_consejo, conyuges_consejo; admin_borrar_persona() (deletes if the person appears nowhere else, otherwise deactivates: activo = false, out of their IGHO; refuses if they have an app account or lead an IGHO)

29. `27_clase_bienvenida.sql`: bv_clases (fecha1 / fecha2 = the two Sundays, hora, lugar, abierta), bv_inscritos (origen bienvenida / stand / clase), bv_asistencia (sesion 1 | 2); edita_clase_bv() (Bienvenida + Consejo/admin), inscribe_clase_bv() (+ Stand team); bv_guardar_clase, bv_borrar_clase, bv_inscribir (creates the person if new and adds them to nuevos), bv_quitar, bv_marcar, bv_lista, bv_buscar. Attending day 1 and day 2 (even in different classes) sets nuevos.clase_bienvenida = true + fecha_clase
30. `28_mi_igho_tarjeta_visitas.sql`: personas.igho_rol (lider / apoyo / anfitrion / asistente; IGHO leaders start as lider) + guardar_rol_igho(); igho.presentacion + guardar_tarjeta_igho(); stand_ighos() also returns presentacion; consejo_visitantes (user_id, conyuge_persona_id, todos_los_igho, sin_conyuge) + guardar_visitante_consejo() (admin; also adds the parentescos link) + conyuge_de_usuario(); cobertura_de_igho() rebuilt (adds column tipo: cobertura | presidente; spouse from consejo_visitantes, else family tree) and registrar_visitas_cobertura() no longer requires coverage; seeds Joel Guido as todos_los_igho, sin_conyuge (his wife doesn't attend IGHO for now)

31. `29_perfil_foto_igho.sql`: igho_fotos (one small JPEG data URL per IGHO, cropped to the card's left side) + guardar_foto_igho(); igho.categorias ('ninos' = Espacio para niños, 'menores18' = IGHO -18 años) + guardar_categorias_igho(); stand_ighos() also returns categorias; mis_datos() / guardar_mis_datos() (own persona through perfiles); solicitudes_ministerio + solicitar_ministerio() (notifies admins, tipo 'solicitud') + resolver_solicitud() (admin approves as servidor / lider_ministerio → inserts usuarios_roles, notifies the person)

## Roles
- `admin`, `anciano` (shown as **Miembro del Consejo**), `secretaria`, `finanzas`
- **Cónyuge del Consejo**: not a rol_t value but a row in `conyuges_consejo` (checkbox in Administración → Editar). Sees every page except Finanzas, Tablero, Reunión del Consejo, Mensajes por WhatsApp and Administración. Pages are read-only («👁 Solo lectura», class `solo-ver`) unless they also have the matching role (e.g. Líder de Kidz edits Kidz). Mi IGHO: all IGHOs readable, editable only their own.
- Only `admin` sees Administración (incl. Familias) and Mensajes por WhatsApp (the WhatsApp shortcuts in Kidz and Formación are hidden for everyone else).
- `lider_ministerio` / `servidor` (shown as "Líder" / "Siervo") + ministry (anfitriones, kidz, bienvenida, worship, anuncios, formacion, stand). In Anuncios the Siervo level is shown as **Anunciante**.
- Anuncios: Líder (Andrés Salas), Consejo and secretaría write each Sunday's announcements and choose who gives them; the Anunciante sees them first in Este domingo.
- Formación Cristiana: Líder creates classes/events and marks who completed; David Pazmiño covers it (Consejo coverage → Formación Cristiana). Stand de información: siervos register people to open classes/events.
- `lider_igho` + igho
- Admins and council members see everything; each council member's Resumen shows their own coverage (cobertura).
- A service team member only sees their own team's page + Este domingo.
- Login: cell number (stored as `09XXXXXXXX@arcorios.app`) or email, with a temporary password that must be changed on first login.
- Parents: sign up themselves from the login screen ("¿Eres papá o mamá?"). A parent = a user linked to a row in `kidz_familias` (no role); they see only "Mis niños".
- Kidz: siervo = check-in/out, registro, Mi servicio. Líder (and Consejo/admin) = also En vivo, Domingo (turnos + actividades), Anuncios, Datos.

## Done
Login, home page by role, Resumen (personalized per council member), Anfitriones count, Este domingo, Worship (PDFs with bulk upload that splits title/artist, series, teams, set list builder, custom instruments, "No puedo ese domingo" notices), Bienvenida, Mi IGHO (members, editing, attendance), Administración (incl. adding a new person not in the census).
Kidz with QR: camera check-in/check-out (photo confirmation, allergies, parent note, authorized pickup list), siervo QR with assignment + activities, live view by class, family registration with photo, shareable QR image, parent app (kids' QR, note for teachers, announcements), stats (attendance per Sunday, by class, frequency, kids missing 4+ weeks). Kidz count fills conteo_kidz automatically.

## Also done (21 Nov 2026)
- Administración → Familias (admin + secretaría): households, roles, "hijo de" links across households, Kidz family link, tree view, census suggestions (Sí / No).
- Multiplicar IGHO (Mi IGHO and the Tablero, for admin or the covering Consejo member): new leader (search or new person), members move with their household, coverage, one-step save with history; last step gives the new leader access (WhatsApp card). Mover marcados a otro IGHO; Cambiar cobertura for several IGHO.
- Tablero del Consejo (desktop, opens automatically for Consejo/admin on screens ≥1100px; also a home card): 12 cards, Sunday chart (each Sunday, month average, period average), people per coverage (bars instead of the mockup's donut, for legibility), IGHO table (reported x/4, visits), Necesitan seguimiento, IGHO tree, family tree; filters (Este mes / 3 meses / año / Personalizado, coverage) and Imprimir / PDF. Sections: Asistencia, IGHO y cobertura (detail, visits, multiply, move), Personas y familias, Nuevos, Kidz.
- "Pendientes del Consejo" card replaced by "Necesitan seguimiento" until council tasks move into the app.

## Also done (21 Nov 2026, second round)
- Este domingo → Anuncios panel (numbered list, who gives them, "Te toca dar los anuncios"), editor with copy from last Sunday.
- Formación Cristiana page (classes/events, registrations, WhatsApp reminders, Completó / Se retiró) and Stand de información page (pick class, search or new person, WhatsApp confirmation, today's list). Resumen shows a Formación panel to whoever covers it.
- Anfitriones: Manteles para lavar counter (not added to the total).
- Logos: Kidz and Arco Worship on their cards and pages; the Kidz QR image now carries the Kidz logo.

## Also done (21 Nov 2026, third round)
- Mi IGHO → Asistencia: the Consejo member who covers the IGHO and their spouse (from the family tree) appear as "Visita de cobertura". They are not members; marking them records a Consejo visit that the Tablero counts.
- Reunión del Consejo (Tablero menu + home card): Pendientes (add, complete, notes, "Ya no aplica" instead of deleting, search), Decisiones (date, Consejo / Consejo ampliado, tema), Acta (by date: decisions, new tasks, completed, notes; accent-insensitive search with highlights; print). Tablero card 6 is "Pendientes del Consejo" again.
- Logos: Mi IGHO (house) and Formación Cristiana seal on their cards and pages.

## Anuncios (22 Nov 2026)
- Each Sunday shows: yellow Recordatorio and red Importante boxes, then the fixed announcements «al inicio» (Bienvenida, Iglesias de hogar), the week's new ones (marked «Nuevo»), then the fixed ones «al final» (Oración, Final), numbered in one list.
- The weekly editor only holds the new ones; «Editar lo que se anuncia cada semana» edits the fixed set (with an Activo switch to pause one).

## Worship teams and sermon slides (22 Nov 2026)
- Each Worship team has an area: Alabanza (Equipo A, Equipo B), Consola (sound), Multimedia (screens/slides). Equipos tab groups them by area; new teams choose their area.
- Armar lista: 3. Equipo de alabanza (A/B), 4. Consola, 5. Multimedia. Changing A↔B keeps Consola and Multimedia. One job per person per Sunday; the function (Consola, Multimedia, Proyección…) decides which section it shows in.
- New "Prédica" tab (everyone in Worship + Consejo): the preaching elder (Consejo/admin) or a Worship leader uploads slides, video, PDF (≤50 MB each) or pastes a Drive/Canva link, with a note for Multimedia. Multimedia taps Descargar (keeps the original file name); the file shows "✓ Descargado por …" so the preacher knows it arrived.
- Este domingo has a "Subir diapositivas de la prédica" button for Consejo/admin; Resumen's Worship panel warns when the slides are missing.

## Stacked-card home and Resumen (23 Nov 2026)
- Home: big header ("Hola, Joel" + gray date), then one full-width colored card per section the user can see, with a big live number (attendance, Kidz, nuevos, Worship songs, next Sunday's date + preacher, Formación, Stand, IGHO reported x/total or the leader's members, people, Consejo pendientes). Tablero, Administración and Finanzas show an arrow instead of a number.
- Cards start stacked (title + number visible, the rest as thin edges) and spread open as you scroll; a small header slides in at the top. If all cards fit on screen (e.g. a siervo with 2 cards) they don't stack.
- Resumen uses the same cards: IGHO you cover, attendance, Kidz, nuevos, Worship, Formación, whole church, people per IGHO, time in Arco.
- Component: pintarPila / llenarTarjeta / medirPila / aplicarPilas; per-card data in DATOS_HOME.

## WhatsApp messages and the five courses (23 Nov 2026)
- New page "Mensajes por WhatsApp" (home card). Lists: Padres de Kidz (by class, or only those who came in the last 8 weeks), No bautizados (by IGHO), No han tomado una clase (pick the course; option "only those who did the previous course"; leaves out people who have it or are already enrolled), Inscritos en una clase, Líderes de IGHO. Admin / Consejo / secretaría see all; Kidz líder → parents; Formación líder → class lists.
- Message with {nombre} (first name; Kidz uses the parents' names); one message per phone (people sharing a phone get one message with both names). Send one by one (opens WhatsApp with the text ready, then "next"), or for a WhatsApp broadcast list: download contacts (.vcf), copy message, copy numbers. Each send is logged in difusion_envios.
- Shortcuts: Kidz → Anuncios ("Mensaje por WhatsApp a los padres", a WhatsApp button on each announcement and right after publishing); a class page → "Invitar a quienes no han tomado…" and "Mensaje a los inscritos".
- Formación Cristiana: "+ Abrir clases" picks one or more of Alpha Matrimonios, Raíces, Herencia I, Herencia II, Legado (each with its book-cover color and emblem). Each is 7 semanas (the first date fills all 7 weekly dates, each editable) or Intensivo (pick the Friday → Friday + Saturday). One fc_ofertas row per course, sharing a grupo. Events are separate ("+ Nuevo evento"). The class page lists the 7 dates or the intensive weekend.

## Birthdays and the card stack (23 Nov 2026)
- personas.fecha_nacimiento existed but the census only gave age (anio_nacimiento_aprox), so most adults have no date yet. The home page asks each user once ("¿Cuándo es tu cumpleaños?", "Ahora no" hides it for 30 days); IGHO leaders can add it in Editar ficha; Kidz children already have it.
- On your birthday the app opens with confetti and a "¡Feliz cumpleaños!" card (once per day; a banner on home lets you replay it).
- Mi IGHO: "Cumpleaños esta semana" panel (Monday–Sunday, age, hoy / mañana / fue el…), 🎂 next to the name, count of members missing a date; the leader's home IGHO card lists them too.
- Kidz check-in: if the child had a birthday in the last 7 days (or today) → banner + confetti. If the child is registered in a class younger than their age → "¿Pasa a la clase de los grandes?" (Sí, cambiar updates kidz_ninos.clase_id and today's check-in; "Todavía no" isn't asked again until the next birthday on that device).
- Home stack: starts a little lower; the opening distance now depends on where the stack starts, so the first card is fully open before it reaches the top.

## Spouses, Stand, census link, notifications (23 Nov 2026, second round)
- Cónyuge del Consejo (see Roles). Generic view-only guard: a capture click handler blocks anything that isn't navigation (`SV_PERMITIDO`), CSS hides save buttons and `.solo-edit` panels.
- Anuncios editor: each new announcement has «Inscripciones en el Stand: No / Sí · personas / Sí · niños». That creates a `stand_actividades` row; copying the announcement to the next Sunday keeps the same list. Panel shows a green «Inscripciones en el Stand» tag.
- Stand de información: only this Sunday's NEW announcements (no fixed ones, reminders or Importante; tap to expand; «Inscribir» on the ones with sign-ups). «Iglesia de hogar (IGHO)» option: pick the IGHO, the person; the leader gets a notice (or a WhatsApp button if the leader has no app) and sees them in Mi IGHO → «Quieren unirse» (WhatsApp, Ya le contacté, Agregar al IGHO), then one pick list with the Stand activities and Formación classes. Niños: search Kidz children or type name, birth date, parent, phone. List of who signed up (leader can close the sign-up or remove someone).
- Logos: Stand (info icon) and Bienvenida (add-person icon) from The Noun Project, Anfitriones (two people in a circle).
- Census by link: `…/Arco-app/?censo=<codigo>` opens without login. Step 1 search yourself (name + surname; the list shows IGHO and last 3 phone digits) or «soy nuevo/a»; step 2 your data, already filled from the base (21_censo_rellenar.sql), to check and correct; step 3 the family already registered (each with «Revisar»); step 3 add family (relationship, lives with me, search or new). Answers wait in Administración → Censo: shows old → new values, lets you join a «new» person to someone already in the base, then Aplicar or Descartar. Mi IGHO → Censo: the link, WhatsApp share, who already answered.
- Avisos: bell on home (unread count) + banner with the latest unread aviso; Avisos page (activate phone notifications, test, my avisos). Admin and Consejo send to Toda la iglesia / equipo / Consejo y cónyuges / Líderes IGHO / Padres de Kidz / one ministry, and choose which page it opens. Saturday 20:00 automatic «Mañana sirves en Arco» from Worship set list, Kidz turnos and Anuncios. iPhone: notifications only after «Agregar a pantalla de inicio». New files next to index.html: `sw.js`, `manifest.json`, `icon-192.png`, `icon-512.png`, `badge-96.png`.

## IGHO places, Bienvenida edits, income (23 Nov 2026, v4)
- Each IGHO has day/time, address and one or more Google Maps links (David Cabrera's rotates between two houses). Mi IGHO shows a «Dónde y cuándo se reúne» panel the leader or Consejo can edit.
- Stand → IGHO: choosing the IGHO shows day/time, address and map; the WhatsApp to the person now carries the IGHO name, day/time, address, map link(s) and the leader's name + phone. The leader's WhatsApp from «Quieren unirse» also includes the location.
- Delete an IGHO sign-up (×): in Mi IGHO → Quieren unirse (leader/Consejo) and in the Stand's today list. Removes the leader's notice too; the person is deleted from the base only if they exist nowhere else.
- Bienvenida: Editar (name, phone, sex, age, first visit, how they came, IGHO interest, notes) and × Borrar on each person; filter renamed «Sin clase de bienvenida».
- Finanzas page (home card shows the year's income): year total, monthly bars, tap a month for its weeks (diezmo/ofrenda when known), form to record a week / adjustments / a month total. Also in the Tablero → Finanzas. Gastos pending the expense report.

## IGHO editor (23 Nov 2026, v5)
- Mi IGHO → «Editar IGHO» (Consejo/admin): name, leader (search or new person), day/time, address, map links. Changing the leader offers the access step (crear_lider_igho). «Celular del líder» field (v7) saves personas.telefono of the leader (used for the WhatsApp to the leader). Leaders still edit only day/time/address/maps. Admin has «+ Nuevo IGHO» (e.g. Josué Merchán's, which wasn't in the base).

## Bienvenida → IGHO (23 Nov 2026, v6)
- Registering a new person with IGHO interest Sí / Tal vez shows «¿A qué IGHO?». Choosing one saves the interest (leader gets the app notice, note «Persona nueva (Bienvenida)») and shows the same ✓ Listo card as the Stand (ighoListoHtml): WhatsApp to the person with day/time, address, map and leader; WhatsApp to the leader (now always offered, in the Stand too).
- Seguimiento: people with interest and no IGHO have an «IGHO» button to do the same later.

## Admin delete (23 Nov 2026, v8)
- Administración → «Borrar datos»: Conteos del domingo (Anfitriones, optionally Kidz count + check-ins of that day), Reuniones de IGHO (with attendance), Visitas de cobertura, Inscritos en clases, Avisos (removes from everyone's bell), Registro de WhatsApp, Personas (admin_borrar_persona). Anfitriones history also shows × for admin. Deletes check that a row was actually removed (RLS silently deletes 0 rows).

## Avisos delete + PDF reports (23 Nov 2026, v10–v11)
- v10: admin × on Avisos page (Mis avisos and Avisos enviados).
- v11: «📄 Informe» button top-right on Anfitriones, Kidz, Bienvenida, Worship, Este domingo (Anuncios), Formación, Stand and Mi IGHO, for that ministry's leaders + Consejo/admin (IGHO: lider_igho, current IGHO). Pick dates (último mes / 3 meses / año / custom) → downloads a PDF (html2pdf.js 0.10.2 from jsDelivr, loaded on first use; fallback opens a print window). Code: INFORMES, botonInforme (called from show()), dialogoInforme, generarInforme, descargarPdf, INF_CSS. Contents: Anfitriones (attendance per Sunday + averages, manteles, team notes); Kidz (per Sunday × class, servers, each child's visits); Bienvenida (new people, how they came, class, IGHO); Worship (each Sunday: team, songs+key, who served; top songs; times each person served; absences); Anuncios (each Sunday's items + announcer); Formación (classes in range, enrolled/completed/withdrew, lists); Stand (activity, class and IGHO sign-ups); IGHO (meetings with who came, each member's attendance, coverage visits, people wanting to join).

## Clase de bienvenida (23 Nov 2026, v12)
- Bienvenida page now has two tabs: Personas (register + Seguimiento) and «Clase de bienvenida».
- «Bienvenido a la familia» is every other month, two Sundays in a row (morning). «+ Nueva clase» suggests the date two months after the last class (moved to Sunday); the second Sunday fills itself (+7 days, editable); hora (default 09:00), lugar, notas; Editar can close sign-ups.
- Sign-ups: checkbox when registering a new person («Inscribir en la clase de bienvenida», on by default), «Clase» button in Seguimiento, «Inscribir marcados» from the Bienvenida list inside the class, search / new person, and the Stand (option «Bienvenido a la familia», with WhatsApp confirmation).
- Pasar lista: Día 1 / Día 2 switch (opens on today's day), tap each person; people who arrive without signing up are added and marked in one step. Each person shows where they signed up, a WhatsApp reminder button and «✓ completó» once they have both days. The Bienvenida home card shows the next class.

## Mi IGHO tiles, notification routing (25 Nov 2026, v13)
- Mi IGHO: top «🔔 Quieren unirse» box (notification space), then tiles: Asistencia (last meeting x/members), Añadir miembro, Info de miembros, Cumpleaños, Resumen (average attendance), Compartir. Each opens a sub-page with «‹ Mi IGHO». Censo tab removed (census by link only).
- Asistencia: names yellow when the person hasn't come in more than 2 weeks, red after more than a month (counted from the last meeting they attended before the chosen date). Bottom: Consejo visits = the IGHO's coverage + spouse, and Joel on every IGHO (his wife hidden).
- Info de miembros: role per member (Líder, Apoyo, Anfitrión, Asistente) with a selector; also in Editar ficha and when adding a new person.
- Resumen: members, average per meeting, meetings in 30 days, Consejo visits this year, % baptized, % with a class, last meetings, roles, Necesitan seguimiento (with WhatsApp), missing data.
- Compartir: the IGHO card (name, presentación, day/time, address, map, leader + phone): Enviar por WhatsApp / Copiar. The same card goes in the Stand/Bienvenida WhatsApp to the person and the leader's WhatsApp from «Quieren unirse».
- Administración → Editar (Consejo/admin): «Visitas a los IGHO»: pick the spouse, «Su esposo/a no aparece en la asistencia», and «Aparece en la asistencia de todos los IGHO».
- Phone notifications: general aviso → home page (or the page the sender picked; «Al tocarlo abre» default is now «Página principal»); «Mañana sirves» → the ministry page; IGHO interest → Mi IGHO. Opening one marks it read. Home shows a blue «🏠 X quiere unirse a tu IGHO» banner for leaders until they mark «Ya le contacté».

## Palette, IGHO card (25 Nov 2026, v14)
- Whole app restyled to the light palette above (also the Tablero charts, PDF reports and confetti).
- Mi IGHO: the round back arrow at the top returns to the tiles when a section is open (and to home from the tiles).
- Compartir: the IGHO card is drawn as an image in the business-card style (landscape on the left, Deep Space Royal panel on the right, house icon, name, IGLESIA DE HOGAR · ARCO RÍOS, day/time, address, leader + phone). «Enviar la tarjeta (imagen)» shares it on the phone (or downloads it), plus «Enviar como texto por WhatsApp» and «Copiar el texto».

## IGHO photo, profile, dark mode (25 Nov 2026, v15)
- Compartir: the card's left side is the IGHO photo («📷 Subir foto», cropped automatically; landscape when there's none). Leader's name appears once (only «Cel.» when the IGHO name is the leader's name). Every line is measured against the diagonal so text never crosses into the photo. Presentación removed; instead toggle buttons «🧒 Espacio para niños» and «🎒 IGHO -18 años» (on the card, in the WhatsApp text and in the Stand's IGHO list).
- WhatsApp text always carries the Google Maps link(s). Sharing the image also copies the text (WhatsApp sometimes drops the caption).
- Mi perfil (tap your initial, top right of home): my data (name, phone, birth date), Claro/Oscuro switch (saved on the device), change password, «Quiero servir en un ministerio» (request + status), Cerrar sesión.
- Administración → Solicitudes: approve as Siervo/Anunciante or Líder, or «No aprobar»; the person gets a notice.
- notificar.ts: «enviar_interes» also sends tipo 'solicitud' (redeploy the function so the admin gets the phone push; without it the request still shows in the bell).

## Folder tabs on home (25 Nov 2026, v16)
- Home and Resumen cards look like file folders: each card's name is on a tab (monospace caps) at a staggered position (PESTANA_POS, alternating left/right). Stacked, only the tabs and a thin edge show (PILA.SLIVER 42; content of thin cards fades with --pleg); scrolling opens them. Card title moved to the tab (.pc-lbl hidden).
- Fix: Administración card (c-white) was navy text on navy; now a white folder with a thin line.

## Maps link always (25 Nov 2026, v17)
- mapasIgho(g): the IGHO's saved Google Maps links, or (if none) a Google Maps search link built from the address + «Cuenca, Ecuador». Used in every WhatsApp text (Compartir, Stand, Bienvenida, «Quieren unirse»).

## Tiles on home and Kidz (25 Nov 2026, v18)
- Home is now a 2-column grid of square tiles (pintarMosaico; every 5th tile full width) with icon, live number (or ↗), name and short line; same DATOS_HOME/llenarTarjeta data. Resumen keeps the folder stack.
- Kidz opens on tiles (kzInicio): Ingreso (niños hoy · siervos), En vivo (en clase ahora), Mi servicio, Registro, Domingo (date), Anuncios, Datos (niños registrados); each opens its section with a title; the top back arrow returns to the Kidz tiles. The tab bar is gone.

## Status (23 Nov 2026, end of day)
- Notifications work on Joel's Android (function `swift-action` deployed with notificar.ts, Verify JWT off).
- To confirm: `21_censo_rellenar.sql` and `22_stand_igho.sql` run in Supabase; cron job `recordatorio-siervos` points to `/functions/v1/swift-action` (check: `select command from cron.job where jobname = 'recordatorio-siervos';`).

## Status (23 Nov 2026, after v11)
- Files 23 and 26 ran OK in Supabase. Confirm 24 (IGHO editor, Jamie Díaz, attendance import) and 25 (Bienvenida → IGHO) were run too.
- After deleting the Kidz test counts of 20 and 22 Nov, add the sheet's 22 Nov count (337 adults, 68 children) if not done: `insert into conteo_anfitriones (fecha, adultos, ninos_auditorio, nuevos, registrado_nombre, actualizado_en) values ('2026-11-22', 337, 68, 0, 'Hoja de asistencia 2026', now()) on conflict (fecha) do nothing;`
- Supabase SQL editor tip: run each file in a New query with the whole file pasted; temp tables don't survive between statements there.

## Pending
- Test notifications on an iPhone (Safari → Agregar a pantalla de inicio first); check the first Saturday reminder (Supabase → Edge Functions → swift-action → Logs, Saturday 20:00)
- Decide: should Consejo spouses see Reunión del Consejo? (now hidden)
- Decide: add a privacy check to the census link (last 4 phone digits or birth year before showing someone's data)
- Weekly schedule for Anfitriones / Bienvenida / Stand so they also get the Saturday reminder
- Finances: income done (v4); add expenses by category when the expense report arrives. October week 1 is $0 in the sheet and November has no Ríos figures yet
- Josué Merchán's IGHO is not in the base: create it with «+ Nuevo IGHO» (Plaza Roma · Estocolmo y Copenhague, Jueves 20:00, https://maps.app.goo.gl/sKEZYBvJFnaMMLbv8)
- Decide: import past Sunday attendance from the "Counsel Dashboard" sheet; move preaching / events into the app
- Check two imported task dates: "Audicion en Enero Febrero" is dated 17-Ene-2027 in the sheet; "10-21-0206" was read as 21 Oct 2026
- Review the 49 census records flagged in `para_revisar.csv`

## How to update
- SQL: Supabase → SQL Editor → New query → Run (each file once).
- App: GitHub → repository → Add file → Upload files → `index.html` (plus `sw.js`, `manifest.json` and the icons when they change) → Commit.
- Edge Function: Supabase → Edge Functions → open the function → Code → paste → Deploy.
