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
    escalerilla no se mueve. El movimiento se aplica al registrar el resultado.
  - El partido se agenda y se reserva como cualquier otro, fijado al club de esa
    escalerilla, y queda marcado como válido por ella.
  - Si las posiciones cambian entre el envío y la respuesta y el desafío queda fuera de
    rango, caduca indicando el motivo.
  - El orden inicial es por categoría y luego por ranking nacional; de ahí en adelante lo
    define la cancha. Al registrarse o cambiarse de club, el jugador entra al último
    puesto de la escalerilla que corresponde.
- **Mis partidos** — próximos partidos con club y cancha, cancelación que libera el
  cupo, e historial con registro de resultado y marcador.
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
- `register_result()` acepta el resultado solo de los jugadores del partido y aplica
  el intercambio de posiciones de la escalerilla.
- `contact_of()` entrega correo y teléfono únicamente a quien tenga una reserva
  confirmada con esa persona; el directorio no los expone.

Las noticias del circuito son un arreglo de datos al inicio del script, con el texto
redactado en español y el enlace a la fuente. Las miniaturas son ilustraciones SVG
generadas en el propio archivo: no se usan fotos de prensa, por derechos de autor.

La app necesita estar publicada (Vercel) para funcionar: carga la librería de
Supabase y el acceso con Google exige un dominio autorizado.

## Limitaciones actuales

1. **La reserva no viaja a un sistema del club.** El motor de canchas es propio y evita
   dobles reservas dentro de la app, pero ningún club de squash en Chile expone hoy una
   API pública de reservas; integrarlo requiere un acuerdo con cada club.
2. **El resultado lo carga un solo jugador.** Hoy basta con que uno de los dos lo
   registre para que la escalerilla se mueva. Con gente compitiendo en serio, el rival
   debería confirmarlo.
3. **El administrador no puede navegar como otro usuario.** Las reglas de seguridad
   amarran los datos a quien inició sesión, y suplantar exigiría la clave secreta del
   proyecto, que nunca puede estar en una página web. El panel de administración es de
   solo lectura y el rol se asigna a mano en la base (`profiles.role = 'admin'`).
4. **Las noticias son estáticas.** Los resultados publicados son reales (Mundial PSA
   2026, Giza), pero están escritos dentro del archivo: no hay una fuente que los
   actualice sola.
5. **El plan gratis de Supabase pausa los proyectos** tras una semana sin actividad. Si
   la app queda sin uso, hay que reactivarla desde el panel antes de una demostración.

Las comunas asignadas a cada club son de ejemplo. Los jugadores ya no lo son: son
las cuentas que se registran de verdad.
