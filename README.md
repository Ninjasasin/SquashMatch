# SquashMatch

Plataforma de gestión de canchas de squash para un club, con una app para sus socios.

El club opera el calendario: crea las cuentas de sus socios, reserva a su nombre, anota los
resultados, cobra a cada uno y avisa cuando hay cancha libre. El socio entra con el ID que
le dieron en recepción y puede desafiar, agendar, ver su ranking y sus estadísticas.

**App publicada:** [squash-match.vercel.app](https://squash-match.vercel.app/)

Los datos viven en Supabase, así que el club y los jugadores se ven entre sí desde
cualquier dispositivo. La app necesita estar publicada para funcionar: abrir el archivo con
doble clic ya no sirve.

## El modelo: las cuentas las crea el club

Esto es lo primero que hay que entender, porque condiciona todo lo demás.

**No hay registro público.** El socio pasa por recepción, le entregan su ID y su clave
inicial, y con eso entra. No necesita correo, y de hecho la mayoría no va a tener uno
registrado.

La razón es de adopción, no técnica: una app que no está en las tiendas no se la baja nadie,
así que esperar que los jugadores se registren solos era esperar sentados. Con este modelo
el club tiene al 100% de sus socios adentro desde el primer día, el ranking existe desde el
primer partido que alguien anote, y los datos quedan limpios porque los escribe el club y no
cada uno como quiere.

La consecuencia es que **la app sirve aunque ningún jugador la abra**. La autogestión —que
el socio reserve solo, mande desafíos, publique horarios— queda disponible para cuando el
hábito llegue, y llegar va a tomar tiempo.

### El ID de socio y el RUT

**El ID es `nombre.apellido`** y es lo único que el jugador escribe para entrar:
`juan.perez`. Se propone solo desde el nombre, tomando la primera y la segunda palabra y no
la última, porque en Chile "Juan Pérez Gómez" es Juan Pérez y no Juan Gómez. Con nombres
compuestos sale mal y el club lo corrige a mano, que es el caso menos frecuente.

**El RUT es la llave única del padrón.** La base rechaza un segundo socio con el mismo RUT,
así que un socio que se fue y vuelve al año recupera su historial y su rating en vez de
empezar de cero. Dos detalles que hacen que el candado cierre de verdad:

- Se guarda **normalizado**, sin puntos ni guion y con la K en mayúscula. Si no,
  `12.345.678-5` y `123456785` son dos filas distintas y la restricción no sirve de nada.
- Se **valida el dígito verificador** por módulo 11, para que un dedazo en el mostrador no
  cree un socio fantasma que después nadie pueda unir con el real.

Y cuando el RUT ya existe, la app no dice "duplicado": dice **de quién es y cuándo jugó por
última vez**. Eso importa más de lo que parece — con un error seco, la recepción termina
inventando un RUT falso para poder seguir.

### La clave

La genera el sistema, tipo `KPQM-4738`, sin caracteres que se confundan (ni O ni 0, ni l ni
1) porque alguien la va a dictar en un mostrador y otro la va a escribir en un teléfono.

**El socio no entra sin cambiarla.** El club la conoce, así que en la primera entrada la app
obliga a elegir una propia antes de dejar pasar.

Si la pierde, vuelve a recepción y el club se la regenera. **No hay recuperación por
correo** porque no hay correo real al que mandar nada. Ese reseteo corre en una Edge Function
—[`supabase/functions/reset-clave`](supabase/functions/reset-clave/index.ts)— porque cambiar
la contraseña de otra persona necesita la llave de servicio de Supabase, que no puede vivir
en el código de una página web.

Por detrás, Supabase Auth exige un identificador con forma de correo, así que el ID se
completa con `@socios.squashmatch.internal`. El jugador nunca lo ve ni lo escribe. `.internal`
está reservado y no puede pertenecerle a nadie, así que ningún correo puede salir por error
hacia un tercero. Antes ese dominio era `squash.cl`, que es de otra persona;
[`supabase/migrar-dominio.sql`](supabase/migrar-dominio.sql) es la migración que ya se
corrió, y queda como registro de que también hay que actualizar `auth.identities`, donde
Supabase guarda una segunda copia del correo.

## Qué hace el club

Todo desde la pestaña **Mi club**, que es su portada.

### Socios

- **Crear socio**: nombre, RUT, teléfono, categoría. Devuelve el ID y la clave inicial para
  entregar.
- **Editar**: se corrigen nombre, RUT, teléfono, categoría, comuna y mano hábil. Los
  teléfonos cambian y en el mostrador se comete un dedazo, así que la ficha tiene que ser
  corregible. El **ID no se cambia**: es con lo que entra y por detrás define su correo
  interno, así que cambiarlo dejaría la cuenta sin poder iniciar sesión.
- **Listado completo** con búsqueda por nombre y filtro entre los del club, todos, o solo
  los marcados. La búsqueda **ignora los acentos**: escribir "andres" encuentra a "Andrés",
  porque nadie teclea tildes en un buscador.

### Reservas

- **Reserva a nombre de socios**, eligiendo a los dos jugadores. El cobro sigue la regla
  obvia: cada mitad se le carga a alguien si se sabe a quién.

  | Quiénes | Cómo se cobra |
  |---|---|
  | Dos socios | $7.500 a cada uno, igual que si hubieran reservado solos |
  | Un socio y un invitado | $7.500 al socio, la otra mitad sin nombre |
  | Dos invitados | $15.000 por la cancha, con la nota de quién jugó |

  El modal lo dice con nombres **antes** de reservar, para que el mostrador no tenga que
  deducirlo.

- **El jugador se elige escribiendo**, no abriendo un desplegable: con 70 socios buscar a
  ojo en una lista es peor que teclear tres letras. Funciona con teclado completo, y avisa
  en rojo si quedó texto escrito sin elegir de la lista — esa es la trampa obvia, y sin el
  aviso la reserva se guardaría como invitado sin cobro a nadie.

- **Agenda del día en columnas**, una por cancha, con quién juega, la nota, los cobros y su
  estado. Apiladas en filas había que leer el texto para saber cuál estaba libre a esa hora,
  que es justo la pregunta que uno se hace.

- **Cancelar** libera la cancha y anula los cobros: lo que no se jugó no se cobra.

### Resultados

El club puede **anotar el resultado** de cualquier partido jugado entre dos socios. Entre
jugadores el resultado lo carga uno y lo confirma el otro, porque ahí alguien podría
inventarse una victoria; cuando lo anota el club no hay nada que confirmar —vio el partido—
así que queda confirmado al instante y mueve el rating. Queda registrado quién lo anotó.

En Gestión hay una lista de **partidos jugados sin resultado**, que es la lista de trabajo
del cierre del día: con el club anotando por todos, si no se ven juntos se pierden.

Un partido con un invitado sin cuenta no entra al ranking: no hay a quién moverle el rating.

**Se puede corregir**, y conviene saber qué implica. Corregir un resultado ya confirmado
obliga a rehacer los ratings desde cero en orden cronológico (`recalc_ratings()`), porque el
historial se calculó con el resultado anterior y no se puede restar un partido sin
recalcular la cadena. La primera vez que se corrija, **varios ratings van a moverse un
poco**: es la deriva acumulada que se repara, no un error. Vale avisárselo al club antes de
que lo vea.

### Avisar que hay cancha libre

El club ya sabe quién juega los martes a las 17:00. En vez de telefonear, le manda el aviso:

- **En la app**: aparece arriba de todo en Inicio del jugador, con un botón que **publica que
  juega en ese bloque** con la fecha y la hora ya puestas. Un aviso que obliga a ir a buscar
  el horario a mano se pierde.
- **Por WhatsApp**: un enlace `wa.me` que abre WhatsApp con el mensaje ya escrito, y la
  persona del mostrador aprieta enviar. **La app nunca envía sola.**

El texto se arma solo con la fecha, la hora y la cancha elegidas —escribirlo a mano cada vez
es la clase de fricción que hace que una función no se use— y se puede editar. Antes de
enviar avisa si ese bloque ya está tomado.

Es a propósito la versión simple de WhatsApp: no cuesta nada por mensaje, no necesita
verificar la empresa ante Meta, ni plantillas aprobadas, ni un número dedicado. La API
(≈US$0,014 por mensaje en Chile) se justificará cuando sepamos cuántos avisos manda de
verdad al día.

### No llamar

Anotación interna del club sobre un socio: está lesionado, de vacaciones o no disponible,
con la ventana de fechas en que dura.

Sale de un problema concreto: a un lesionado lo llamaban todos los días para ofrecerle
cancha y el jugador terminaba molesto de repetir lo mismo.

**Al jugador no le cambia nada** —sigue agendando y siendo desafiado igual— y **no la ve por
ningún lado**. Es gestión de reservas, no una función del jugador. Vive en una tabla del club
que solo lee quien lo administra: si un jugador la consulta por la API, recibe cero filas.

La fecha de término es lo que hace que esto no se pudra: al pasar, la marca deja de aplicar
sola, sin que nadie tenga que acordarse de sacarla.

### Cobranza

La cancha vale $15.000 y se cobra **por jugador**: dos cobros de $7.500, que es como se paga
en la práctica. El club marca cada uno como pagado, ve quién debe y cuántos días lleva. El
jugador ve su propia deuda.

**Descarga del estado de cuenta** en planilla, con todos los movimientos y el total por
cobrar. Es el respaldo del club: el plan gratis de Supabase no hace copias de seguridad, así
que la cobranza no puede vivir en un solo lugar.

### Reporte de turnos

El número que los ejecutivos cuentan a mano en el cuaderno para saber si llegaron a su meta
del día.

- **Turnos reservados por día contra la meta.** El Club Sirio pide 16 de lunes a viernes y 8
  los fines de semana. Es del club completo, sin importar quién cubra el turno.
- Turnos de hoy, promedio diario, días que se cumplió la meta, y **qué porcentaje se reservó
  por la app** sin pasar por el mostrador. Ese último es el número que Easy Cancha no le
  puede mostrar.
- Gráfico día por día con la marca de la meta sobre cada barra, que baja sola el fin de
  semana. Las canceladas no cuentan: la cancha quedó libre.

### Panel de gestión

Ocupación media, mapa de calor de cuándo se juega, uso por cancha y quiénes juegan más. Y
una **búsqueda por ventana de horario**: elige un turno o una hora exacta y aparecen los que
más juegan en ese bloque, con cuándo vinieron por última vez y qué días suelen poder,
ampliando de tres en tres. Se puede filtrar por día de la semana, con una casilla para
incluir o excluir el fin de semana —un sábado a las 10 no se compara con un martes a las 10.

### Configuración

El club no depende de nosotros para cambiar sus propias reglas:

- **Horario y turnos**: hora de apertura, hora del último turno y duración. Muestra en vivo
  cuántos turnos salen de lo que se está escribiendo.
- **Metas** del reporte, de semana y de fin de semana.
- **Reglamento interno** y **política de cancelación**.
- **Contacto**: teléfono, correo, dirección.

## Qué hace el jugador

- **Inicio** — próximos 7 días, avisos, últimos partidos, acceso directo a desafiar y
  noticias del circuito PSA.
- **La grilla de turnos es de cada club**, no de la app. El Club Sirio corre de **08:00 a
  22:00 en turnos de 40 minutos**: 22 por cancha, 44 entre las dos. Antes la app asumía
  bloques de una hora, que no es como trabaja ningún club que hayamos visto, y con la grilla
  equivocada su conteo nunca iba a cuadrar con el del cuaderno.

  Como las horas redondas casi no existen en una grilla de 40 minutos —el Sirio no tiene las
  19:00, tiene 18:40 y 19:20— los modales proponen el turno **más cercano** a la hora que uno
  tenía en mente.
- **Desafíos con elección de cancha** — club, fecha, hora y cancha, con el estado real de
  cada una en ese bloque. Al aceptar, la cancha queda reservada en el acto.
- **Contrapropuesta de horario** — muchas veces sí quieren jugar pero la hora no acomoda, y
  antes la única salida era rechazar. Ahora el desafiado responde con otro día u hora y un
  mensaje, y le vuelve al que desafió para que confirme.

  Solo una vuelta: si el horario nuevo tampoco sirve, se rechaza y se manda un desafío
  nuevo. Sin ese límite es una negociación sin cierre.

  Por eso **Solicitudes agrupa por a quién le toca responder** y no por quién envió: con las
  contrapropuestas el turno se invierte, y agrupando por remitente lo accionable quedaba
  escondido.
- **Canchas abiertas** — publicar "quiero jugar tal día a tal hora" sin apuntarle a nadie.
  Publicar no toma la cancha: se reserva al confirmar, así que se la lleva la primera pareja
  que confirma. La categoría es una preferencia, no un muro.
- **Los desafíos y las publicaciones vencen solos** cuando pasa su horario.
- **Resultados en dos pasos** — uno carga quién ganó y el marcador **en sets** (3-0, 3-1,
  3-2, 2-0, 2-1; los parciales de cada game no se piden, nadie los recuerda) y el rival
  confirma o rechaza. Quien lo cargó no puede confirmarlo. El marcador se muestra desde
  quien mira: una derrota se ve 1-3, no 3-1.
- **Ranking propio, estilo Elo** — todos parten según su categoría y cada partido confirmado
  mueve puntos. Ganarle a alguien mejor rankeado suma más. Es de **suma cero**: lo que uno
  gana el otro lo pierde. K de 32 los primeros 10 partidos y 20 después, multiplicador por
  margen, y **K a la mitad cuando dos juegan más de tres veces en 30 días** para que la
  pérdida tienda a cero entre los mismos rivales.
- **Reglamento y contacto del club** — plegados en la vista Canchas, que es el momento en
  que importan. Deliberadamente **no** es un modal al entrar: uno que hay que cerrar cada vez
  se aprende a cerrar sin leer, que es peor que no tenerlo. La política de cancelación además
  sale junto al botón de cancelar una reserva.
- **Mi perfil** — panel, estadísticas (efectividad, racha, partidos por mes, rivales
  frecuentes, rendimiento contra mejor rankeados) y edición de sus datos.

## Cómo está hecho

La interfaz es un solo archivo `index.html` con el HTML, el CSS y el JavaScript en línea.
Los datos viven en **Supabase**: PostgreSQL, autenticación y actualizaciones en vivo. El
esquema completo está en [`supabase/schema.sql`](supabase/schema.sql) y la guía de montaje en
[`docs/backend-supabase.md`](docs/backend-supabase.md).

Lo que corre en el navegador:

- `fetchAll()` lee todo al iniciar sesión, y se vuelve a leer después de cada acción.
- `checkSlot()` / `courtFree()` validan la disponibilidad para la interfaz: avisan temprano y
  evitan viajes inútiles. La decisión real la toma el servidor.
- `slotsOf()` arma la grilla de un club desde su horario y la guarda; `slotCercano()` elige el
  turno más parecido a una hora deseada, y `metaDelDia()` resuelve si ese día corre la meta de
  semana o la de fin de semana.
- `sinAcentos()` es el único lugar donde se decide cómo comparar texto escrito por una
  persona. Lo usan los tres buscadores.
- `normalizarRut()` y `rutValido()` duplican a propósito lo que hace la base: avisar del
  dedazo mientras se escribe, sin esperar el viaje al servidor.

Lo que corre en el servidor, porque es donde se puede garantizar:

- `accept_challenge()` revalida horario, disponibilidad de ambos jugadores y cancha, y crea
  la reserva en una sola transacción. Un índice único sobre club, fecha, hora y cancha impide
  la doble reserva aunque dos personas acepten en el mismo segundo.
- `counter_challenge()` reemplaza el horario del desafío y guarda el anterior, de modo que
  `accept_challenge()` no necesita saber que las contrapropuestas existen. Lo único que cambia
  ahí es quién puede aceptar, que se da vuelta.
- `join_invite()` / `confirm_invite()` cierran una publicación creando la reserva, validando
  lo mismo que `accept_challenge()`.
- `report_result()` deja el resultado *por confirmar*; `confirm_result()` solo puede
  ejecutarla el rival. `club_report_result()` lo anota confirmado, comprobando que quien llama
  administre el club.
- `apply_elo()` mueve el rating y corre dentro de las dos anteriores: nunca desde el
  navegador. `recalc_ratings()` rehace todos los ratings desde cero en orden cronológico.
- `club_crear_socio()` completa la ficha de una cuenta recién creada y `club_editar_socio()`
  la corrige. Van por función y no por un `grant` de update porque el club está escribiendo en
  la fila de **otra** persona, y eso no puede quedar abierto.
- `socio_por_rut()` responde de quién es un RUT sin entregar el RUT de nadie.
- `contact_of()` entrega correo y teléfono a quien tenga una reserva confirmada con esa
  persona; `club_contacto()` se los entrega al club, pero solo de los socios que tienen a ese
  club como sede o que jugaron ahí. Un club no puede sacar los teléfonos de los jugadores de
  otro.
- `club_book()` / `set_club_note()` / `club_cancel()` / `mark_payment()` /
  `set_club_config()` son las del club, y todas comprueban que quien llama lo administre: un
  jugador que intente marcarse un pago recibe un error del servidor, no de la interfaz.
- `club_notes()` entrega las notas de las reservas solo a quien administra el club.
- Los cobros los crea un disparador al confirmarse la reserva y otro los anula al cancelarse.
  Un índice único garantiza que la parte sin nombre de una reserva tenga un solo cobro: la
  restricción normal no sirve porque en SQL dos nulos no se consideran iguales.
- `normalizar_rut()` y `rut_valido()` sostienen la llave única del padrón.

Y una **Edge Function**, la única pieza que no es ni navegador ni SQL:

- [`reset-clave`](supabase/functions/reset-clave/index.ts) regenera la clave de un socio.
  Cambiar la contraseña de otra persona necesita la llave de servicio, que no puede vivir en
  el código de la app: cualquiera que abra el navegador podría leerla y con ella crear, borrar
  o suplantar usuarios.

  Dos cosas separadas a propósito adentro: **quién llama** se resuelve con su propio token,
  preguntándole a la base por `is_club_admin`, que usa `auth.uid()`. La llave de servicio se
  usa solo para leer y escribir, **nunca para decidir permisos**. Y no deja resetear cuentas
  de club ni de administración, o el club podría tomarse la cuenta de otro administrador.

  Necesita un secreto llamado `SM_SECRET_KEY` con la llave secreta del proyecto, y que
  `service_role` tenga permisos sobre las tablas —los da la sección 13 del esquema. Sin eso
  las consultas fallan con `42501` aunque la llave sea la correcta.

### Al agregar una columna sensible, sácala del SELECT general

En Supabase el permiso por omisión es **todos los autenticados ven todas las columnas**, así
que proteger un dato es siempre una decisión deliberada. Ya pasó tres veces:

- El correo y el teléfono de los jugadores.
- La nota que el club escribe en cada reserva, que lleva nombres de invitados y detalles de
  cobro. Estuvo llegando al navegador de cualquier jugador: la interfaz no la mostraba, pero
  viajaba en la consulta y bastaba con pedirla a la API para leerla.
- El RUT de los socios.

El patrón es el mismo en los tres casos:

1. `revoke select on <tabla> from authenticated` y volver a otorgar **solo** las columnas
   públicas, una por una.
2. Entregar la columna reservada con una función `security definer` que compruebe quién
   pregunta (`contact_of()`, `club_notes()`, `club_contacto()`, `socio_por_rut()`).
3. En el cliente, pedir columnas explícitas en vez de `select('*')`, porque con permisos por
   columna el asterisco falla.

Ojo con el paso 1: **cada columna nueva hay que sumarla al `grant`**, o la app empieza a
recibir "permission denied" sin más explicación.

Y una advertencia general: esconder algo en la interfaz no protege nada. La clave pública de
la app está a la vista en el código de la página —así está diseñado— y cualquiera puede
consultar la base con ella. Lo único que cuenta es lo que prohíbe el servidor.

### Trampas del esquema que ya nos costaron una vuelta

- **Un `check` escrito dentro del `create table` no se actualiza** en una base que ya existe,
  porque ese `create` no vuelve a correr. Agregar un valor nuevo al `check` de `status` no
  bastaba: hay que reemplazarlo con un `alter` explícito.
- **El `if exists` de `drop trigger` cubre el trigger, no la tabla.** Si la tabla ya no está,
  la línea revienta con `relation does not exist` y, como el editor corre todo en una
  transacción, voltea el esquema completo.
- **Las columnas que agrega cada esquema nuevo** pueden no existir todavía en la base. La app
  pide los perfiles de más a menos columnas y usa la primera consulta que responde, para
  seguir andando aunque el esquema vaya un paso atrás.

### Rendimiento

- Los datos se releen completos después de cada acción, en vez de actualizar solo lo que
  cambió. Con este volumen es más simple y más seguro; con cientos de jugadores habría que
  refinarlo.
- Los avisos en vivo llegan de a varios por acción, así que se agrupan y disparan una sola
  relectura.
- Las estadísticas de cada jugador y el último movimiento de rating se calculan una vez por
  carga, no cada vez que se piden. Cada vista se dibuja al entrar en ella; los contadores de
  las pestañas se calculan aparte, porque deben estar al día aunque el jugador esté mirando
  otra sección.

Las tablas están en la publicación `supabase_realtime`, así que los desafíos, las reservas y
los cambios de rating llegan solos a las pantallas abiertas, sin recargar.

Las noticias del circuito son un arreglo de datos al inicio del script, con el texto en
español y el enlace a la fuente. Las miniaturas son ilustraciones SVG generadas en el propio
archivo: no se usan fotos de prensa, por derechos de autor.

## Puesta en marcha

1. Correr [`supabase/schema.sql`](supabase/schema.sql) completo en el SQL Editor. Es
   idempotente.
2. En **Authentication → Email**, dejar **"Confirm email" apagado**. Con las cuentas creadas
   por el club no hay correo real al que mandar confirmación, y el servicio interno de
   Supabase tiene un límite de unos pocos envíos por hora: con la confirmación activa el club
   se queda pegado al cuarto socio.
3. Desplegar la Edge Function `reset-clave` y crear el secreto `SM_SECRET_KEY` con la llave
   secreta del proyecto. Esa llave no va nunca en el código ni en el repositorio.
4. Opcional: [`supabase/seed-demo.sql`](supabase/seed-demo.sql) para tener contenido de
   muestra.

## Datos de prueba

[`supabase/seed-demo.sql`](supabase/seed-demo.sql) crea 12 jugadores en los dos clubes, con
perfil, categoría y 18 partidos confirmados. Se corre **después** de `schema.sql`.

Para entrar se escribe solo el nombre, sin dominio:

| Para ver | Usuario | Clave |
|---|---|---|
| El club | `clubsirio` | `admin2026` |
| Jugadores | `joaquin`, `camila`, `rodrigo`, … | `squash2026` |

En Club Sirio: camila, rodrigo, joaquin, sebastian, fernanda, valentina, jorge. En Santiago
Squash: cristobal, matias, felipe, tomas, pablo.

Para borrarlas con sus partidos y desafíos:

```sql
delete from auth.users where email like '%@socios.squashmatch.internal';
```

Y para dejar la base presentable después de trabajar en ella,
[`supabase/limpiar-pruebas.sql`](supabase/limpiar-pruebas.sql) borra lo que dejan las
verificaciones —desafíos, publicaciones, avisos y marcas con textos de prueba, reservas
canceladas de los últimos días— sin tocar jugadores, partidos, ratings ni cobros reales. La
app no permite eliminar filas, solo cancelarlas, así que este aseo va por SQL a propósito.

## Decisiones que ya se tomaron

**La escalerilla se retiró.** Existió hasta julio de 2026: un ranking interno por club donde
cada uno desafiaba hasta tres puestos arriba y el ganador se quedaba con su lugar. Se sacó
porque el ranking por puntos ya cumple esa función y hacerlo dos veces confundía —un mismo
partido movía dos marcadores con reglas distintas. Si se retoma, lo que había que resolver y
ya estaba resuelto: membresía explícita e independiente del club del perfil, cierre del hueco
al salir alguien (lo que obliga a que la restricción de puesto único sea `deferrable`), y
revalidación del rango al aceptar y no solo al enviar. Está en el historial de git.

**El acceso con Google se eliminó.** Con las cuentas creadas por el club no tiene sentido, y
se fue con él todo el trámite de Google Cloud.

**Las notificaciones push quedaron descartadas por ahora.** En iPhone solo funcionan si el
jugador agrega la app a la pantalla de inicio, y eso no lo va a hacer casi nadie. Una app en
las tiendas resolvería la adopción, pero es un problema que todavía no tenemos: primero hay
que ver si los socios usan lo que hay. Mientras tanto, WhatsApp es el canal que en Chile la
gente sí abre.

## Limitaciones actuales

1. **La app no se conecta con el sistema de reservas que el club ya use.** Ningún club de
   squash en Chile expone una API pública. La salida que ofrece la app es la contraria: que el
   club cargue acá también las canchas de quienes no la usan, y este pase a ser su calendario.
   Mientras haya dos calendarios en paralelo, la ocupación no será real y la cobranza seguirá
   partida.
2. **El WhatsApp necesita WhatsApp Web vinculado** en el computador del club: el enlace abre
   `web.whatsapp.com` y si no está vinculado muestra el QR. Se escanea una vez y queda. Desde
   el teléfono abre la app directo.
3. **El administrador de la app no puede navegar como otro usuario.** Las reglas de seguridad
   amarran los datos a quien inició sesión. El panel de administración es de solo lectura y el
   rol se asigna a mano en la base (`profiles.role = 'admin'`).
4. **Las noticias son estáticas.** Los resultados publicados son reales (Mundial PSA 2026,
   Giza), pero están escritos dentro del archivo.
5. **El plan gratis de Supabase no hace copias de seguridad.** Empiezan en el plan Pro.
   Mientras tanto el respaldo de la cobranza es la descarga del estado de cuenta, que depende
   de que alguien se acuerde. Si el club empieza a cobrar de verdad con esto, conviene pagar
   el plan o programar un respaldo automático.
6. **El plan gratis pausa los proyectos** tras una semana sin actividad. Si la app queda sin
   uso, hay que reactivarla desde el panel antes de una demostración.
7. **`index.html` va en 6.350 líneas**, y el esquema en 2.100. Sigue siendo manejable, pero antes de la próxima
   función grande conviene partirlo en archivos y sumar pruebas automáticas: hoy todo se
   verifica a mano contra la base.

Las comunas asignadas a cada club son de ejemplo.
