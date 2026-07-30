-- =============================================================================
-- SquashMatch — jugadores y partidos de prueba
-- =============================================================================
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor de Supabase.
--
-- Crea 12 cuentas de prueba con perfil, club, categoría y un historial de
-- partidos ya confirmados, para que el directorio, el ranking y las
-- estadísticas se vean vivos al mostrar la app.
--
-- Para entrar se escribe solo el nombre, sin dominio: la app lo completa sola.
--
--   Jugadores:    joaquin, camila, rodrigo, …   Contraseña: squash2026
--   Club Sirio:   clubsirio                     Contraseña: admin2026
--                 Es cuenta de administración del club, no juega.
--
-- Por detrás quedan como nombre@socios.squashmatch.internal, porque Supabase
-- exige un identificador con forma de correo. Nadie recibe correo ahí.
--
-- Sirven para iniciar sesión y recorrer la app como cualquiera de ellos.
--
-- OJO: inserta directo en auth.users, la tabla interna de Supabase. Es un camino
-- no oficial, válido para poblar un prototipo. En producción los usuarios deben
-- entrar registrándose.
--
-- Para borrar todo lo que crea este script:
--   delete from auth.users where email like '%@socios.squashmatch.internal';
-- =============================================================================

-- pgcrypto es la que cifra la contraseña. En Supabase viene instalada; esta
-- línea solo se asegura de que esté disponible.
create extension if not exists pgcrypto with schema extensions;

-- Limpia una corrida anterior de este mismo script, para poder repetirlo.
delete from auth.users where email like '%@socios.squashmatch.internal';

-- -----------------------------------------------------------------------------
-- 1. Cuentas
-- -----------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  j.correo,
  extensions.crypt('squash2026', extensions.gen_salt('bf')),
  now(), now() - (j.antiguedad || ' days')::interval, now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', j.nombre),
  '', '', '', ''
from (values
  ('matias@socios.squashmatch.internal',     'Matías Fuentes',    120),
  ('cristobal@socios.squashmatch.internal',  'Cristóbal Herrera', 115),
  ('rodrigo@socios.squashmatch.internal',    'Rodrigo Vera',      110),
  ('felipe@socios.squashmatch.internal',     'Felipe Cárcamo',    100),
  ('sebastian@socios.squashmatch.internal',  'Sebastián Rojas',    95),
  ('tomas@socios.squashmatch.internal',      'Tomás Aguilera',     90),
  ('joaquin@socios.squashmatch.internal',    'Joaquín Silva',      85),
  ('pablo@socios.squashmatch.internal',      'Pablo Navarrete',    80),
  ('camila@socios.squashmatch.internal',     'Camila Rojas',       75),
  ('fernanda@socios.squashmatch.internal',   'Fernanda Lagos',     70),
  ('valentina@socios.squashmatch.internal',  'Valentina Muñoz',    65),
  ('jorge@socios.squashmatch.internal',      'Jorge Salazar',      60)
) as j(correo, nombre, antiguedad)
where not exists (select 1 from auth.users u where u.email = j.correo);

-- Identidad de correo: sin esto el inicio de sesión con contraseña no funciona.
insert into auth.identities (
  id, user_id, identity_data, provider, provider_id,
  last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(), u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', u.id::text, now(), now(), now()
from auth.users u
where u.email like '%@socios.squashmatch.internal'
  and not exists (
    select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email'
  );

-- -----------------------------------------------------------------------------
-- 2. Perfiles
-- El trigger handle_new_user() ya creó la fila con nombre y correo; acá se
-- completan categoría, ranking y club.
-- -----------------------------------------------------------------------------
update public.profiles p
   set category      = d.categoria,
       national_rank = d.ranking,
       hand          = d.mano,
       comuna        = d.comuna,
       playing_since = d.desde,
       club_id       = d.club
from (values
  ('cristobal@socios.squashmatch.internal', 'Primera',    1, 'Zurdo',   'Providencia',  '2009', 'c2'),
  ('matias@socios.squashmatch.internal',    'Primera',    3, 'Diestro', 'Las Condes',   '2011', 'c2'),
  ('felipe@socios.squashmatch.internal',    'Segunda',   12, 'Diestro', 'Ñuñoa',        '2015', 'c2'),
  ('tomas@socios.squashmatch.internal',     'Tercera',   41, 'Diestro', 'La Reina',     '2018', 'c2'),
  ('pablo@socios.squashmatch.internal',     'Cuarta',    68, 'Zurdo',   'Macul',        '2021', 'c2'),
  ('rodrigo@socios.squashmatch.internal',   'Primera',    7, 'Diestro', 'Las Condes',   '2010', 'c1'),
  ('sebastian@socios.squashmatch.internal', 'Segunda',   24, 'Zurdo',   'Vitacura',     '2016', 'c1'),
  ('joaquin@socios.squashmatch.internal',   'Tercera',   52, 'Diestro', 'Las Condes',   '2019', 'c1'),
  ('camila@socios.squashmatch.internal',    'Damas A',    2, 'Diestro', 'Las Condes',   '2014', 'c1'),
  ('fernanda@socios.squashmatch.internal',  'Damas A',    5, 'Zurdo',   'Lo Barnechea', '2017', 'c1'),
  ('valentina@socios.squashmatch.internal', 'Damas B',   21, 'Diestro', 'Vitacura',     '2020', 'c1'),
  ('jorge@socios.squashmatch.internal',     'Máster +40', 6, 'Diestro', 'Las Condes',   '2005', 'c1')
) as d(correo, categoria, ranking, mano, comuna, desde, club)
where p.email = d.correo;

-- -----------------------------------------------------------------------------
-- 2b. Cuenta de administración del Club Sirio
-- No es un jugador: no aparece en el directorio ni en el ranking.
--   Correo: clubsirio@socios.squashmatch.internal   ·   Contraseña: admin2026
-- -----------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select
  '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
  'authenticated', 'authenticated', 'clubsirio@socios.squashmatch.internal',
  extensions.crypt('admin2026', extensions.gen_salt('bf')),
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', 'Club Sirio · Administración'),
  '', '', '', ''
where not exists (select 1 from auth.users where email = 'clubsirio@socios.squashmatch.internal');

insert into auth.identities (
  id, user_id, identity_data, provider, provider_id,
  last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', u.id::text, now(), now(), now()
from auth.users u
where u.email = 'clubsirio@socios.squashmatch.internal'
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email');

update public.profiles
   set staff = true, club_id = 'c1', name = 'Club Sirio · Administración'
 where email = 'clubsirio@socios.squashmatch.internal';

insert into public.club_admins (club_id, player_id)
select 'c1', id from public.profiles where email = 'clubsirio@socios.squashmatch.internal'
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- 3. Partidos jugados, todos con resultado ya confirmado
-- Las fechas son distintas entre sí para que ninguna reserva choque de cancha.
-- -----------------------------------------------------------------------------
insert into public.bookings (
  club_id, court, match_date, match_time, player_a, player_b,
  status, winner_id, sets_winner, sets_loser, result_status, reported_by
)
select
  m.club, m.cancha, current_date - m.dias, m.hora,
  pa.id, pb.id, 'confirmada', pg.id, m.sets_g, m.sets_p, 'confirmado', pa.id
from (values
  -- Club Sirio
  ('c1', 1,  3, '19:00', 'rodrigo',   'sebastian', 'rodrigo',   3, 1),
  ('c1', 2,  6, '20:00', 'joaquin',   'sebastian', 'sebastian', 3, 2),
  ('c1', 1, 10, '19:00', 'camila',    'fernanda',  'camila',    3, 0),
  ('c1', 2, 13, '18:00', 'jorge',     'joaquin',   'jorge',     3, 1),
  ('c1', 1, 17, '20:00', 'rodrigo',   'jorge',     'rodrigo',   3, 0),
  ('c1', 2, 21, '19:00', 'valentina', 'fernanda',  'fernanda',  3, 1),
  ('c1', 1, 26, '21:00', 'sebastian', 'camila',    'sebastian', 3, 2),
  ('c1', 2, 31, '19:00', 'joaquin',   'valentina', 'joaquin',   3, 1),
  ('c1', 1, 38, '20:00', 'rodrigo',   'joaquin',   'rodrigo',   3, 1),
  ('c1', 2, 45, '19:00', 'camila',    'valentina', 'camila',    3, 0),
  -- Santiago Squash
  ('c2', 1,  4, '19:00', 'cristobal', 'matias',    'cristobal', 3, 1),
  ('c2', 2,  8, '20:00', 'felipe',    'tomas',     'felipe',    3, 0),
  ('c2', 1, 12, '18:00', 'matias',    'felipe',    'matias',    3, 2),
  ('c2', 2, 16, '19:00', 'tomas',     'pablo',     'tomas',     3, 1),
  ('c2', 1, 22, '20:00', 'cristobal', 'felipe',    'cristobal', 3, 0),
  ('c2', 2, 28, '19:00', 'pablo',     'felipe',    'felipe',    3, 1),
  ('c2', 1, 35, '21:00', 'matias',    'tomas',     'matias',    3, 0),
  ('c2', 2, 42, '19:00', 'cristobal', 'pablo',     'cristobal', 3, 0)
) as m(club, cancha, dias, hora, a, b, ganador, sets_g, sets_p)
join public.profiles pa on pa.email = m.a       || '@socios.squashmatch.internal'
join public.profiles pb on pb.email = m.b       || '@socios.squashmatch.internal'
join public.profiles pg on pg.email = m.ganador || '@socios.squashmatch.internal'
where not exists (
  select 1 from public.bookings b
   where b.club_id = m.club and b.match_date = current_date - m.dias
     and b.match_time = m.hora and b.court = m.cancha
);

-- -----------------------------------------------------------------------------
-- 4. Comprobación: si esto devuelve 12 filas, quedó todo listo.
-- -----------------------------------------------------------------------------
select c.name as club, p.name as jugador, p.email as correo,
       p.category as categoria, p.national_rank as ranking, p.rating as puntos
  from public.profiles p
  join public.clubs c on c.id = p.club_id
 where not p.staff
 order by c.name, p.rating desc nulls last;

-- =============================================================================
-- PARA BORRAR TODO ESTO (los perfiles, partidos y desafíos se van en cascada):
--
--   delete from auth.users where email like '%@socios.squashmatch.internal';
--
-- =============================================================================
