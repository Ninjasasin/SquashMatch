-- =============================================================================
-- SquashMatch — jugadores y partidos de prueba
-- =============================================================================
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor de Supabase.
--
-- Crea 12 cuentas de prueba con perfil, club, categoría y un historial de
-- partidos ya confirmados, para que el directorio, la escalerilla y las
-- estadísticas se vean vivos al mostrar la app.
--
--   Correos:      nombre@squash.cl   (camila@squash.cl, rodrigo@squash.cl, …)
--   Contraseña:   squash2026
--
-- Sirven para iniciar sesión y recorrer la app como cualquiera de ellos.
--
-- OJO: inserta directo en auth.users, la tabla interna de Supabase. Es un camino
-- no oficial, válido para poblar un prototipo. En producción los usuarios deben
-- entrar registrándose.
--
-- Para borrar todo lo que crea este script:
--   delete from auth.users where email like '%@squash.cl';
-- =============================================================================

-- pgcrypto es la que cifra la contraseña. En Supabase viene instalada; esta
-- línea solo se asegura de que esté disponible.
create extension if not exists pgcrypto with schema extensions;

-- Limpia una corrida anterior de este mismo script, para poder repetirlo.
delete from auth.users where email like '%@demo.squashmatch.cl';

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
  ('matias@squash.cl',     'Matías Fuentes',    120),
  ('cristobal@squash.cl',  'Cristóbal Herrera', 115),
  ('rodrigo@squash.cl',    'Rodrigo Vera',      110),
  ('felipe@squash.cl',     'Felipe Cárcamo',    100),
  ('sebastian@squash.cl',  'Sebastián Rojas',    95),
  ('tomas@squash.cl',      'Tomás Aguilera',     90),
  ('joaquin@squash.cl',    'Joaquín Silva',      85),
  ('pablo@squash.cl',      'Pablo Navarrete',    80),
  ('camila@squash.cl',     'Camila Rojas',       75),
  ('fernanda@squash.cl',   'Fernanda Lagos',     70),
  ('valentina@squash.cl',  'Valentina Muñoz',    65),
  ('jorge@squash.cl',      'Jorge Salazar',      60)
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
where u.email like '%@squash.cl'
  and not exists (
    select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email'
  );

-- -----------------------------------------------------------------------------
-- 2. Perfiles
-- El trigger handle_new_user() ya creó la fila con nombre y correo; acá se
-- completan categoría, ranking y club. Al asignar el club, el trigger
-- place_in_ladder() ubica a cada uno al final de la escalerilla, así que el
-- orden de esta lista es el orden inicial de cada escalerilla.
-- -----------------------------------------------------------------------------
update public.profiles p
   set category      = d.categoria,
       national_rank = d.ranking,
       hand          = d.mano,
       comuna        = d.comuna,
       playing_since = d.desde,
       club_id       = d.club
from (values
  ('cristobal@squash.cl', 'Primera',    1, 'Zurdo',   'Providencia',  '2009', 'c2'),
  ('matias@squash.cl',    'Primera',    3, 'Diestro', 'Las Condes',   '2011', 'c2'),
  ('felipe@squash.cl',    'Segunda',   12, 'Diestro', 'Ñuñoa',        '2015', 'c2'),
  ('tomas@squash.cl',     'Tercera',   41, 'Diestro', 'La Reina',     '2018', 'c2'),
  ('pablo@squash.cl',     'Cuarta',    68, 'Zurdo',   'Macul',        '2021', 'c2'),
  ('rodrigo@squash.cl',   'Primera',    7, 'Diestro', 'Las Condes',   '2010', 'c1'),
  ('sebastian@squash.cl', 'Segunda',   24, 'Zurdo',   'Vitacura',     '2016', 'c1'),
  ('joaquin@squash.cl',   'Tercera',   52, 'Diestro', 'Las Condes',   '2019', 'c1'),
  ('camila@squash.cl',    'Damas A',    2, 'Diestro', 'Las Condes',   '2014', 'c1'),
  ('fernanda@squash.cl',  'Damas A',    5, 'Zurdo',   'Lo Barnechea', '2017', 'c1'),
  ('valentina@squash.cl', 'Damas B',   21, 'Diestro', 'Vitacura',     '2020', 'c1'),
  ('jorge@squash.cl',     'Máster +40', 6, 'Diestro', 'Las Condes',   '2005', 'c1')
) as d(correo, categoria, ranking, mano, comuna, desde, club)
where p.email = d.correo;

-- -----------------------------------------------------------------------------
-- 3. Partidos jugados, todos con resultado ya confirmado
-- Las fechas son distintas entre sí para que ninguna reserva choque de cancha.
-- -----------------------------------------------------------------------------
insert into public.bookings (
  club_id, court, match_date, match_time, player_a, player_b,
  status, winner_id, sets_winner, sets_loser, result_status, reported_by, ladder
)
select
  m.club, m.cancha, current_date - m.dias, m.hora,
  pa.id, pb.id, 'confirmada', pg.id, m.sets_g, m.sets_p, 'confirmado', pa.id, false
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
join public.profiles pa on pa.email = m.a       || '@squash.cl'
join public.profiles pb on pb.email = m.b       || '@squash.cl'
join public.profiles pg on pg.email = m.ganador || '@squash.cl'
where not exists (
  select 1 from public.bookings b
   where b.club_id = m.club and b.match_date = current_date - m.dias
     and b.match_time = m.hora and b.court = m.cancha
);

-- -----------------------------------------------------------------------------
-- 4. Comprobación: si esto devuelve 12 filas, quedó todo listo.
-- -----------------------------------------------------------------------------
select c.name as club, p.ladder_pos as puesto, p.name as jugador,
       p.email as correo, p.category as categoria, p.national_rank as ranking
  from public.profiles p
  join public.clubs c on c.id = p.club_id
 order by c.name, p.ladder_pos;

-- =============================================================================
-- PARA BORRAR TODO ESTO (los perfiles, partidos y desafíos se van en cascada):
--
--   delete from auth.users where email like '%@squash.cl';
--
-- =============================================================================
