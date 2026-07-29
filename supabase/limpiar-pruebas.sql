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
delete from public.challenges
 where message ~* '(auditor|prueba|vencido|vigente|canal|revancha del|jugamos el domingo)';

-- Publicaciones de canchas abiertas hechas para probar.
delete from public.open_invites
 where message ~* '(auditor|prueba|canal)';

-- Reservas del club que solo existieron para comprobar la cancelación.
-- Sus cobros se van con ellas.
delete from public.bookings
 where source = 'club'
   and status = 'cancelada';

-- Restos de texto de prueba en las biografías de los perfiles.
update public.profiles
   set bio = ''
 where bio ~* '(audit|prueba de|test )';

-- -----------------------------------------------------------------------------
-- Comprobación: las tres consultas deberían devolver 0.
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
 where club_note ~* '(auditor|prueba)';
