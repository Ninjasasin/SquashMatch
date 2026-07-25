# SquashMatch

Plataforma para jugadores de squash: busca rivales por categoría y ranking nacional,
mándales un desafío para un día, hora y club determinados, y al aceptarlo se genera
la reserva de cancha en el acto.

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
- **Panel de administración** — de solo lectura, visible para las cuentas con
  `role = 'admin'`: totales de cuentas, desafíos pendientes, reservas vigentes y partidos
  jugados, más el listado de jugadores con su club, puesto y récord.
- **Inicio** — pantalla de entrada con el resumen del jugador: sus partidos dentro de
  los próximos 7 días, un panel de notificaciones derivadas del estado real de la app
  (desafíos recibidos con aceptar/rechazar en el mismo lugar, desafíos propios aceptados
  o rechazados, recordatorios de partidos dentro de 48 horas y resultados por registrar),
  sus últimos 3 partidos con marcador, accesos directos para desafiar y un enlace a las
  estadísticas completas. El bloque de desafío rápido sugiere tres rivales de su misma
  categoría o de categorías afines, con el ranking más cercano al suyo. Al final hay una
  sección de noticias del circuito PSA: al hacer clic en la miniatura o el titular se abre
  la nota breve en español, con enlace a la fuente original.
- **Directorio de jugadores** — búsqueda por nombre o club, filtros por categoría
  (Primera a Cuarta, Damas A/B, Juvenil Sub-19, Máster +40/+50) y por club, con orden
  por ranking nacional, nombre o partidos ganados.
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
  - El orden inicial es por categoría y luego por ranking nacional; de ahí en adelante lo
    define la cancha. Al registrarse o cambiarse de club, el jugador entra al último
    puesto de la escalerilla que corresponde.
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
  - *Mis datos*: nombre, categoría, ranking, club, mano hábil, año desde que juega,
    contacto (correo, teléfono, comuna), días y horario en que puede jugar, y una nota
    para sus rivales. La disponibilidad aparece en su tarjeta del directorio y el
    contacto se muestra al rival en los partidos ya reservados, para coordinar.
- **Ranking nacional** por categoría, con el récord de cada jugador.
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
- `report_result()` recibe el resultado de cualquiera de los dos jugadores y lo deja
  *por confirmar*; `confirm_result()` solo puede ejecutarla el rival, y es la que aplica
  el intercambio de posiciones de la escalerilla.
- `contact_of()` entrega correo y teléfono únicamente a quien tenga una reserva
  confirmada con esa persona; el directorio no los expone.

Las noticias del circuito son un arreglo de datos al inicio del script, con el texto
redactado en español y el enlace a la fuente. Las miniaturas son ilustraciones SVG
generadas en el propio archivo: no se usan fotos de prensa, por derechos de autor.

Las cuatro tablas están en la publicación `supabase_realtime`, así que los desafíos, las
reservas y los cambios de escalerilla llegan solos a las pantallas abiertas, sin recargar.

La app necesita estar publicada (Vercel) para funcionar: carga la librería de
Supabase y el acceso con Google exige un dominio autorizado.

## Datos de prueba

[`supabase/seed-demo.sql`](supabase/seed-demo.sql) crea 12 jugadores repartidos en los dos
clubes, con perfil, categoría, ranking y 18 partidos ya confirmados, para poder mostrar la
app con contenido. Se corre en el SQL Editor **después** de `schema.sql`.

Las cuentas quedan como `nombre@squash.cl` — camila, rodrigo, joaquin, sebastian,
fernanda, valentina y jorge en Club Sirio; cristobal, matias, felipe, tomas y pablo en
Santiago Squash — todas con la contraseña `squash2026`. Sirven para recorrer la app desde
el punto de vista de cualquiera de ellos.

Para borrarlas, con sus partidos y desafíos:

```sql
delete from auth.users where email like '%@squash.cl';
```

## Limitaciones actuales

1. **La reserva no viaja a un sistema del club.** El motor de canchas es propio y evita
   dobles reservas dentro de la app, pero ningún club de squash en Chile expone hoy una
   API pública de reservas; integrarlo requiere un acuerdo con cada club.
2. **El administrador no puede navegar como otro usuario.** Las reglas de seguridad
   amarran los datos a quien inició sesión, y suplantar exigiría la clave secreta del
   proyecto, que nunca puede estar en una página web. El panel de administración es de
   solo lectura y el rol se asigna a mano en la base (`profiles.role = 'admin'`).
3. **Las noticias son estáticas.** Los resultados publicados son reales (Mundial PSA
   2026, Giza), pero están escritos dentro del archivo: no hay una fuente que los
   actualice sola.
4. **El plan gratis de Supabase pausa los proyectos** tras una semana sin actividad. Si
   la app queda sin uso, hay que reactivarla desde el panel antes de una demostración.

Las comunas asignadas a cada club son de ejemplo. Los jugadores ya no lo son: son
las cuentas que se registran de verdad.
