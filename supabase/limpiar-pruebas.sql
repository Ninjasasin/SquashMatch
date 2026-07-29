-- =============================================================================
-- SquashMatch — limpieza de datos de prueba
-- =============================================================================
-- Borra lo que quedó de las verificaciones hechas durante el desarrollo:
-- desafíos con textos como "auditoría" o "prueba canal", publicaciones de
-- prueba y reservas canceladas que solo existían para comprobar que la
-- cancelación funcionaba.
--
-- NO toca a los jugadores, sus partidos jugados, los ratings ni los cobros
-- reales. Es seguro correrlo las veces que haga falta.
--
-- Ejecutar en el SQL Editor de Supabase. No requiere desplegar nada.
-- =============================================================================

-- Desafíos creados para probar (el texto los delata). Al borrarlos, las reservas
-- que salieron de ellos se conservan: quedan como partidos agendados normales.
-- counter_msg va en el filtro porque una contrapropuesta de prueba puede llevar
-- el texto delator solo en la respuesta y no en el desafío original.
delete from public.challenges
 where message ~* '(auditor|prueba|vencido|vigente|canal|revancha del|jugamos el domingo)'
    or counter_msg ~* '(auditor|prueba|no puedo tan temprano)';

-- Publicaciones de canchas abiertas hechas para probar.
delete from public.open_invites
 where message ~* '(auditor|prueba|canal)';

-- Reservas del club que solo existieron para comprobar la cancelación.
-- Sus cobros se van con ellas.
delete from public.bookings
 where source = 'club'
   and status = 'cancelada';

-- Reservas de la app canceladas durante las pruebas, sin resultado cargado.
-- Solo las de estos últimos días: las canceladas viejas son historia real.
delete from public.bookings
 where source = 'app'
   and status = 'cancelada'
   and result_status = 'sin_resultado'
   and created_at > now() - interval '3 days';

-- Avisos del club mandados para probar.
delete from public.club_messages
 where body ~* '(auditor|prueba)';

-- Marcas de "no llamar" puestas para probar.
delete from public.player_flags
 where note ~* '(auditor|prueba|rotura de fibras)';

-- Restos de texto de prueba en las biografías de los perfiles.
update public.profiles
   set bio = ''
 where bio ~* '(audit|prueba de|test )';

-- -----------------------------------------------------------------------------
-- Comprobación: todas las consultas deberían devolver 0.
-- -----------------------------------------------------------------------------
select 'desafíos de prueba' as que, count(*) as quedan
  from public.challenges
 where message ~* '(auditor|prueba|vencido|vigente|canal)'
union all
select 'publicaciones de prueba', count(*)
  from public.open_invites
 where message ~* '(auditor|prueba|canal)'
union all
select 'notas de prueba en reservas', count(*)
  from public.bookings
 where club_note ~* '(auditor|prueba)'
union all
select 'avisos de prueba', count(*)
  from public.club_messages
 where body ~* '(auditor|prueba)'
union all
select 'marcas de prueba', count(*)
  from public.player_flags
 where note ~* '(auditor|prueba|rotura de fibras)';
