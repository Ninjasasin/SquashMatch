-- =============================================================================
-- SquashMatch — jugadores y partidos de prueba
-- =============================================================================
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor de Supabase.
--
-- Crea 12 cuentas fantasma con perfil, club, categoría y un historial de partidos
-- ya confirmados, para que el directorio, la escalerilla y las estadísticas se
-- vean vivos al mostrar la app.
--
-- Todas usan el dominio @demo.squashmatch.cl y la contraseña  demo2026squash
-- así que también sirven para iniciar sesión y recorrer la app como cualquiera
-- de ellos.
--
-- OJO: inserta directo en auth.users, la tabla interna de Supabase. Es un camino
-- no oficial, válido para poblar un prototipo. En producción los usuarios deben
-- entrar registrándose.
--
-- Para borrar todo lo que crea este script (al final del archivo está la línea
-- completa):  delete from auth.users where email like '%@demo.squashmatch.cl';
-- =============================================================================

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
  extensions.crypt('demo2026squash', extensions.gen_salt('bf')),
  now(), now() - (j.antiguedad || ' days')::interval, now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', j.nombre),
  '', '', '', ''
from (values
  ('matias.fuentes@demo.squashmatch.cl',    'Matías Fuentes',    120),
  ('cristobal.herrera@demo.squashmatch.cl', 'Cristóbal Herrera', 115),
  ('rodrigo.vera@demo.squashmatch.cl',      'Rodrigo Vera',      110),
  ('felipe.carcamo@demo.squashmatch.cl',    'Felipe Cárcamo',    100),
  ('sebastian.rojas@demo.squashmatch.cl',   'Sebastián Rojas',    95),
  ('tomas.aguilera@demo.squashmatch.cl',    'Tomás Aguilera',     90),
  ('joaquin.silva@demo.squashmatch.cl',     'Joaquín Silva',      85),
  ('pablo.navarrete@demo.squashmatch.cl',   'Pablo Navarrete',    80),
  ('camila.rojas@demo.squashmatch.cl',      'Camila Rojas',       75),
  ('fernanda.lagos@demo.squashmatch.cl',    'Fernanda Lagos',     70),
  ('valentina.munoz@demo.squashmatch.cl',   'Valentina Muñoz',    65),
  ('jorge.salazar@demo.squashmatch.cl',     'Jorge Salazar',      60)
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
where u.email like '%@demo.squashmatch.cl'
  and not exists (
    select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email'
  );

-- -----------------------------------------------------------------------------
-- 2. Perfiles
-- El trigger handle_new_user() ya creó la fila con nombre y correo; acá se
-- completan categoría, ranking y club. Al asignar el club, el trigger
-- place_in_ladder() ubica a cada uno al final de la escalerilla, así que el
-- orden de esta lista es el orden inicial de la escalerilla.
-- -----------------------------------------------------------------------------
update public.profiles p
   set category      = d.categoria,
       national_rank = d.ranking,
       hand          = d.mano,
       comuna        = d.comuna,
       playing_since = d.desde,
       club_id       = d.club
from (values
  ('cristobal.herrera@demo.squashmatch.cl', 'Primera',        1,  'Zurdo',   'Providencia', '2009', 'c2'),
  ('matias.fuentes@demo.squashmatch.cl',    'Primera',        3,  'Diestro', 'Las Condes',  '2011', 'c2'),
  ('felipe.carcamo@demo.squashmatch.cl',    'Segunda',       12,  'Diestro', 'Ñuñoa',       '2015', 'c2'),
  ('tomas.aguilera@demo.squashmatch.cl',    'Tercera',       41,  'Diestro', 'La Reina',    '2018', 'c2'),
  ('pablo.navarrete@demo.squashmatch.cl',   'Cuarta',        68,  'Zurdo',   'Macul',       '2021', 'c2'),
  ('rodrigo.vera@demo.squashmatch.cl',      'Primera',        7,  'Diestro', 'Las Condes',  '2010', 'c1'),
  ('sebastian.rojas@demo.squashmatch.cl',   'Segunda',       24,  'Zurdo',   'Vitacura',    '2016', 'c1'),
  ('joaquin.silva@demo.squashmatch.cl',     'Tercera',       52,  'Diestro', 'Las Condes',  '2019', 'c1'),
  ('camila.rojas@demo.squashmatch.cl',      'Damas A',        2,  'Diestro', 'Las Condes',  '2014', 'c1'),
  ('fernanda.lagos@demo.squashmatch.cl',    'Damas A',        5,  'Zurdo',   'Lo Barnechea','2017', 'c1'),
  ('valentina.munoz@demo.squashmatch.cl',   'Damas B',       21,  'Diestro', 'Vitacura',    '2020', 'c1'),
  ('jorge.salazar@demo.squashmatch.cl',     'Máster +40',     6,  'Diestro', 'Las Condes',  '2005', 'c1')
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
  ('c1', 1,  3, '19:00', 'rodrigo.vera',    'sebastian.rojas', 'rodrigo.vera',    3, 1),
  ('c1', 2,  6, '20:00', 'joaquin.silva',   'sebastian.rojas', 'sebastian.rojas', 3, 2),
  ('c1', 1, 10, '19:00', 'camila.rojas',    'fernanda.lagos',  'camila.rojas',    3, 0),
  ('c1', 2, 13, '18:00', 'jorge.salazar',   'joaquin.silva',   'jorge.salazar',   3, 1),
  ('c1', 1, 17, '20:00', 'rodrigo.vera',    'jorge.salazar',   'rodrigo.vera',    3, 0),
  ('c1', 2, 21, '19:00', 'valentina.munoz', 'fernanda.lagos',  'fernanda.lagos',  3, 1),
  ('c1', 1, 26, '21:00', 'sebastian.rojas', 'camila.rojas',    'sebastian.rojas', 3, 2),
  ('c1', 2, 31, '19:00', 'joaquin.silva',   'valentina.munoz', 'joaquin.silva',   3, 1),
  ('c1', 1, 38, '20:00', 'rodrigo.vera',    'joaquin.silva',   'rodrigo.vera',    3, 1),
  ('c1', 2, 45, '19:00', 'camila.rojas',    'valentina.munoz', 'camila.rojas',    3, 0),
  -- Santiago Squash
  ('c2', 1,  4, '19:00', 'cristobal.herrera','matias.fuentes', 'cristobal.herrera', 3, 1),
  ('c2', 2,  8, '20:00', 'felipe.carcamo',  'tomas.aguilera',  'felipe.carcamo',  3, 0),
  ('c2', 1, 12, '18:00', 'matias.fuentes',  'felipe.carcamo',  'matias.fuentes',  3, 2),
  ('c2', 2, 16, '19:00', 'tomas.aguilera',  'pablo.navarrete', 'tomas.aguilera',  3, 1),
  ('c2', 1, 22, '20:00', 'cristobal.herrera','felipe.carcamo', 'cristobal.herrera', 3, 0),
  ('c2', 2, 28, '19:00', 'pablo.navarrete', 'felipe.carcamo',  'felipe.carcamo',  3, 1),
  ('c2', 1, 35, '21:00', 'matias.fuentes',  'tomas.aguilera',  'matias.fuentes',  3, 0),
  ('c2', 2, 42, '19:00', 'cristobal.herrera','pablo.navarrete','cristobal.herrera', 3, 0)
) as m(club, cancha, dias, hora, a, b, ganador, sets_g, sets_p)
join public.profiles pa on pa.email = m.a       || '@demo.squashmatch.cl'
join public.profiles pb on pb.email = m.b       || '@demo.squashmatch.cl'
join public.profiles pg on pg.email = m.ganador || '@demo.squashmatch.cl'
where not exists (
  select 1 from public.bookings b
   where b.club_id = m.club and b.match_date = current_date - m.dias
     and b.match_time = m.hora and b.court = m.cancha
);

-- -----------------------------------------------------------------------------
-- 4. Comprobación
-- -----------------------------------------------------------------------------
select c.name as club, p.ladder_pos as puesto, p.name as jugador,
       p.category as categoria, p.national_rank as ranking
  from public.profiles p
  join public.clubs c on c.id = p.club_id
 order by c.name, p.ladder_pos;

-- =============================================================================
-- PARA BORRAR TODO ESTO (los perfiles, partidos y desafíos se van en cascada):
--
--   delete from auth.users where email like '%@demo.squashmatch.cl';
--
-- =============================================================================
