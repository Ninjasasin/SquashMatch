# SquashMatch

Plataforma para jugadores de squash: busca rivales por categoría y ranking nacional,
mándales un desafío para un día, hora y club determinados, y al aceptarlo se genera
la reserva de cancha en el acto.

**Demo:** abre `index.html` en cualquier navegador. No hay nada que instalar ni compilar.

## Qué hace

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
- **Registro de jugadores** y selector "Entrar como" para simular a cualquier jugador
  y ver los dos lados del desafío.

## Cómo está hecho

Un solo archivo `index.html` con todo el HTML, CSS y JavaScript en línea. Sin
dependencias, sin CDN, sin build. La lógica de reservas vive en un IIFE al final del
archivo:

- `checkSlot()` valida un bloque para dos jugadores (horario pasado, jugador con otro
  partido a esa hora, cancha pedida ocupada, canchas agotadas).
- `courtFree()` / `freeCourt()` / `bookingsAt()` resuelven la disponibilidad real por club,
  fecha, hora y cancha.
- `acceptRequest()` es la transacción: revalida y crea la reserva con la cancha asignada.
- `syncLadders()` / `ladderTargets()` / `canChallengeLadder()` / `applyLadderResult()`
  sostienen la escalerilla: mantienen cada lista al día con los socios del club, resuelven
  el rango desafiable y aplican el intercambio de posiciones al cargar un resultado.

Los datos se guardan en `localStorage` del navegador, bajo una clave versionada
(`squashmatch-vN`). Al cambiar la semilla de datos se sube esa versión para que los
navegadores con una partida guardada carguen los datos nuevos.

Las noticias del circuito son un arreglo de datos al inicio del script, con el texto
redactado en español y el enlace a la fuente. Las miniaturas son ilustraciones SVG
generadas en el propio archivo: no se usan fotos de prensa, tanto por mantener el archivo
autocontenido como por los derechos de autor sobre esas imágenes.

## Limitaciones actuales

1. **La reserva no viaja a un sistema del club.** El motor de canchas es propio y evita
   dobles reservas dentro de la app, pero ningún club de squash en Chile expone hoy una
   API pública de reservas; integrarlo requiere un acuerdo con cada club. La lógica está
   aislada en `checkSlot()` / `freeCourt()` para enchufarla cuando exista.
2. **Los datos son por navegador.** Sirve como demo y para mostrar la idea a clubes,
   pero para que dos jugadores en celulares distintos se vean se necesita un backend
   (usuarios, autenticación, notificaciones).

3. **Las noticias son estáticas.** Los resultados publicados son reales (Mundial PSA 2026,
   Giza), pero están escritos dentro del archivo: no hay una fuente que los actualice sola.

Los jugadores son datos de ejemplo, igual que las comunas asignadas a cada club.
