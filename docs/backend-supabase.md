# Pasar SquashMatch a Supabase + Google

Guía de la migración: qué haces tú, qué hago yo y en qué orden. Los pasos 1 a 6
son tuyos porque implican crear cuentas y manejar credenciales.

---

## Lo que cambia

Hoy cada persona que abre la app tiene su propia copia de los datos en su
navegador. Con Supabase pasan a vivir en una base de datos compartida: dos
jugadores en celulares distintos se ven, se desafían y la reserva bloquea la
cancha para ambos. Además el acceso con Google pasa a ser real.

Lo que **no** cambia: la interfaz, la lógica de escalerilla, las estadísticas y
el flujo de desafíos. Se reescribe la capa de datos, no la app.

---

## 1. Crear el proyecto en Supabase

1. Entra a [supabase.com](https://supabase.com) y crea una cuenta (sirve la de GitHub).
2. **New project**. Nombre: `squashmatch`. Región: **South America (São Paulo)**, la
   más cercana a Chile.
3. Guarda la contraseña de la base de datos que te muestra. No la necesito yo, pero
   la vas a necesitar tú si algún día entras por fuera.
4. El proyecto tarda un par de minutos en quedar listo.

## 2. Crear las tablas

1. En el panel del proyecto: **SQL Editor** → **New query**.
2. Abre [`supabase/schema.sql`](../supabase/schema.sql), copia **todo** el contenido
   y pégalo ahí.
3. **Run**. Debería terminar sin errores.
4. Verifica en **Table Editor** que aparecieron: `clubs`, `profiles`, `challenges`
   y `bookings`, y que `clubs` ya tiene Club Sirio y Santiago Squash.

## 3. Publicar la app en GitHub Pages

El acceso con Google necesita una dirección web real: no funciona abriendo el
archivo con doble clic.

1. En el repositorio: **Settings** → **Pages**.
2. En *Source* elige **Deploy from a branch**, rama `main`, carpeta `/ (root)`.
3. **Save**. En un par de minutos queda en:
   `https://ninjasasin.github.io/SquashMatch/`

Anota esa dirección: la usas en los pasos 4 y 5.

## 4. Crear el cliente de Google

1. Entra a [console.cloud.google.com](https://console.cloud.google.com) con tu cuenta.
2. Crea un proyecto nuevo, por ejemplo `SquashMatch`.
3. Ve a **APIs y servicios** → **Pantalla de consentimiento de OAuth**:
   - Tipo de usuario: **Externo**.
   - Nombre de la app: `SquashMatch`. Correo de asistencia: el tuyo.
   - Guarda. Mientras esté en modo *Prueba*, solo entran los correos que agregues
     como usuarios de prueba; para abrirlo a cualquiera hay que publicarlo.
4. **Credenciales** → **Crear credenciales** → **ID de cliente de OAuth**:
   - Tipo: **Aplicación web**.
   - *Orígenes de JavaScript autorizados*: `https://ninjasasin.github.io`
   - *URI de redireccionamiento autorizados*:
     `https://TU-PROYECTO.supabase.co/auth/v1/callback`
     (la parte `TU-PROYECTO` la ves en Supabase → Settings → API → Project URL)
5. Al crearlo te muestra el **ID de cliente** y el **secreto de cliente**. Déjalos a
   mano para el paso 5.

## 5. Conectar Google con Supabase

1. En Supabase: **Authentication** → **Sign In / Providers** → **Google**.
2. Actívalo y pega el **ID de cliente** y el **secreto** del paso anterior.
3. **Authentication** → **URL Configuration**:
   - *Site URL*: `https://ninjasasin.github.io/SquashMatch/`
   - En *Redirect URLs* agrega también `http://localhost:8123/index.html` para poder
     probar en tu computador.
4. Guarda.

## 6. Pasarme dos datos

De **Settings** → **API** del proyecto:

- **Project URL** — algo como `https://abcdefgh.supabase.co`
- **anon public key** — una clave larga que empieza con `eyJ...`

Ambos son públicos por diseño: van escritos dentro de la app y cualquiera que abra
la página los puede leer. Lo que protege los datos son las reglas de seguridad que
ya vienen en el esquema, no el secreto de esa clave.

**No me mandes** el *service_role key* ni el secreto de Google ni la contraseña de la
base de datos. Esos sí son secretos y no los necesito.

---

## 7. Lo que hago yo con eso

1. Reemplazo la capa de datos: hoy todo pasa por `localStorage`, pasará por Supabase.
2. Cambio el acceso simulado por el de Google real, más la opción de entrar con
   correo (enlace mágico), que no necesita contraseña.
3. Onboarding: cuando alguien entra por primera vez con Google, ya llega con nombre y
   correo; solo le pedimos categoría y club.
4. El rol de administrador pasa a ser una columna en la base de datos en vez de una
   clave escrita en el código.
5. Notificaciones en vivo: los desafíos aparecen sin recargar la página.

---

## Sobre la seguridad del esquema

Vale la pena que sepas qué quedó protegido, porque no es lo mismo que hoy:

- **Nadie puede reservar saltándose las reglas.** Aceptar un desafío no es una
  escritura directa: pasa por una función en el servidor que revalida el horario, que
  ninguno de los dos tenga otro partido, el rango de la escalerilla y la
  disponibilidad de la cancha. Además hay un índice único que impide dos reservas
  confirmadas en la misma cancha, fecha y hora, aunque dos personas acepten en el
  mismo segundo.
- **Cada quien edita solo su perfil**, y ve solo los desafíos en los que participa.
- **El teléfono y el correo no son públicos.** El directorio no los entrega; se
  obtienen con una función que los devuelve únicamente a quien tenga una reserva
  confirmada con esa persona.
- **El resultado de un partido solo lo pueden registrar sus dos jugadores**, y el
  movimiento de la escalerilla lo aplica el servidor, no el navegador.

Lo que **no** está resuelto y conviene decidir más adelante: que alguien registre un
resultado falso. Hoy basta con que uno de los dos lo cargue. Lo natural es pedir
confirmación del rival antes de mover la escalerilla.
