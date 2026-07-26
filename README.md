# SquashMatch

Plataforma para jugadores de squash: busca rivales por categoría y rating, mándales un
desafío para un día, hora y club determinados, y al aceptarlo se genera la reserva de
cancha en el acto.

**App publicada:** [squash-match.vercel.app](https://squash-match.vercel.app/)

Las cuentas y los partidos viven en Supabase, así que los jugadores se ven entre sí
desde cualquier dispositivo. La app necesita estar publicada para funcionar: abrir el
archivo con doble clic ya no sirve.

## Qué hace

- **Pantalla de entrada** — la app parte pidiendo identificarse, con Supabase Auth:
  - *Continuar con Google*: acceso real por OAuth. Requiere un cliente OAuth de Google
    Cloud conectado al proyecto y el dominio autorizado.
  - *Entrar con correo y contraseña* y *Crear una cuenta*: la contraseña se cifra y se
    valida en el servidor; nunca se guarda en el navegador.
  - Al entrar por primera vez, la cuenta llega con nombre y correo pero sin categoría ni
    club: la app pide esos dos datos antes de dejar pasar, y con eso el jugador entra al
    último puesto de la escalerilla de su club.
  - La sesión sobrevive a recargas y se cierra desde el botón *Salir*.
- **Administración del club** — un rol aparte del administrador de la app, amarrado a un
  club y no a la persona: alguien puede administrar un club y jugar en otro. Su trabajo es
  la cobranza, y reemplaza el control manual que hoy lleva el club mientras no haya
  integración con un medio de pago.
  - **La cancha se cobra por jugador.** Vale $15.000 y al confirmarse una reserva se
    generan dos cobros de $7.500, uno para cada uno, que es como se paga en la práctica.
    Si la reserva se cancela, los cobros se anulan: lo que no se jugó no se cobra.
  - **El club también reserva para gente sin cuenta**, con una nota de quiénes jugaron.
    Esas reservas llevan un cobro único por la cancha completa, no aparecen en el ranking
    ni en las estadísticas, y para el resto de los jugadores figuran solo como "reservada
    por el club". Es lo que permite que toda la cobranza quede en un lugar y que los datos
    de ocupación sean reales.
  - **Agenda del día** con las canchas ocupadas y libres hora por hora, incluidos los días
    pasados, para saber quién jugó y quién quedó debiendo. Desde cada bloque libre se
    reserva; desde cada reserva se anota, se cobra o se cancela.
  - **Por cobrar** ordenado por días de atraso, y **Pagados** con la fecha en que se marcó
    cada uno y la opción de deshacer.
  - **Descarga del estado de cuenta** en planilla, con todos los movimientos y el total por
    cobrar a esa fecha. Es el respaldo del club: el plan gratis de Supabase **no hace
    copias de seguridad** —empiezan en el plan pagado— así que la cobranza no puede vivir
    en un solo lugar. El archivo se genera en el navegador y lleva la fecha en el nombre.
  - La cuenta del club no juega: no aparece en el directorio, la escalerilla ni el ranking,
    y solo ve las secciones que le sirven. *Canchas abiertas* la conserva como consulta,
    para ver quién está buscando rival, pero sin publicar ni sumarse.
- **Panel de administración de la app** — de solo lectura, visible para las cuentas con
  `role = 'admin'`: totales de cuentas, desafíos pendientes, reservas vigentes y partidos
  jugados, más el listado de jugadores con su club, puesto y récord.
- **Inicio** — pantalla de entrada con el resumen del jugador: sus partidos dentro de
  los próximos 7 días, un panel de notificaciones derivadas del estado real de la app
  (desafíos recibidos con aceptar/rechazar en el mismo lugar, desafíos propios aceptados
  o rechazados, recordatorios de partidos dentro de 48 horas y resultados por registrar),
  sus últimos 3 partidos con marcador, accesos directos para desafiar y un enlace a las
  estadísticas completas. El bloque de desafío rápido sugiere tres rivales de su misma
  categoría o de categorías afines, con el rating más cercano al suyo. Al final hay una
  sección de noticias del circuito PSA: al hacer clic en la miniatura o el titular se abre
  la nota breve en español, con enlace a la fuente original.
- **Directorio de jugadores** — búsqueda por nombre o club, filtros por categoría
  (Primera a Cuarta, Damas A/B, Juvenil Sub-19, Máster +40/+50) y por club, con orden
  por rating, nombre o partidos ganados. Los filtros se aplican al apretar **Aplicar**,
  no mientras se escribe, así se pueden combinar varios antes de buscar; los que se dejan
  vacíos no filtran, y una línea indica qué está aplicado.
- **Canchas abiertas** — para cuando tienes la hora y no el rival, que es el desorden
  que hoy se resuelve a los gritos en el grupo de WhatsApp del club. Publicas club, día,
  hora y, si quieres, cancha y la categoría de rival que buscas; la publicación queda
  visible y filtrable para todos. Otro jugador se suma con *Jugar*, la publicación sale
  de la lista mientras esperas, y tú confirmas o rechazas. Si rechazas, vuelve a quedar
  visible para cualquier otro; también puedes darla de baja cuando quieras. Al confirmar
  se crea la reserva.
  - **Publicar no toma la cancha**: se reserva recién al confirmar, así que la cancha se
    la lleva la primera pareja que confirma, venga de un desafío o de una publicación.
  - **No corren por la escalerilla**, para poder jugar contra alguien de tu rango sin
    arriesgar el puesto. La escalerilla se desafía solo desde su propia sección.
  - La categoría es una preferencia que se muestra y sirve para filtrar, no un muro:
    cualquiera se puede sumar.
- **Desafíos con elección de cancha** — eliges club, fecha, hora y cancha. El selector
  muestra el estado real de cada cancha en ese bloque (disponible u ocupada) y deja pedir
  una en particular, porque los jugadores suelen tener preferencia; también existe la
  opción "cualquiera disponible". El envío se bloquea si el horario no sirve.
- **Reserva inmediata al aceptar** — se reserva la cancha pedida, o la primera libre si no
  se pidió ninguna. Si esa cancha se ocupó mientras tanto, el desafío queda caducado
  indicando el motivo y si la otra cancha sigue libre; además, los demás desafíos
  pendientes de esos dos jugadores en el mismo bloque se anulan solos.
- **Clubes y canchas** — dos clubes (Club Sirio y Santiago Squash) con dos canchas cada
  uno, Cancha 1 y Cancha 2. La grilla de canchas muestra el estado de cada una hora por
  hora, con quién juega en la que está ocupada, y oculta los bloques ya pasados.
- **Escalerilla** — ranking interno de cada club, con todos sus jugadores del 1 al N:
  - Cada jugador puede desafiar hasta **3 puestos hacia arriba** y ser desafiado por los
    3 de abajo. El botón *Desafiar* solo aparece en esos tres rivales; el resto queda sin
    acción, así no se puede desafiar fuera de rango.
  - Si gana el desafiante, **intercambian posiciones**; si gana el defensor, la
    escalerilla no se mueve. El movimiento se aplica cuando el rival confirma el
    resultado, no cuando se carga.
  - El partido se agenda y se reserva como cualquier otro, fijado al club de esa
    escalerilla, y queda marcado como válido por ella.
  - Si las posiciones cambian entre el envío y la respuesta y el desafío queda fuera de
    rango, caduca indicando el motivo.
  - **La inscripción es explícita y no depende del club del perfil**: hay botones para
    unirse y para salir, se entra al último puesto, y un jugador puede estar en varias
    escalerillas a la vez. Al salir, los de abajo suben un lugar.
- **Mis partidos** — próximos partidos con club y cancha, cancelación que libera el
  cupo, e historial con el marcador.
- **Resultados en dos pasos** — uno de los dos jugadores carga quién ganó y el marcador
  **en sets** (3-0, 3-1, 3-2, o 2-0 y 2-1 al mejor de 3; no se piden los parciales de
  cada game, que nadie recuerda). El partido queda *por confirmar* y el rival recibe el
  aviso con dos botones: confirmar o rechazar. Quien cargó el resultado no puede
  confirmarlo, y hasta que el otro lo acepte no cuenta para las estadísticas ni mueve la
  escalerilla. Si lo rechazan, vuelve a quedar disponible para cargarlo de nuevo. El
  marcador siempre se muestra desde quien mira: una derrota se ve 1-3, no 3-1.
- **Mi perfil** — panel con el resumen del jugador, sus estadísticas y la edición de
  sus datos:
  - *Panel*: partidos agendados, desafíos por responder, partidos jugados y efectividad,
    más el próximo partido y los desafíos que esperan respuesta.
  - *Estadísticas*: efectividad, racha actual, últimos cinco resultados, partidos por mes
    (gráfico), rivales más frecuentes, clubes donde más juega, rendimiento contra rivales
    mejor rankeados y actividad de desafíos enviados/recibidos.
  - *Mis datos*: nombre, categoría, club, mano hábil, año desde que juega,
    contacto (correo, teléfono, comuna), días y **franjas horarias** en que puede jugar
    —se puede marcar más de una—, y una nota
    para sus rivales. La disponibilidad aparece en su tarjeta del directorio y el
    contacto se muestra al rival en los partidos ya reservados, para coordinar.
- **Rating de los jugadores** — un número que refleja el nivel y se mueve solo con los
  resultados confirmados, al estilo del Elo del ajedrez y de chess.com. Reemplaza al
  ranking nacional autodeclarado, que cualquiera podía inflar.
  - Cada jugador arranca con el rating de su categoría (Primera 1600, Segunda 1450, y así)
    en vez de partir todos iguales.
  - Ganarle a alguien muy superior suma mucho; ganarle a alguien muy por debajo, casi
    nada. A 800 puntos de diferencia el intercambio es cero: en la práctica, un amistoso.
  - El marcador pesa suave (3-0 vale 1,15; 3-1 vale 1,0; 3-2 vale 0,85), porque en squash
    un 3-2 puede ser un partidazo.
  - El intercambio es **de suma cero**: lo que uno gana, el otro lo pierde, así que el
    promedio del circuito nunca se infla.
  - Jugar más de tres veces contra el mismo rival en 30 días vale la mitad, que es la
    puerta natural para inflar el rating entre conocidos.
  - La pestaña **Ranking** ordena por rating y muestra cuánto se movió cada uno en su
    último partido. La explicación completa, con tablas y ejemplos, está en
    [`docs/rating-squashmatch.docx`](docs/rating-squashmatch.docx).
- **Panel de administración** de solo lectura para las cuentas con `role = 'admin'`:
  totales de cuentas, desafíos y reservas, y el listado de jugadores registrados.

## Cómo está hecho

La interfaz es un solo archivo `index.html` con el HTML, el CSS y el JavaScript en
línea. Los datos viven en **Supabase**: base de datos PostgreSQL, autenticación y
actualizaciones en vivo. El esquema completo está en
[`supabase/schema.sql`](supabase/schema.sql) y la guía de montaje en
[`docs/backend-supabase.md`](docs/backend-supabase.md).

Lo que corre en el navegador:

- `fetchAll()` lee clubes, perfiles, desafíos y reservas al iniciar sesión, y se
  vuelve a leer después de cada acción.
- `checkSlot()` / `courtFree()` validan la disponibilidad para la interfaz: avisan
  temprano y evitan viajes inútiles. La decisión real la toma el servidor.
- `ladderTargets()` / `canChallengeLadder()` resuelven a quién se puede desafiar;
  las posiciones vienen de la columna `ladder_pos`.

Lo que corre en el servidor, porque es donde se puede garantizar:

- `accept_challenge()` revalida horario, disponibilidad de ambos jugadores, rango de
  escalerilla y cancha, y crea la reserva en una sola transacción. Un índice único
  sobre club, fecha, hora y cancha impide la doble reserva aunque dos personas
  acepten en el mismo segundo.
- `join_invite()` deja a un jugador postulando a una publicación, y `confirm_invite()`
  la cierra creando la reserva o la devuelve a la lista si el autor rechaza. Validan lo
  mismo que `accept_challenge()`: horario, que ninguno de los dos tenga otro partido y la
  disponibilidad de cancha.
- `apply_elo()` mueve el rating de ambos jugadores, y corre dentro de `confirm_result()`:
  el rating solo cambia con resultados confirmados por los dos, nunca desde el navegador.
  `recalc_ratings()` rehace todos los ratings desde cero en orden cronológico.
- `join_ladder()` / `leave_ladder()` inscriben o retiran al jugador de la escalerilla de un
  club; puede estar en varias a la vez.
- `report_result()` recibe el resultado de cualquiera de los dos jugadores y lo deja
  *por confirmar*; `confirm_result()` solo puede ejecutarla el rival, y es la que aplica
  el intercambio de posiciones de la escalerilla.
- `contact_of()` entrega correo y teléfono únicamente a quien tenga una reserva
  confirmada con esa persona; el directorio no los expone.
- `club_book()` / `set_club_note()` / `club_cancel()` dejan que el club reserve para
  jugadores sin cuenta, anote quiénes jugaron y libere la cancha. `mark_payment()` marca
  los cobros. Todas comprueban que quien llama administre ese club: un jugador que
  intente marcarse un pago recibe un error del servidor, no de la interfaz.
- Los cobros los crea un disparador al confirmarse la reserva, y otro los anula al
  cancelarse. Un índice único garantiza que una reserva del club tenga un solo cobro:
  la restricción normal no sirve porque en SQL dos nulos no se consideran iguales.
- `club_notes()` entrega las notas de las reservas únicamente a quien administra el club.

### Al agregar una columna sensible, sácala del SELECT general

En Supabase el permiso por omisión es **todos los autenticados ven todas las columnas**,
así que proteger un dato es siempre una decisión deliberada. Ya pasó dos veces:

- El correo y el teléfono de los jugadores.
- La nota que el club escribe en cada reserva, que lleva nombres de invitados y detalles
  de cobro. Estuvo llegando al navegador de cualquier jugador: la interfaz no la mostraba,
  pero viajaba en la consulta y bastaba con pedirla directamente a la API para leerla.

El patrón para resolverlo es el mismo en los dos casos:

1. `revoke select on <tabla> from authenticated` y volver a otorgar **solo** las columnas
   públicas, una por una.
2. Entregar la columna reservada con una función `security definer` que compruebe quién
   pregunta (`contact_of()`, `club_notes()`).
3. En el cliente, pedir columnas explícitas en vez de `select('*')`, porque con permisos
   por columna el asterisco falla.

Ojo con el paso 1: **cada columna nueva hay que sumarla al `grant`**, o la app empieza a
recibir "permission denied" sin más explicación.

Y una advertencia general: esconder algo en la interfaz no protege nada. La clave pública
de la app está a la vista en el código de la página —así está diseñado— y cualquiera puede
consultar la base directamente con ella. Lo único que cuenta es lo que prohíbe el
servidor.

Las noticias del circuito son un arreglo de datos al inicio del script, con el texto
redactado en español y el enlace a la fuente. Las miniaturas son ilustraciones SVG
generadas en el propio archivo: no se usan fotos de prensa, por derechos de autor.

Sobre el rendimiento, tres decisiones que conviene conocer antes de tocar el código:

- Los datos se releen completos después de cada acción, en vez de actualizar solo lo que
  cambió. Con este volumen es más simple y más seguro; con cientos de jugadores habría que
  refinarlo.
- Los avisos en vivo llegan de a varios por acción, así que se agrupan y disparan una sola
  relectura.
- Las estadísticas de cada jugador y el último movimiento de rating se calculan una vez por
  carga de datos, no cada vez que se pide. Cada vista se dibuja al entrar en ella; los
  contadores de las pestañas se calculan aparte, porque deben estar al día aunque el
  jugador esté mirando otra sección.

Las cinco tablas están en la publicación `supabase_realtime`, así que los desafíos, las
reservas y los cambios de escalerilla llegan solos a las pantallas abiertas, sin recargar.

La app necesita estar publicada (Vercel) para funcionar: carga la librería de
Supabase y el acceso con Google exige un dominio autorizado.

## Datos de prueba

[`supabase/seed-demo.sql`](supabase/seed-demo.sql) crea 12 jugadores repartidos en los dos
clubes, con perfil, categoría y 18 partidos ya confirmados, para poder mostrar la
app con contenido. Se corre en el SQL Editor **después** de `schema.sql`.

Las cuentas quedan como `nombre@squash.cl` — camila, rodrigo, joaquin, sebastian,
fernanda, valentina y jorge en Club Sirio; cristobal, matias, felipe, tomas y pablo en
Santiago Squash — todas con la contraseña `squash2026`. Sirven para recorrer la app desde
el punto de vista de cualquiera de ellos.

La administración del Club Sirio entra con `clubsirio@squash.cl` y contraseña `admin2026`.

Para borrarlas, con sus partidos y desafíos:

```sql
delete from auth.users where email like '%@squash.cl';
```

## Limitaciones actuales

1. **La app no se conecta con el sistema de reservas que el club ya use.** Ningún club de
   squash en Chile expone una API pública, así que integrarlo requiere un acuerdo caso a
   caso. La salida que ofrece la app es la contraria: que el club cargue acá también las
   canchas de quienes no la usan, y este pase a ser su calendario. Mientras haya dos
   calendarios en paralelo, la ocupación que muestre el sistema no será real y la cobranza
   seguirá partida.
2. **El administrador no puede navegar como otro usuario.** Las reglas de seguridad
   amarran los datos a quien inició sesión, y suplantar exigiría la clave secreta del
   proyecto, que nunca puede estar en una página web. El panel de administración es de
   solo lectura y el rol se asigna a mano en la base (`profiles.role = 'admin'`).
3. **Las noticias son estáticas.** Los resultados publicados son reales (Mundial PSA
   2026, Giza), pero están escritos dentro del archivo: no hay una fuente que los
   actualice sola.
4. **El plan gratis de Supabase no hace copias de seguridad.** Los respaldos diarios
   empiezan en el plan Pro. Mientras tanto, el respaldo de la cobranza es la descarga del
   estado de cuenta, que depende de que alguien se acuerde de hacerla. Si el club empieza
   a usar esto para cobrar de verdad, conviene pagar el plan o programar un respaldo
   automático.
5. **El plan gratis de Supabase pausa los proyectos** tras una semana sin actividad. Si
   la app queda sin uso, hay que reactivarla desde el panel antes de una demostración.

Las comunas asignadas a cada club son de ejemplo. Los jugadores ya no lo son: son
las cuentas que se registran de verdad.
