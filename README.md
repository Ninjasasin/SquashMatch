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
  categoría o de categorías afines, con el ranking más cercano al suyo.
- **Directorio de jugadores** — búsqueda por nombre o club, filtros por categoría
  (Primera a Cuarta, Damas A/B, Juvenil Sub-19, Máster +40/+50) y por club, con orden
  por ranking nacional, nombre o partidos ganados.
- **Desafíos** — eliges club, fecha y hora; la app te dice en vivo cuántas canchas
  quedan libres en ese bloque y bloquea el envío si el horario no sirve.
- **Reserva inmediata al aceptar** — se asigna la primera cancha libre del club y la
  reserva queda confirmada. Si el bloque se ocupó mientras tanto, el desafío queda
  caducado con el motivo, y los demás desafíos pendientes de esos dos jugadores en el
  mismo bloque se anulan solos.
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
- **Ranking nacional** por categoría y **grilla de canchas** por club y día, que
  muestra los cupos libres y quién juega en cada cancha (los bloques ya pasados se
  ocultan).
- **Registro de jugadores** y selector "Entrar como" para simular a cualquier jugador
  y ver los dos lados del desafío.

## Cómo está hecho

Un solo archivo `index.html` con todo el HTML, CSS y JavaScript en línea. Sin
dependencias, sin CDN, sin build. La lógica de reservas vive en un IIFE al final del
archivo:

- `checkSlot()` valida un bloque para dos jugadores (horario pasado, jugador con otro
  partido a esa hora, canchas agotadas).
- `freeCourt()` / `bookingsAt()` resuelven la disponibilidad real por club, fecha y hora.
- `acceptRequest()` es la transacción: revalida y crea la reserva con cancha asignada.

Los datos se guardan en `localStorage` del navegador.

## Limitaciones actuales

1. **La reserva no viaja a un sistema del club.** El motor de canchas es propio y evita
   dobles reservas dentro de la app, pero ningún club de squash en Chile expone hoy una
   API pública de reservas; integrarlo requiere un acuerdo con cada club. La lógica está
   aislada en `checkSlot()` / `freeCourt()` para enchufarla cuando exista.
2. **Los datos son por navegador.** Sirve como demo y para mostrar la idea a clubes,
   pero para que dos jugadores en celulares distintos se vean se necesita un backend
   (usuarios, autenticación, notificaciones).

Los jugadores y clubes incluidos son datos de ejemplo.
