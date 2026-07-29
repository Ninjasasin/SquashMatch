// =============================================================================
// SquashMatch — resetear la clave de un socio
// =============================================================================
// Cambiar la contraseña de OTRA persona necesita la llave de servicio de
// Supabase, y esa llave no puede vivir en el código de la app: cualquiera que
// abra el navegador podría leerla y con ella crear, borrar o suplantar usuarios.
//
// Por eso esto corre en el servidor. La llave la inyecta Supabase como variable
// de entorno y nunca sale de acá.
//
// Existe porque el socio no tiene correo real: no hay a dónde mandarle un enlace
// de recuperación. Si pierde la clave, vuelve a recepción y el club se la
// regenera, que es el mismo camino por el que la recibió la primera vez.
// =============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/* Clave legible: alguien la va a dictar en un mostrador y otro la va a escribir
   en un teléfono, así que sin caracteres que se confundan (ni O ni 0, ni l ni 1). */
function claveInicial(): string {
  const abc = 'ABCDEFGHJKMNPQRSTUVWXYZ';
  const num = '23456789';
  const azar = (n: number) => crypto.getRandomValues(new Uint32Array(1))[0] % n;
  let out = '';
  for (let i = 0; i < 4; i++) out += abc[azar(abc.length)];
  out += '-';
  for (let i = 0; i < 4; i++) out += num[azar(num.length)];
  return out;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Solo POST.' }, 405);

  // Los proyectos con el sistema de llaves nuevo (sb_publishable_ / sb_secret_)
  // no siempre traen los nombres viejos, asi que se prueban los dos. Si falta,
  // conviene que lo diga en vez de fallar despues como si el socio no existiera.
  const env = (...nombres: string[]) => {
    for (const n of nombres) {
      const v = Deno.env.get(n);
      if (v) return v;
    }
    return '';
  };

  const url = env('SUPABASE_URL');
  const anon = env('SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY');
  const servicio = env('SM_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY');

  if (!url || !anon || !servicio) {
    return json({
      error: 'Faltan variables de entorno en la funcion.',
      detalle: { url: !!url, anon: !!anon, servicio: !!servicio },
    }, 500);
  }

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth) return json({ error: 'Falta la sesion.' }, 401);

  let cuerpo: Record<string, unknown> = {};
  try {
    cuerpo = (await req.json()) ?? {};
  } catch {
    return json({ error: 'Cuerpo invalido.' }, 400);
  }

  /* Modo diagnostico: dice QUE variables encontro y si el cliente de servicio
     puede leer, sin devolver ningun valor de llave. Nombres y si/no, nada mas.
     Existe porque "permission denied" no dice con que rol se esta consultando, y
     adivinarlo cuesta mas que preguntarlo. */
  if (cuerpo.diagnostico === true) {
    const nombres = Object.keys(Deno.env.toObject())
      .filter((k) => k.startsWith('SUPABASE_') || k.startsWith('SM_'))
      .sort();
    const prueba = createClient(url, servicio, { auth: { persistSession: false } });
    const perfiles = await prueba.from('profiles').select('id').limit(1);
    const clubes = await prueba.from('clubs').select('id').limit(1);
    return json({
      variablesEncontradas: nombres,
      servicioEmpiezaCon: servicio.slice(0, 12),
      leerProfiles: perfiles.error ? perfiles.error.message : 'ok',
      leerClubs: clubes.error ? clubes.error.message : 'ok',
    });
  }

  const playerId = String(cuerpo.player_id ?? '');
  if (!playerId) return json({ error: 'Falta el jugador.' }, 400);

  // Quién llama. Va con el token del usuario, así que no se puede falsear.
  const comoUsuario = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
  });
  const { data: quien, error: errQuien } = await comoUsuario.auth.getUser();
  if (errQuien || !quien?.user) return json({ error: 'Sesion invalida.' }, 401);

  // La llave de servicio se usa solo para leer y escribir, nunca para decidir
  // si el que llama tiene permiso: eso se resuelve con su propio token.
  const admin = createClient(url, servicio, { auth: { persistSession: false } });

  const { data: socio, error: errSocio } = await admin
    .from('profiles')
    .select('id, name, member_id, club_id, staff, role')
    .eq('id', playerId)
    .single();

  if (errSocio) {
    return json({ error: 'No pude leer el socio: ' + errSocio.message }, 500);
  }
  if (!socio) return json({ error: 'Ese socio no existe.' }, 404);
  if (!socio.member_id) return json({ error: 'Esa cuenta no es de un socio.' }, 400);
  if (!socio.club_id) return json({ error: 'Ese socio no tiene club.' }, 400);

  // Una cuenta de club o de administración no se resetea desde acá: si no, el
  // club podría tomarse la cuenta de otro administrador.
  if (socio.staff || socio.role === 'admin') {
    return json({ error: 'Esa cuenta no se puede resetear desde el panel del club.' }, 403);
  }

  // ¿El que llama administra el club de ese socio? Lo responde la base con
  // auth.uid(), no un dato que venga en la petición.
  const { data: esAdmin, error: errAdmin } = await comoUsuario
    .rpc('is_club_admin', { p_club: socio.club_id });

  if (errAdmin) return json({ error: errAdmin.message }, 500);
  if (!esAdmin) {
    return json({ error: 'Solo el administrador de ese club puede resetear la clave.' }, 403);
  }

  const clave = claveInicial();
  const { error: errClave } = await admin.auth.admin.updateUserById(playerId, {
    password: clave,
  });
  if (errClave) return json({ error: errClave.message }, 500);

  // Vuelve a quedar obligado a cambiarla: el club acaba de verla.
  const { error: errFlag } = await admin
    .from('profiles')
    .update({ must_change_password: true })
    .eq('id', playerId);
  if (errFlag) return json({ error: errFlag.message }, 500);

  return json({ member_id: socio.member_id, name: socio.name, clave });
});
