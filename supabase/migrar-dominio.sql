-- =============================================================================
-- SquashMatch — pasar el correo interno a un dominio reservado
-- =============================================================================
-- Supabase Auth exige un identificador con forma de correo, así que el ID de
-- socio se completa con un dominio por detrás. El jugador nunca lo ve ni lo
-- escribe: entra con "clubsirio" o "andres.soto".
--
-- Ese dominio era squash.cl, que es de otra persona. Pasa a
-- socios.squashmatch.internal, porque .internal está reservado justamente para
-- esto y nunca va a pertenecerle a nadie: ningún correo puede salir por error
-- hacia un tercero.
--
-- Correr UNA vez, y después de haber desplegado la versión de la app que usa el
-- dominio nuevo. Si se corre antes, nadie puede entrar hasta que se despliegue.
--
-- Ejecutar en el SQL Editor de Supabase.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Sacar las cuentas de prueba que quedaron de diagnosticar el registro.
--    Va primero: no tiene sentido migrarlas para borrarlas después.
-- -----------------------------------------------------------------------------
delete from auth.users
 where email like 'zz.test.%'
    or email like 'zz.prueba.%';

-- -----------------------------------------------------------------------------
-- 2. El correo con que Supabase busca la cuenta al entrar.
-- -----------------------------------------------------------------------------
update auth.users
   set email = replace(email, '@squash.cl', '@socios.squashmatch.internal')
 where email like '%@squash.cl';

-- -----------------------------------------------------------------------------
-- 3. La copia que Supabase guarda aparte, en la identidad del proveedor
--    'email'. Si no se actualiza, las dos versiones quedan en desacuerdo.
-- -----------------------------------------------------------------------------
update auth.identities
   set identity_data = jsonb_set(
         identity_data, '{email}',
         to_jsonb(replace(identity_data->>'email',
                          '@squash.cl', '@socios.squashmatch.internal')))
 where provider = 'email'
   and identity_data->>'email' like '%@squash.cl';

-- -----------------------------------------------------------------------------
-- 4. La copia en profiles, que es la que lee la app.
--    La app ya no la muestra cuando reconoce que es interna, pero se migra igual
--    para que las dos tablas digan lo mismo.
-- -----------------------------------------------------------------------------
update public.profiles
   set email = replace(email, '@squash.cl', '@socios.squashmatch.internal')
 where email like '%@squash.cl';

-- -----------------------------------------------------------------------------
-- 5. Comprobación: la primera consulta debe devolver 0 y la segunda, 14.
-- -----------------------------------------------------------------------------
select 'quedan con el dominio viejo' as que, count(*) as total
  from auth.users where email like '%@squash.cl'
union all
select 'ya con el dominio interno', count(*)
  from auth.users where email like '%@socios.squashmatch.internal';
