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

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const servicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth) return json({ error: 'Falta la sesion.' }, 401);

  let playerId = '';
  try {
    playerId = (await req.json())?.player_id ?? '';
  } catch {
    return json({ error: 'Cuerpo invalido.' }, 400);
  }
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

  if (errSocio || !socio) return json({ error: 'Ese socio no existe.' }, 404);
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
