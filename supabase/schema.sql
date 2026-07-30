-- =============================================================================
-- SquashMatch — esquema de base de datos
-- Ejecutar completo en Supabase: panel del proyecto → SQL Editor → New query.
-- Es idempotente: se puede volver a correr sin romper nada.
-- =============================================================================

-- =============================================================================
-- 1. CLUBES
-- =============================================================================
create table if not exists public.clubs (
  id     text primary key,
  name   text not null,
  comuna text not null,
  courts int  not null check (courts > 0)
);

-- La grilla de turnos es de cada club, no de la app: el Club Sirio corre de
-- 08:00 a 22:00 en turnos de 40 minutos, que son 22 turnos por cancha y 44
-- entre las dos. Antes la app asumía bloques de una hora, que no es como
-- trabaja ningún club de los que vimos.
--
-- goal_weekday y goal_weekend son la meta de turnos reservados al día que usan
-- los ejecutivos del club para su bono. Es del club completo, sin importar
-- quién esté cubriendo el turno, y el fin de semana es más baja.
alter table public.clubs
  add column if not exists opens        text not null default '08:00',
  add column if not exists last_slot    text not null default '22:00',
  add column if not exists slot_minutes int  not null default 40
    check (slot_minutes between 10 and 180),
  add column if not exists goal_weekday int  not null default 16 check (goal_weekday >= 0),
  add column if not exists goal_weekend int  not null default 8  check (goal_weekend >= 0);

-- Reglamento interno y datos de contacto. El club los edita desde su panel y
-- los jugadores los leen en la vista Canchas, plegados: es el momento en que
-- importan —están eligiendo hora— y así no estorban al que ya los conoce.
alter table public.clubs
  add column if not exists rules       text not null default '',
  add column if not exists cancel_rule text not null default '',
  add column if not exists phone       text not null default '',
  add column if not exists email       text not null default '',
  add column if not exists address     text not null default '';

-- El insert de abajo no toca estas columnas a propósito: si el club ajusta su
-- horario, su meta o su reglamento, volver a correr el esquema no se los pisa.
insert into public.clubs (id, name, comuna, courts) values
  ('c1', 'Club Sirio',      'Las Condes',  2),
  ('c2', 'Santiago Squash', 'Providencia', 2)
on conflict (id) do update
  set name = excluded.name, comuna = excluded.comuna, courts = excluded.courts;

-- =============================================================================
-- 2. PERFILES
-- Un perfil por usuario autenticado. Se crea solo al registrarse (trigger más
-- abajo) y el jugador completa categoría y club desde la app.
-- =============================================================================
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  name           text not null default '',
  email          text not null default '',
  category       text,
  national_rank  int check (national_rank between 1 and 999),
  club_id        text references public.clubs(id),
  hand           text default 'Diestro',
  -- contacto: protegido con permisos por columna (ver sección 7)
  phone          text default '',
  comuna         text default '',
  playing_since  text default '',
  available_days text[] default '{}',
  preferred_slot text default '',
  bio            text default '',
  role           text not null default 'player' check (role in ('player','admin')),
  created_at     timestamptz not null default now()
);

-- Cuentas de administración de club: no son jugadores y no aparecen en el
-- directorio ni en el ranking. Va acá y no más abajo porque los permisos por
-- columna de la sección 6 la nombran.
alter table public.profiles
  add column if not exists staff boolean not null default false;


-- =============================================================================
-- SOCIOS DEL CLUB
-- El servicio es para los socios, y las cuentas las crea el club: el jugador
-- pasa por recepción, le entregan su ID de socio y con eso entra. No hay
-- registro público.
--
-- Esto resuelve de una vez la adopción —el socio ya está adentro, no hay que
-- convencerlo de registrarse— y la calidad de los datos, porque los escribe el
-- club y no cada uno como quiere.
--
-- member_id es nombre.apellido, y es lo que el jugador escribe para entrar.
-- rut es la llave que impide duplicados: si un socio se va y vuelve al año, la
-- base no deja crearlo de nuevo y recupera su historial y su rating.
-- =============================================================================
alter table public.profiles
  add column if not exists member_id text,
  add column if not exists rut       text,
  add column if not exists must_change_password boolean not null default false,
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

-- Únicos, pero solo cuando hay valor: las cuentas de club no tienen ni ID de
-- socio ni RUT, y varios nulos no pueden chocar entre sí.
create unique index if not exists profiles_member_id_unique
  on public.profiles (member_id) where member_id is not null;

create unique index if not exists profiles_rut_unique
  on public.profiles (rut) where rut is not null;

create index if not exists profiles_club_idx on public.profiles (club_id);

-- El RUT se guarda normalizado —sin puntos ni guion, K en mayúscula— porque si
-- no, 12.345.678-5 y 123456785 son dos filas distintas y la llave única no
-- sirve para nada. Esta es la parte que hay que hacer bien o el candado no cierra.
create or replace function public.normalizar_rut(p_rut text)
returns text
language sql
immutable
as $$
  select nullif(upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g')), '');
$$;

-- Dígito verificador por módulo 11. Sin esto, un dedazo en recepción crea un
-- socio fantasma que después nadie puede unir con el real.
create or replace function public.rut_valido(p_rut text)
returns boolean
language plpgsql
immutable
as $$
declare
  limpio  text := public.normalizar_rut(p_rut);
  cuerpo  text;
  dv      text;
  suma    int := 0;
  factor  int := 2;
  i       int;
  resto   int;
  esperado text;
begin
  if limpio is null or length(limpio) < 2 then
    return false;
  end if;
  cuerpo := left(limpio, length(limpio) - 1);
  dv     := right(limpio, 1);
  if cuerpo !~ '^[0-9]+$' then
    return false;
  end if;

  for i in reverse length(cuerpo)..1 loop
    suma := suma + (substr(cuerpo, i, 1))::int * factor;
    factor := case when factor = 7 then 2 else factor + 1 end;
  end loop;

  resto := 11 - (suma % 11);
  esperado := case resto when 11 then '0' when 10 then 'K' else resto::text end;
  return dv = esperado;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_rut_chk') then
    alter table public.profiles add constraint profiles_rut_chk
      check (rut is null or public.rut_valido(rut));
  end if;
end $$;

-- =============================================================================
-- 3. DESAFÍOS
-- =============================================================================
create table if not exists public.challenges (
  id         uuid primary key default gen_random_uuid(),
  from_id    uuid not null references public.profiles(id) on delete cascade,
  to_id      uuid not null references public.profiles(id) on delete cascade,
  club_id    text not null references public.clubs(id),
  match_date date not null,
  match_time text not null,
  court      int  not null default 0,   -- 0 = cualquiera disponible
  message    text default '',
  status     text not null default 'pendiente'
             check (status in ('pendiente','contrapropuesta','aceptada',
                               'rechazada','cancelada','caducada')),
  note       text default '',
  booking_id uuid,
  created_at timestamptz not null default now(),
  constraint challenges_distinct_players check (from_id <> to_id)
);

-- El check de status venia escrito dentro del create table, y en una base que ya
-- existia ese create no corre: por eso agregar 'contrapropuesta' arriba no bastaba
-- y la base seguia rechazando el estado nuevo. Se reemplaza explicito.
alter table public.challenges drop constraint if exists challenges_status_check;
alter table public.challenges add constraint challenges_status_check
  check (status in ('pendiente','contrapropuesta','aceptada',
                    'rechazada','cancelada','caducada'));

-- Contrapropuesta: el desafiado no dice que no, dice "ese día no, pero el
-- jueves sí". match_date y match_time pasan a ser los del horario nuevo —así
-- accept_challenge no necesita saber nada de esto— y counter_of_* guarda el
-- horario original, solo para poder mostrar de dónde se venía.
alter table public.challenges
  add column if not exists counter_of_date date,
  add column if not exists counter_of_time text,
  add column if not exists counter_msg     text not null default '',
  add column if not exists counter_by      uuid references public.profiles(id) on delete set null;

create index if not exists challenges_to_idx   on public.challenges (to_id, status);
create index if not exists challenges_from_idx on public.challenges (from_id, status);

-- =============================================================================
-- 4. RESERVAS
-- =============================================================================
create table if not exists public.bookings (
  id               uuid primary key default gen_random_uuid(),
  challenge_id     uuid references public.challenges(id) on delete set null,
  club_id          text not null references public.clubs(id),
  court            int  not null check (court > 0),
  match_date       date not null,
  match_time       text not null,
  player_a         uuid not null references public.profiles(id) on delete cascade,
  player_b         uuid not null references public.profiles(id) on delete cascade,
  status           text not null default 'confirmada'
                   check (status in ('confirmada','cancelada')),
  winner_id        uuid references public.profiles(id) on delete set null,
  score            text default '',
  created_at       timestamptz not null default now()
);

-- Resultado: lo carga un jugador y lo confirma el otro. Se anota por sets, sin
-- parciales: despues del partido nadie recuerda los games, pero todos saben el 3-1.
alter table public.bookings
  add column if not exists reported_by    uuid references public.profiles(id) on delete set null,
  add column if not exists sets_winner    int,
  add column if not exists sets_loser     int,
  add column if not exists result_status  text not null default 'sin_resultado';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bookings_result_status_chk') then
    alter table public.bookings add constraint bookings_result_status_chk
      check (result_status in ('sin_resultado','por_confirmar','confirmado','rechazado'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bookings_sets_chk') then
    alter table public.bookings add constraint bookings_sets_chk
      check (
        (sets_winner is null and sets_loser is null)
        or (sets_winner = 3 and sets_loser between 0 and 2)
        or (sets_winner = 2 and sets_loser between 0 and 1)
      );
  end if;
end $$;

-- El club tambien reserva para gente que no usa la app: esas reservas no tienen
-- jugadores registrados, solo una nota con quien jugo, para poder cobrarles.
alter table public.bookings
  alter column player_a drop not null,
  alter column player_b drop not null;

alter table public.bookings
  add column if not exists club_note text not null default '',
  add column if not exists source    text not null default 'app';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bookings_source_chk') then
    alter table public.bookings add constraint bookings_source_chk
      check (source in ('app','club'));
  end if;
end $$;

-- Esta es la regla que impide la doble reserva. Aunque dos personas acepten un
-- desafío en el mismo instante, la base de datos deja pasar solo a una.
create unique index if not exists bookings_slot_unique
  on public.bookings (club_id, match_date, match_time, court)
  where status = 'confirmada';

create index if not exists bookings_players_idx on public.bookings (player_a, player_b, match_date);

-- =============================================================================
-- 5. PERFIL AUTOMÁTICO AL REGISTRARSE
-- Google entrega el nombre y el correo; el resto lo completa el jugador.
-- =============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, email)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    coalesce(new.email, '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================================
-- 6. SEGURIDAD (RLS + permisos por columna)
-- El directorio es visible para cualquier jugador autenticado, pero el teléfono
-- y el correo NO: esos se entregan solo a quien tenga un partido reservado con
-- esa persona, a través de la función contact_of().
-- =============================================================================
alter table public.clubs      enable row level security;
alter table public.profiles   enable row level security;
alter table public.challenges enable row level security;
alter table public.bookings   enable row level security;

-- Permisos explícitos. El proyecto se crea con "exponer tablas nuevas
-- automáticamente" desactivado, así que cada tabla se expone porque acá lo
-- decidimos. Sin estos GRANT la app no podría leer ni escribir nada.
grant usage on schema public to authenticated;
grant select on public.clubs to authenticated;
grant select, insert, update on public.challenges to authenticated;
grant select, update on public.bookings to authenticated;

drop policy if exists clubs_read on public.clubs;
create policy clubs_read on public.clubs
  for select to authenticated using (true);

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Permisos por columna: el contacto queda fuera del SELECT general.
revoke select on public.profiles from authenticated;
grant select (
  id, name, category, national_rank, club_id, hand, comuna,
  playing_since, available_days, preferred_slot, bio, role, created_at,
  rating, rating_matches, staff, member_id, must_change_password
) on public.profiles to authenticated;
grant update (
  name, category, national_rank, club_id, hand, phone, comuna,
  playing_since, available_days, preferred_slot, bio, must_change_password
) on public.profiles to authenticated;

-- Contacto del rival: solo si hay una reserva confirmada entre ambos.
create or replace function public.contact_of(target uuid)
returns table (email text, phone text)
language sql
security definer
set search_path = public
as $$
  select p.email, p.phone
    from public.profiles p
   where p.id = target
     and (
       target = auth.uid()
       or exists (
         select 1 from public.bookings b
          where b.status = 'confirmada'
            and ((b.player_a = auth.uid() and b.player_b = target)
              or (b.player_b = auth.uid() and b.player_a = target))
       )
     );
$$;

-- El administrador tiene lectura global (panel de solo lectura). No puede
-- suplantar a nadie: eso exigiría la clave secreta, que nunca va en el navegador.
-- El rol se asigna a mano en Table Editor → profiles → role = 'admin'; los
-- jugadores no pueden cambiárselo porque 'role' está fuera del GRANT de UPDATE.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

grant execute on function public.is_admin() to authenticated;

-- Desafíos: cada quien ve y crea los suyos; el admin los ve todos.
drop policy if exists challenges_read on public.challenges;
create policy challenges_read on public.challenges
  for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid() or public.is_admin());

drop policy if exists challenges_insert on public.challenges;
create policy challenges_insert on public.challenges
  for insert to authenticated with check (from_id = auth.uid());

-- Retirar el propio desafío o rechazar uno recibido. Aceptar y contraproponer
-- van por RPC: las dos tocan horarios y hay que revalidarlos en el servidor.
drop policy if exists challenges_update on public.challenges;
create policy challenges_update on public.challenges
  for update to authenticated
  using (from_id = auth.uid() or to_id = auth.uid())
  with check (status in ('cancelada','rechazada'));

-- La nota del club puede llevar nombres de invitados y detalles de cobro, así que
-- queda fuera de lo que ve cualquier jugador: se entrega solo por club_notes().
revoke select on public.bookings from authenticated;
grant select (
  id, challenge_id, club_id, court, match_date, match_time,
  player_a, player_b, status, winner_id, score, created_at, reported_by,
  sets_winner, sets_loser, result_status, source
) on public.bookings to authenticated;

create or replace function public.club_notes(p_club text)
returns table (booking_id uuid, note text)
language sql
stable
security definer
set search_path = public
as $$
  select b.id, b.club_note
    from public.bookings b
   where b.club_id = p_club
     and public.is_club_admin(p_club);
$$;

grant execute on function public.club_notes(text) to authenticated;

-- Reservas: visibles para todos (la grilla de canchas muestra la ocupación),
-- pero solo se crean y modifican por RPC.
drop policy if exists bookings_read on public.bookings;
create policy bookings_read on public.bookings
  for select to authenticated using (true);

drop policy if exists bookings_cancel on public.bookings;
create policy bookings_cancel on public.bookings
  for update to authenticated
  using (player_a = auth.uid() or player_b = auth.uid())
  with check (status = 'cancelada');

-- =============================================================================
-- 7. ACEPTAR UN DESAFÍO = RESERVAR
-- Toda la validación vive acá, en una sola transacción: es el único lugar donde
-- se puede garantizar que dos personas no se lleven la misma cancha.
-- =============================================================================
create or replace function public.accept_challenge(p_challenge uuid)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  ch        public.challenges;
  cl        public.clubs;
  chosen    int;
  n         int;
  new_book  public.bookings;
  slot_ts   timestamptz;
begin
  select * into ch from public.challenges where id = p_challenge for update;
  if ch is null then
    raise exception 'Ese desafío ya no existe.';
  end if;
  -- Un desafío lo acepta el desafiado; una contrapropuesta la acepta quien
  -- desafió, que es a quien le cambiaron el horario.
  if ch.status = 'pendiente' then
    if ch.to_id <> auth.uid() then
      raise exception 'Solo puede aceptar el jugador desafiado.';
    end if;
  elsif ch.status = 'contrapropuesta' then
    if ch.from_id <> auth.uid() then
      raise exception 'La contrapropuesta la acepta quien envió el desafío.';
    end if;
  else
    raise exception 'La solicitud ya no está pendiente.';
  end if;

  select * into cl from public.clubs where id = ch.club_id;

  slot_ts := (ch.match_date + ch.match_time::time) at time zone 'America/Santiago';
  if slot_ts < now() then
    update public.challenges
       set status = 'caducada', note = 'Ese horario ya pasó.'
     where id = ch.id;
    raise exception 'Ese horario ya pasó.';
  end if;

  -- Ninguno de los dos puede tener otro partido en ese bloque.
  if exists (
    select 1 from public.bookings b
     where b.status = 'confirmada'
       and b.match_date = ch.match_date
       and b.match_time = ch.match_time
       and (b.player_a in (ch.from_id, ch.to_id) or b.player_b in (ch.from_id, ch.to_id))
  ) then
    update public.challenges
       set status = 'caducada', note = 'Uno de los jugadores ya tiene un partido en ese bloque.'
     where id = ch.id;
    raise exception 'Uno de los jugadores ya tiene un partido en ese bloque.';
  end if;

  -- Elección de cancha: la pedida, o la primera libre.
  if ch.court > 0 then
    if exists (
      select 1 from public.bookings b
       where b.status = 'confirmada' and b.club_id = ch.club_id
         and b.match_date = ch.match_date and b.match_time = ch.match_time
         and b.court = ch.court
    ) then
      update public.challenges
         set status = 'caducada',
             note = 'La cancha ' || ch.court || ' ya está reservada en ese bloque.'
       where id = ch.id;
      raise exception 'La cancha % ya está reservada en ese bloque.', ch.court;
    end if;
    chosen := ch.court;
  else
    chosen := null;
    for n in 1..cl.courts loop
      if not exists (
        select 1 from public.bookings b
         where b.status = 'confirmada' and b.club_id = ch.club_id
           and b.match_date = ch.match_date and b.match_time = ch.match_time
           and b.court = n
      ) then
        chosen := n;
        exit;
      end if;
    end loop;
    if chosen is null then
      update public.challenges
         set status = 'caducada', note = 'No quedan canchas disponibles en ese club a esa hora.'
       where id = ch.id;
      raise exception 'No quedan canchas disponibles en ese club a esa hora.';
    end if;
  end if;

  insert into public.bookings (
    challenge_id, club_id, court, match_date, match_time,
    player_a, player_b
  ) values (
    ch.id, ch.club_id, chosen, ch.match_date, ch.match_time,
    ch.from_id, ch.to_id
  )
  returning * into new_book;

  update public.challenges
     set status = 'aceptada', booking_id = new_book.id
   where id = ch.id;

  -- Los demás desafíos pendientes de estos dos en el mismo bloque quedan sin efecto.
  update public.challenges
     set status = 'caducada',
         note = 'Uno de los jugadores reservó otro partido en ese bloque.'
   where status = 'pendiente'
     and id <> ch.id
     and match_date = ch.match_date
     and match_time = ch.match_time
     and (from_id in (ch.from_id, ch.to_id) or to_id in (ch.from_id, ch.to_id));

  return new_book;
end $$;

-- Responder con otro horario en vez de rechazar. Solo una vuelta: si el horario
-- nuevo tampoco sirve, se rechaza y se manda un desafío nuevo. Sin ese límite
-- esto se convierte en una negociación de ida y vuelta sin cierre.
create or replace function public.counter_challenge(
  p_challenge uuid,
  p_date      date,
  p_time      text,
  p_court     int,
  p_msg       text
)
returns public.challenges
language plpgsql
security definer
set search_path = public
as $$
declare
  ch      public.challenges;
  cl      public.clubs;
  slot_ts timestamptz;
  fila    public.challenges;
begin
  select * into ch from public.challenges where id = p_challenge for update;
  if ch is null then
    raise exception 'Ese desafio ya no existe.';
  end if;
  if ch.to_id <> auth.uid() then
    raise exception 'Solo el jugador desafiado puede proponer otro horario.';
  end if;
  if ch.status <> 'pendiente' then
    raise exception 'Ese desafio ya no esta pendiente.';
  end if;

  select * into cl from public.clubs where id = ch.club_id;
  if p_court < 0 or p_court > cl.courts then
    raise exception 'Ese club no tiene una cancha %.', p_court;
  end if;

  slot_ts := (p_date + p_time::time) at time zone 'America/Santiago';
  if slot_ts < now() then
    raise exception 'Ese horario ya paso.';
  end if;

  if p_date = ch.match_date and p_time = ch.match_time then
    raise exception 'Ese es el mismo horario que te propusieron.';
  end if;

  -- Ninguno de los dos puede tener ya un partido en el bloque nuevo.
  if exists (
    select 1 from public.bookings b
     where b.status = 'confirmada'
       and b.match_date = p_date
       and b.match_time = p_time
       and (b.player_a in (ch.from_id, ch.to_id) or b.player_b in (ch.from_id, ch.to_id))
  ) then
    raise exception 'Uno de los dos ya tiene un partido en ese bloque.';
  end if;

  update public.challenges
     set counter_of_date = ch.match_date,
         counter_of_time = ch.match_time,
         counter_msg     = coalesce(p_msg, ''),
         counter_by      = auth.uid(),
         match_date      = p_date,
         match_time      = p_time,
         court           = p_court,
         status          = 'contrapropuesta',
         note            = ''
   where id = ch.id
  returning * into fila;

  return fila;
end $$;

grant execute on function public.counter_challenge(uuid, date, text, int, text) to authenticated;

-- =============================================================================
-- 8. RESULTADO EN DOS PASOS
-- Un jugador lo carga, el otro lo confirma. El rating se mueve recien al
-- confirmarse: sin eso, cualquiera podria inventarse una victoria y subir.
-- =============================================================================
create or replace function public.report_result(
  p_booking   uuid,
  p_winner    uuid,
  p_sets_win  int,
  p_sets_lose int
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  bk      public.bookings;
  updated public.bookings;
begin
  select * into bk from public.bookings where id = p_booking for update;
  if bk is null then
    raise exception 'Esa reserva no existe.';
  end if;
  if auth.uid() not in (bk.player_a, bk.player_b) then
    raise exception 'Solo los jugadores del partido pueden cargar el resultado.';
  end if;
  if bk.status <> 'confirmada' then
    raise exception 'El partido esta cancelado.';
  end if;
  if bk.result_status = 'confirmado' then
    raise exception 'Ese resultado ya fue confirmado.';
  end if;
  if bk.result_status = 'por_confirmar' then
    raise exception 'Ya hay un resultado esperando confirmacion.';
  end if;
  if p_winner not in (bk.player_a, bk.player_b) then
    raise exception 'El ganador debe ser uno de los dos jugadores.';
  end if;
  if not (
    (p_sets_win = 3 and p_sets_lose between 0 and 2) or
    (p_sets_win = 2 and p_sets_lose between 0 and 1)
  ) then
    raise exception 'El marcador por sets no es valido.';
  end if;

  update public.bookings
     set winner_id = p_winner,
         sets_winner = p_sets_win,
         sets_loser = p_sets_lose,
         reported_by = auth.uid(),
         result_status = 'por_confirmar'
   where id = bk.id
  returning * into updated;

  return updated;
end $$;

create or replace function public.confirm_result(
  p_booking uuid,
  p_accept  boolean
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  bk      public.bookings;
  updated public.bookings;
begin
  select * into bk from public.bookings where id = p_booking for update;
  if bk is null then
    raise exception 'Esa reserva no existe.';
  end if;
  if auth.uid() not in (bk.player_a, bk.player_b) then
    raise exception 'Solo los jugadores del partido pueden confirmar el resultado.';
  end if;
  if bk.result_status <> 'por_confirmar' then
    raise exception 'No hay un resultado esperando confirmacion.';
  end if;
  if bk.reported_by = auth.uid() then
    raise exception 'El resultado lo tiene que confirmar el rival, no quien lo carga.';
  end if;

  if not p_accept then
    update public.bookings
       set result_status = 'rechazado',
           winner_id = null, sets_winner = null, sets_loser = null, reported_by = null
     where id = bk.id
    returning * into updated;
    return updated;
  end if;

  update public.bookings
     set result_status = 'confirmado'
   where id = bk.id
  returning * into updated;

  -- El rating se mueve solo con resultados confirmados por ambos.
  perform public.apply_elo(updated.id);

  return updated;
end $$;

drop function if exists public.register_result(uuid, uuid, text);

-- =============================================================================
-- 9. PERMISOS DE EJECUCIÓN
-- =============================================================================
grant execute on function public.accept_challenge(uuid) to authenticated;
grant execute on function public.report_result(uuid, uuid, int, int) to authenticated;
grant execute on function public.confirm_result(uuid, boolean) to authenticated;
grant execute on function public.contact_of(uuid) to authenticated;

-- =============================================================================
-- 10b. RATING PROPIO (estilo Elo)
-- Reemplaza al ranking nacional autodeclarado. Se mueve solo, con los resultados
-- confirmados por ambos jugadores, y lo calcula el servidor.
-- =============================================================================
alter table public.profiles
  add column if not exists rating         int,
  add column if not exists rating_matches int not null default 0;

create table if not exists public.rating_history (
  id            uuid primary key default gen_random_uuid(),
  player_id     uuid not null references public.profiles(id) on delete cascade,
  booking_id    uuid references public.bookings(id) on delete cascade,
  rating_before int not null,
  rating_after  int not null,
  created_at    timestamptz not null default now()
);

create index if not exists rating_history_player_idx
  on public.rating_history (player_id, created_at);

grant select on public.rating_history to authenticated;
alter table public.rating_history enable row level security;

drop policy if exists rating_history_read on public.rating_history;
create policy rating_history_read on public.rating_history
  for select to authenticated using (true);

-- Punto de partida segun la categoria declarada: si todos partieran igual, el
-- sistema tardaria meses en reflejar la realidad.
create or replace function public.initial_rating(p_cat text)
returns int
language sql
immutable
as $$
  select case p_cat
    when 'Primera'        then 1600
    when 'Segunda'        then 1450
    when 'Tercera'        then 1300
    when 'Cuarta'         then 1150
    when 'Damas A'        then 1500
    when 'Damas B'        then 1350
    when 'Juvenil Sub-19' then 1350
    when 'Máster +40'     then 1300
    when 'Máster +50'     then 1250
    else 1200
  end;
$$;

-- Al completar el perfil, el jugador arranca con el rating de su categoria.
create or replace function public.seed_rating()
returns trigger
language plpgsql
as $$
begin
  if new.rating is null and new.category is not null then
    new.rating := public.initial_rating(new.category);
  end if;
  return new;
end $$;

drop trigger if exists profiles_seed_rating on public.profiles;
create trigger profiles_seed_rating
  before insert or update of category on public.profiles
  for each row execute function public.seed_rating();

update public.profiles
   set rating = public.initial_rating(category)
 where rating is null and category is not null;

-- Aplica el resultado de un partido al rating de ambos.
create or replace function public.apply_elo(p_booking uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bk        public.bookings;
  perdedor  uuid;
  r_gan     int;
  r_per     int;
  n_gan     int;
  n_per     int;
  esperado  numeric;
  margen    numeric;
  k_gan     numeric;
  k_per     numeric;
  repetidos int;
  delta_gan int;
  delta_per int;
begin
  select * into bk from public.bookings where id = p_booking;
  if bk is null or bk.result_status <> 'confirmado' or bk.winner_id is null then
    return;
  end if;
  -- Un partido mueve el rating una sola vez.
  if exists (select 1 from public.rating_history where booking_id = bk.id) then
    return;
  end if;

  perdedor := case when bk.winner_id = bk.player_a then bk.player_b else bk.player_a end;

  select coalesce(rating, initial_rating(category)), rating_matches
    into r_gan, n_gan from public.profiles where id = bk.winner_id;
  select coalesce(rating, initial_rating(category)), rating_matches
    into r_per, n_per from public.profiles where id = perdedor;

  if r_gan is null or r_per is null then
    return;
  end if;

  -- Probabilidad de que ganara el que gano.
  esperado := 1.0 / (1.0 + power(10.0, (r_per - r_gan) / 400.0));

  -- El marcador pesa, pero suave: un 3-2 en squash puede ser un partidazo.
  margen := case
    when bk.sets_loser = 0 then 1.15
    when bk.sets_loser = 1 then 1.00
    else 0.85
  end;

  -- Menos movimiento cuando el sistema ya conoce al jugador. Se usa el mismo K
  -- para los dos (el menor) para que el intercambio sea estrictamente de suma
  -- cero: lo que uno gana, el otro lo pierde. Con K distinto por jugador se
  -- crearian puntos de la nada y el promedio del circuito se inflaria.
  k_gan := least(case when n_gan < 10 then 32 else 20 end,
                 case when n_per < 10 then 32 else 20 end);
  k_per := k_gan;

  -- Jugar muchas veces contra el mismo rival en poco tiempo rinde cada vez menos:
  -- es la puerta natural para inflar el rating entre conocidos.
  select count(*) into repetidos
    from public.bookings b
   where b.result_status = 'confirmado'
     and b.id <> bk.id
     and b.match_date > current_date - 30
     and ((b.player_a = bk.player_a and b.player_b = bk.player_b)
       or (b.player_a = bk.player_b and b.player_b = bk.player_a));
  if repetidos >= 3 then
    k_gan := k_gan * 0.5;
    k_per := k_per * 0.5;
  end if;

  delta_gan := round(k_gan * margen * (1 - esperado));
  delta_per := round(k_per * margen * (0 - (1 - esperado)));

  update public.profiles
     set rating = r_gan + delta_gan, rating_matches = n_gan + 1
   where id = bk.winner_id;
  update public.profiles
     set rating = greatest(100, r_per + delta_per), rating_matches = n_per + 1
   where id = perdedor;

  insert into public.rating_history (player_id, booking_id, rating_before, rating_after)
  values (bk.winner_id, bk.id, r_gan, r_gan + delta_gan),
         (perdedor,     bk.id, r_per, greatest(100, r_per + delta_per));
end $$;

-- Rehace todos los ratings desde cero, en orden cronologico. Sirve para poner al
-- dia los partidos que ya estaban cargados antes de existir el rating.
create or replace function public.recalc_ratings()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  fila  record;
  total int := 0;
begin
  -- El WHERE es obligatorio: Supabase bloquea los DELETE sin condicion.
  delete from public.rating_history where true;
  update public.profiles
     set rating = initial_rating(category), rating_matches = 0
   where category is not null;

  for fila in
    select id from public.bookings
     where result_status = 'confirmado' and winner_id is not null
     order by match_date, match_time, created_at
  loop
    perform public.apply_elo(fila.id);
    total := total + 1;
  end loop;

  return total;
end $$;

grant execute on function public.recalc_ratings() to authenticated;

-- =============================================================================
-- 10c. ADMINISTRACION DEL CLUB Y PAGOS
-- Distinto del administrador de la app: el del club ve solo lo suyo. La cancha
-- se cobra por jugador (la mitad cada uno), que es como se paga en la practica.
-- =============================================================================
alter table public.clubs
  add column if not exists court_price int not null default 15000;

create table if not exists public.club_admins (
  club_id   text not null references public.clubs(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  primary key (club_id, player_id)
);

alter table public.club_admins enable row level security;
grant select on public.club_admins to authenticated;

drop policy if exists club_admins_read on public.club_admins;
create policy club_admins_read on public.club_admins
  for select to authenticated using (true);

create or replace function public.is_club_admin(p_club text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.club_admins
     where club_id = p_club and player_id = auth.uid()
  );
$$;

grant execute on function public.is_club_admin(text) to authenticated;

-- =============================================================================
-- CREACIÓN DE SOCIOS
-- La cuenta de acceso la crea el navegador del club con el registro normal de
-- Supabase, y después llama a esto para completar la ficha. Va por función y no
-- por un grant de update porque el club está escribiendo en la fila de OTRA
-- persona, y eso no puede quedar abierto.
--
-- El RUT no se entrega en el SELECT general: es dato personal y no tiene por qué
-- verlo otro jugador. Para saber si un RUT ya existe está socio_por_rut(), que
-- devuelve a quién pertenece sin exponer el número de nadie más.
-- =============================================================================
create or replace function public.club_crear_socio(
  p_user     uuid,
  p_club     text,
  p_member   text,
  p_rut      text,
  p_name     text,
  p_phone    text,
  p_category text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  limpio text := public.normalizar_rut(p_rut);
  fila   public.profiles;
begin
  if not public.is_club_admin(p_club) then
    raise exception 'Solo el administrador del club puede crear socios.';
  end if;
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'El socio necesita nombre.';
  end if;
  if btrim(coalesce(p_member, '')) = '' then
    raise exception 'El socio necesita un ID.';
  end if;
  if limpio is null or not public.rut_valido(limpio) then
    raise exception 'Ese RUT no es valido. Revisa el numero y el digito verificador.';
  end if;

  -- Mensaje util en vez de un choque de indice: la recepcion tiene que entender
  -- que el socio ya existe, o va a inventar un RUT falso para poder seguir.
  if exists (select 1 from public.profiles where rut = limpio and id <> p_user) then
    raise exception 'Ese RUT ya esta registrado como socio.';
  end if;
  if exists (select 1 from public.profiles where member_id = p_member and id <> p_user) then
    raise exception 'Ese ID de socio ya esta usado.';
  end if;

  update public.profiles
     set name      = btrim(p_name),
         member_id = p_member,
         rut       = limpio,
         phone     = coalesce(p_phone, ''),
         category  = p_category,
         club_id   = p_club,
         must_change_password = true,
         created_by = auth.uid()
   where id = p_user
  returning * into fila;

  if fila is null then
    raise exception 'No encontre la cuenta recien creada.';
  end if;
  return fila;
end $$;

grant execute on function public.club_crear_socio(uuid, text, text, text, text, text, text)
  to authenticated;

-- ¿Ese RUT ya es socio? Devuelve a quién pertenece, sin entregar el RUT de nadie.
create or replace function public.socio_por_rut(p_club text, p_rut text)
returns table (id uuid, name text, member_id text, club_id text, last_played date)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_club_admin(p_club) then
    raise exception 'Solo el administrador del club puede consultar socios.';
  end if;

  return query
    select p.id, p.name, p.member_id, p.club_id,
           (select max(b.match_date) from public.bookings b
             where b.status = 'confirmada'
               and (b.player_a = p.id or b.player_b = p.id)) as last_played
      from public.profiles p
     where p.rut = public.normalizar_rut(p_rut);
end $$;

grant execute on function public.socio_por_rut(text, text) to authenticated;

-- Resetear la clave de un socio que la perdió NO se puede hacer desde el
-- navegador: cambiar la contraseña de otra persona necesita la llave de
-- administración de Supabase, que no puede vivir en el código de la app. Queda
-- pendiente y se resuelve con una Edge Function.

-- =============================================================================
-- NO LLAMAR
-- Anotación interna del club sobre un jugador: está lesionado, de vacaciones o
-- lo que sea, y no tiene sentido llamarlo para ofrecerle cancha.
--
-- Sale de un problema concreto: a un lesionado lo llamaban todos los días y el
-- jugador terminaba molesto de repetir lo mismo. Es gestión de reservas, no una
-- función del jugador: NO le cambia nada al jugador, que puede seguir
-- agendando, desafiando y siendo desafiado igual que siempre. Lo único que hace
-- es que a quien está haciendo los llamados le salga la marca.
--
-- Por eso vive acá y no en profiles: es del club sobre su operación, y solo la
-- ve quien administra ese club. La lee la lista desde la que se sale a llamar.
--
-- until_date es lo que hace que esto no se pudra: al pasar la fecha la marca
-- deja de aplicar sola, sin que nadie tenga que acordarse de sacarla.
-- =============================================================================
create table if not exists public.player_flags (
  club_id    text not null references public.clubs(id) on delete cascade,
  player_id  uuid not null references public.profiles(id) on delete cascade,
  reason     text not null check (reason in ('lesion','vacaciones','otro')),
  note       text not null default '',
  from_date  date,
  until_date date,
  marked_by  uuid references public.profiles(id) on delete set null,
  marked_at  timestamptz not null default now(),
  primary key (club_id, player_id),
  constraint player_flags_range_chk
    check (from_date is null or until_date is null or until_date >= from_date)
);

alter table public.player_flags enable row level security;
grant select, insert, update, delete on public.player_flags to authenticated;

-- Solo quien administra el club ve y toca las marcas de ese club. Para el
-- jugador la tabla no existe: la consulta le devuelve cero filas.
drop policy if exists player_flags_read on public.player_flags;
create policy player_flags_read on public.player_flags
  for select to authenticated using (public.is_club_admin(club_id));

drop policy if exists player_flags_write on public.player_flags;
create policy player_flags_write on public.player_flags
  for insert to authenticated with check (public.is_club_admin(club_id));

drop policy if exists player_flags_edit on public.player_flags;
create policy player_flags_edit on public.player_flags
  for update to authenticated
  using (public.is_club_admin(club_id))
  with check (public.is_club_admin(club_id));

drop policy if exists player_flags_delete on public.player_flags;
create policy player_flags_delete on public.player_flags
  for delete to authenticated using (public.is_club_admin(club_id));

-- =============================================================================
-- AVISOS DEL CLUB
-- La otra mitad de la lista de llamados: en vez de telefonear, el club le manda
-- el aviso al jugador dentro de la app. "La cancha 1 a las 17:00 está libre" al
-- que siempre juega a esa hora.
--
-- El aviso lleva el bloque concreto (fecha, hora, cancha) y no solo el texto,
-- para que al jugador le podamos ofrecer la acción: publicar que juega ahí y
-- buscar rival. Un aviso que obliga a ir a buscar el horario a mano se pierde.
--
-- Reservar la cancha no lo hace el aviso: sigue haciendo falta un rival. Esto
-- avisa, no agenda.
-- =============================================================================
create table if not exists public.club_messages (
  id         uuid primary key default gen_random_uuid(),
  club_id    text not null references public.clubs(id) on delete cascade,
  player_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (length(btrim(body)) > 0),
  match_date date,
  match_time text,
  court      int  not null default 0,
  sent_by    uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create index if not exists club_messages_player_idx
  on public.club_messages (player_id, created_at desc);

alter table public.club_messages enable row level security;
grant select, insert, delete on public.club_messages to authenticated;
-- El jugador solo puede tocar read_at: darlo por visto, nada más.
grant update (read_at) on public.club_messages to authenticated;

-- Lo ve el destinatario y quien administra el club que lo mandó.
drop policy if exists club_messages_read on public.club_messages;
create policy club_messages_read on public.club_messages
  for select to authenticated
  using (player_id = auth.uid() or public.is_club_admin(club_id));

drop policy if exists club_messages_send on public.club_messages;
create policy club_messages_send on public.club_messages
  for insert to authenticated with check (public.is_club_admin(club_id));

drop policy if exists club_messages_seen on public.club_messages;
create policy club_messages_seen on public.club_messages
  for update to authenticated
  using (player_id = auth.uid()) with check (player_id = auth.uid());

drop policy if exists club_messages_drop on public.club_messages;
create policy club_messages_drop on public.club_messages
  for delete to authenticated using (public.is_club_admin(club_id));

-- Configuración del club: la edita solo quien lo administra. Va por función y
-- no por un grant de update para que la comprobación viva en el servidor.
create or replace function public.set_club_config(
  p_club         text,
  p_opens        text,
  p_last_slot    text,
  p_slot_minutes int,
  p_goal_weekday int,
  p_goal_weekend int,
  p_rules        text,
  p_cancel_rule  text,
  p_phone        text,
  p_email        text,
  p_address      text
)
returns public.clubs
language plpgsql
security definer
set search_path = public
as $$
declare
  fila public.clubs;
begin
  if not public.is_club_admin(p_club) then
    raise exception 'Solo el administrador del club puede cambiar su configuracion.';
  end if;
  if p_slot_minutes < 10 or p_slot_minutes > 180 then
    raise exception 'La duracion del turno tiene que estar entre 10 y 180 minutos.';
  end if;
  if p_opens::time >= p_last_slot::time then
    raise exception 'La hora del ultimo turno tiene que ser posterior a la de apertura.';
  end if;
  if p_goal_weekday < 0 or p_goal_weekend < 0 then
    raise exception 'Las metas no pueden ser negativas.';
  end if;

  update public.clubs
     set opens        = p_opens,
         last_slot    = p_last_slot,
         slot_minutes = p_slot_minutes,
         goal_weekday = p_goal_weekday,
         goal_weekend = p_goal_weekend,
         rules        = coalesce(p_rules, ''),
         cancel_rule  = coalesce(p_cancel_rule, ''),
         phone        = coalesce(p_phone, ''),
         email        = coalesce(p_email, ''),
         address      = coalesce(p_address, '')
   where id = p_club
  returning * into fila;

  return fila;
end $$;

grant execute on function public.set_club_config(
  text, text, text, int, int, int, text, text, text, text, text
) to authenticated;

-- Un cobro por jugador y por reserva.
create table if not exists public.payments (
  id         uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  -- nulo cuando la reserva la hizo el club para alguien sin cuenta
  player_id  uuid references public.profiles(id) on delete cascade,
  club_id    text not null references public.clubs(id),
  amount     int  not null,
  status     text not null default 'pendiente'
             check (status in ('pendiente','pagado','anulado')),
  paid_at    timestamptz,
  marked_by  uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (booking_id, player_id)
);

alter table public.payments alter column player_id drop not null;

create index if not exists payments_player_idx on public.payments (player_id, status);
create index if not exists payments_club_idx   on public.payments (club_id, status);

alter table public.payments enable row level security;
grant select on public.payments to authenticated;

-- Cada quien ve lo suyo; el administrador del club ve todo lo de su club.
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments
  for select to authenticated
  using (player_id = auth.uid() or public.is_club_admin(club_id) or public.is_admin());

-- Al confirmarse una reserva se generan los dos cobros, mitad y mitad.
create or replace function public.create_payments()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  precio int;
begin
  select court_price into precio from public.clubs where id = new.club_id;
  precio := coalesce(precio, 15000);

  /* La cancha se cobra por mitades, y cada mitad se le carga a alguien si se
     sabe a quien. Cuando el club reserva puede saber uno, los dos o ninguno:
     - los dos socios      -> dos cobros de la mitad, igual que una reserva normal
     - un socio y un invitado -> la mitad al socio, la otra sin nombre
     - dos invitados       -> un solo cobro por la cancha completa

     Antes cualquier reserva del club generaba un unico cobro sin jugador, asi que
     al socio no le aparecia su deuda aunque hubiera jugado. Con el club haciendo
     la mayoria de las reservas, eso dejaba la cobranza a ciegas. */
  if new.player_a is not null then
    insert into public.payments (booking_id, player_id, club_id, amount)
    values (new.id, new.player_a, new.club_id, precio / 2)
    on conflict (booking_id, player_id) do nothing;
  end if;

  if new.player_b is not null then
    insert into public.payments (booking_id, player_id, club_id, amount)
    values (new.id, new.player_b, new.club_id, precio / 2)
    on conflict (booking_id, player_id) do nothing;
  end if;

  -- La parte que no tiene nombre: la cancha completa si no se identifico a
  -- nadie, o la mitad si solo falto uno.
  if new.player_a is null or new.player_b is null then
    insert into public.payments (booking_id, player_id, club_id, amount)
    values (new.id, null, new.club_id,
            case when new.player_a is null and new.player_b is null
                 then precio else precio / 2 end);
  end if;

  return new;
end $$;

drop trigger if exists bookings_create_payments on public.bookings;
create trigger bookings_create_payments
  after insert on public.bookings
  for each row when (new.status = 'confirmada')
  execute function public.create_payments();

-- Cancelar una reserva anula sus cobros: lo que no se jugo no se cobra.
create or replace function public.void_payments()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelada' and old.status <> 'cancelada' then
    update public.payments
       set status = 'anulado'
     where booking_id = new.id and status <> 'pagado';
  end if;
  return new;
end $$;

drop trigger if exists bookings_void_payments on public.bookings;
create trigger bookings_void_payments
  after update of status on public.bookings
  for each row execute function public.void_payments();

-- Marcar pagado o volver a pendiente. Solo el administrador de ese club.
create or replace function public.mark_payment(p_payment uuid, p_paid boolean)
returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  pago    public.payments;
  updated public.payments;
begin
  select * into pago from public.payments where id = p_payment for update;
  if pago is null then
    raise exception 'Ese cobro no existe.';
  end if;
  if not public.is_club_admin(pago.club_id) then
    raise exception 'Solo el administrador del club puede marcar pagos.';
  end if;
  if pago.status = 'anulado' then
    raise exception 'Ese cobro esta anulado porque la reserva se cancelo.';
  end if;

  update public.payments
     set status    = case when p_paid then 'pagado' else 'pendiente' end,
         paid_at   = case when p_paid then now() else null end,
         marked_by = case when p_paid then auth.uid() else null end
   where id = pago.id
  returning * into updated;

  return updated;
end $$;

grant execute on function public.mark_payment(uuid, boolean) to authenticated;

-- Reservar una cancha para gente que no usa la app. La nota guarda quien jugo.
-- La firma cambia, asi que la version vieja se retira: si no, Postgres deja las
-- dos conviviendo como sobrecargas y la app podria llamar a la que no queremos.
drop function if exists public.club_book(text, date, text, int, text);

create or replace function public.club_book(
  p_club     text,
  p_date     date,
  p_time     text,
  p_court    int,
  p_note     text,
  p_player_a uuid default null,
  p_player_b uuid default null
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  cl       public.clubs;
  nueva    public.bookings;
  slot_ts  timestamptz;
begin
  if not public.is_club_admin(p_club) then
    raise exception 'Solo el administrador del club puede reservar canchas.';
  end if;

  select * into cl from public.clubs where id = p_club;
  if cl is null then
    raise exception 'Ese club no existe.';
  end if;
  if p_court < 1 or p_court > cl.courts then
    raise exception 'Ese club no tiene una cancha %.', p_court;
  end if;

  slot_ts := (p_date + p_time::time) at time zone 'America/Santiago';
  if slot_ts < now() - interval '12 hours' then
    raise exception 'Ese horario ya paso.';
  end if;

  if exists (
    select 1 from public.bookings b
     where b.status = 'confirmada' and b.club_id = p_club
       and b.match_date = p_date and b.match_time = p_time and b.court = p_court
  ) then
    raise exception 'Esa cancha ya esta reservada en ese bloque.';
  end if;

  -- El mismo jugador dos veces no es un partido.
  if p_player_a is not null and p_player_a = p_player_b then
    raise exception 'Elige dos jugadores distintos.';
  end if;

  -- Las cuentas de club no juegan.
  if exists (select 1 from public.profiles
              where id in (p_player_a, p_player_b) and staff) then
    raise exception 'Una cuenta de administracion no puede jugar.';
  end if;

  -- Ninguno de los dos puede tener ya un partido en ese bloque, en este club o
  -- en otro: es la misma regla que se aplica al aceptar un desafio.
  if exists (
    select 1 from public.bookings b
     where b.status = 'confirmada'
       and b.match_date = p_date
       and b.match_time = p_time
       and (b.player_a in (p_player_a, p_player_b)
         or b.player_b in (p_player_a, p_player_b))
  ) then
    raise exception 'Uno de los jugadores ya tiene un partido en ese bloque.';
  end if;

  insert into public.bookings (
    club_id, court, match_date, match_time, player_a, player_b,
    status, source, club_note
  ) values (
    p_club, p_court, p_date, p_time, p_player_a, p_player_b,
    'confirmada', 'club', coalesce(p_note, '')
  )
  returning * into nueva;

  return nueva;
end $$;

-- Anotar quien jugo, o cualquier cosa que el club necesite recordar para cobrar.
create or replace function public.set_club_note(p_booking uuid, p_note text)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  bk      public.bookings;
  updated public.bookings;
begin
  select * into bk from public.bookings where id = p_booking;
  if bk is null then
    raise exception 'Esa reserva no existe.';
  end if;
  if not public.is_club_admin(bk.club_id) then
    raise exception 'Solo el administrador del club puede anotar en las reservas.';
  end if;

  update public.bookings set club_note = coalesce(p_note, '')
   where id = bk.id
  returning * into updated;

  return updated;
end $$;

-- Cancelar desde el club: libera la cancha y anula el cobro.
create or replace function public.club_cancel(p_booking uuid)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  bk      public.bookings;
  updated public.bookings;
begin
  select * into bk from public.bookings where id = p_booking;
  if bk is null then
    raise exception 'Esa reserva no existe.';
  end if;
  if not public.is_club_admin(bk.club_id) then
    raise exception 'Solo el administrador del club puede cancelar estas reservas.';
  end if;

  update public.bookings set status = 'cancelada'
   where id = bk.id
  returning * into updated;

  return updated;
end $$;

grant execute on function public.club_book(text, date, text, int, text, uuid, uuid)
  to authenticated;
grant execute on function public.set_club_note(uuid, text) to authenticated;
grant execute on function public.club_cancel(uuid) to authenticated;

-- Primero se limpian los cobros sin jugador que no correspondan a la cancha
-- completa: los generaba el traspaso de mas abajo antes de que supiera de estas
-- reservas. Va antes del indice, porque el indice no se puede crear si todavia
-- hay duplicados.
delete from public.payments p
 using public.bookings b, public.clubs c
 where p.booking_id = b.id
   and c.id = b.club_id
   and p.player_id is null
   and p.amount <> c.court_price;

-- Por si quedaran varios cobros de cancha completa en una misma reserva, se
-- conserva el mas antiguo.
delete from public.payments p
 where p.player_id is null
   and exists (
     select 1 from public.payments q
      where q.booking_id = p.booking_id
        and q.player_id is null
        and (q.created_at < p.created_at
             or (q.created_at = p.created_at and q.id < p.id))
   );

-- Una reserva del club tiene un unico cobro, por la cancha entera. La restriccion
-- de la tabla no sirve para eso: en SQL dos nulos no se consideran iguales, asi
-- que no impide repetirlos.
create unique index if not exists payments_club_unique
  on public.payments (booking_id) where player_id is null;

-- Genera los cobros de las reservas que ya existian antes de esta seccion. Se
-- saltan las reservas que ya tienen cobros y las que no tienen jugadores de la
-- app, que son las del club y llevan un cobro unico.
insert into public.payments (booking_id, player_id, club_id, amount, status)
select b.id, j.jugador, b.club_id, coalesce(c.court_price, 15000) / 2,
       case when b.status = 'cancelada' then 'anulado' else 'pendiente' end
  from public.bookings b
  join public.clubs c on c.id = b.club_id
  cross join lateral (values (b.player_a), (b.player_b)) as j(jugador)
 where j.jugador is not null
   and not exists (select 1 from public.payments p where p.booking_id = b.id)
on conflict (booking_id, player_id) do nothing;

-- =============================================================================
-- 10. CANCHAS ABIERTAS
-- Publicar "quiero jugar tal día a tal hora" sin apuntarle a nadie. Otro jugador
-- se suma y el que publicó confirma. Publicar NO bloquea la cancha: la primera
-- pareja que confirma se la lleva, venga de un desafío o de una publicación.
-- =============================================================================
create table if not exists public.open_invites (
  id           uuid primary key default gen_random_uuid(),
  player_id    uuid not null references public.profiles(id) on delete cascade,
  club_id      text not null references public.clubs(id),
  match_date   date not null,
  match_time   text not null,
  court        int  not null default 0,   -- 0 = cualquiera disponible
  category     text,                      -- categoría que busca; es preferencia, no muro
  message      text default '',
  status       text not null default 'abierta'
               check (status in ('abierta','postulada','cerrada','cancelada')),
  candidate_id uuid references public.profiles(id) on delete set null,
  booking_id   uuid references public.bookings(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- Un mismo jugador no puede tener dos publicaciones vivas para el mismo bloque.
create unique index if not exists open_invites_slot_unique
  on public.open_invites (player_id, match_date, match_time)
  where status in ('abierta','postulada');

create index if not exists open_invites_estado_idx on public.open_invites (status, match_date);

alter table public.open_invites enable row level security;

grant select, insert, update on public.open_invites to authenticated;

-- Las publicaciones abiertas las ve todo el mundo; las cerradas, solo los suyos.
drop policy if exists open_invites_read on public.open_invites;
create policy open_invites_read on public.open_invites
  for select to authenticated
  using (
    status in ('abierta','postulada')
    or player_id = auth.uid()
    or candidate_id = auth.uid()
    or public.is_admin()
  );

drop policy if exists open_invites_insert on public.open_invites;
create policy open_invites_insert on public.open_invites
  for insert to authenticated with check (player_id = auth.uid());

-- Solo para darse de baja: sumarse y confirmar van por funciones.
drop policy if exists open_invites_cancel on public.open_invites;
create policy open_invites_cancel on public.open_invites
  for update to authenticated
  using (player_id = auth.uid())
  with check (status = 'cancelada');

-- Sumarse a una publicación: queda a la espera de que el autor confirme.
create or replace function public.join_invite(p_invite uuid)
returns public.open_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  inv     public.open_invites;
  updated public.open_invites;
  slot_ts timestamptz;
begin
  select * into inv from public.open_invites where id = p_invite for update;
  if inv is null then
    raise exception 'Esa publicacion ya no existe.';
  end if;
  if inv.player_id = auth.uid() then
    raise exception 'Esa publicacion es tuya.';
  end if;
  if inv.status <> 'abierta' then
    raise exception 'Alguien se te adelanto: esa publicacion ya no esta disponible.';
  end if;

  slot_ts := (inv.match_date + inv.match_time::time) at time zone 'America/Santiago';
  if slot_ts < now() then
    raise exception 'Ese horario ya paso.';
  end if;

  if exists (
    select 1 from public.bookings b
     where b.status = 'confirmada'
       and b.match_date = inv.match_date and b.match_time = inv.match_time
       and (b.player_a = auth.uid() or b.player_b = auth.uid())
  ) then
    raise exception 'Ya tienes un partido reservado en ese bloque.';
  end if;

  update public.open_invites
     set candidate_id = auth.uid(), status = 'postulada'
   where id = inv.id
  returning * into updated;

  return updated;
end $$;

-- El autor acepta o rechaza. Al aceptar se crea la reserva; al rechazar, la
-- publicacion vuelve a quedar visible para cualquier otro.
create or replace function public.confirm_invite(
  p_invite uuid,
  p_accept boolean
)
returns public.open_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  inv      public.open_invites;
  updated  public.open_invites;
  cl       public.clubs;
  chosen   int;
  n        int;
  new_book public.bookings;
  slot_ts  timestamptz;
begin
  select * into inv from public.open_invites where id = p_invite for update;
  if inv is null then
    raise exception 'Esa publicacion ya no existe.';
  end if;
  if inv.player_id <> auth.uid() then
    raise exception 'Solo quien publico puede confirmar.';
  end if;
  if inv.status <> 'postulada' then
    raise exception 'No hay nadie esperando confirmacion.';
  end if;

  if not p_accept then
    update public.open_invites
       set candidate_id = null, status = 'abierta'
     where id = inv.id
    returning * into updated;
    return updated;
  end if;

  slot_ts := (inv.match_date + inv.match_time::time) at time zone 'America/Santiago';
  if slot_ts < now() then
    update public.open_invites set status = 'cancelada' where id = inv.id;
    raise exception 'Ese horario ya paso.';
  end if;

  if exists (
    select 1 from public.bookings b
     where b.status = 'confirmada'
       and b.match_date = inv.match_date and b.match_time = inv.match_time
       and (b.player_a in (inv.player_id, inv.candidate_id)
         or b.player_b in (inv.player_id, inv.candidate_id))
  ) then
    raise exception 'Uno de los dos ya tiene un partido en ese bloque.';
  end if;

  select * into cl from public.clubs where id = inv.club_id;

  if inv.court > 0 then
    if exists (
      select 1 from public.bookings b
       where b.status = 'confirmada' and b.club_id = inv.club_id
         and b.match_date = inv.match_date and b.match_time = inv.match_time
         and b.court = inv.court
    ) then
      raise exception 'La cancha % ya esta reservada en ese bloque.', inv.court;
    end if;
    chosen := inv.court;
  else
    chosen := null;
    for n in 1..cl.courts loop
      if not exists (
        select 1 from public.bookings b
         where b.status = 'confirmada' and b.club_id = inv.club_id
           and b.match_date = inv.match_date and b.match_time = inv.match_time
           and b.court = n
      ) then
        chosen := n;
        exit;
      end if;
    end loop;
    if chosen is null then
      raise exception 'Se acabaron las canchas de ese club a esa hora.';
    end if;
  end if;

  insert into public.bookings (
    club_id, court, match_date, match_time, player_a, player_b
  ) values (
    inv.club_id, chosen, inv.match_date, inv.match_time,
    inv.player_id, inv.candidate_id
  )
  returning * into new_book;

  update public.open_invites
     set status = 'cerrada', booking_id = new_book.id
   where id = inv.id
  returning * into updated;

  -- Las demas publicaciones de estos dos en el mismo bloque quedan sin efecto.
  update public.open_invites
     set status = 'cancelada'
   where id <> inv.id
     and status in ('abierta','postulada')
     and match_date = inv.match_date and match_time = inv.match_time
     and (player_id in (inv.player_id, inv.candidate_id)
       or candidate_id in (inv.player_id, inv.candidate_id));

  return updated;
end $$;

grant execute on function public.join_invite(uuid) to authenticated;
grant execute on function public.confirm_invite(uuid, boolean) to authenticated;

-- =============================================================================
-- 11. CAMBIOS EN VIVO
-- Supabase solo publica los cambios de las tablas que estén en esta publicación.
-- Sin esto, la app se entera de un desafío nuevo recién al recargar la página.
-- =============================================================================
do $$
begin
  alter publication supabase_realtime add table public.challenges;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.bookings;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.open_invites;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.rating_history;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.payments;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.player_flags;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.club_messages;
exception when duplicate_object then null;
end $$;

-- =============================================================================
-- 12. RETIRO DE LA ESCALERILLA
-- Va al final a propósito: para cuando esto corre, las funciones de más arriba
-- ya se reemplazaron por versiones que no nombran nada de la escalerilla, así
-- que se puede borrar sin que quede una dependencia colgando.
--
-- OJO: esto borra de forma definitiva quién estaba inscrito y en qué puesto.
-- Los partidos, los ratings, las reservas y los cobros no se tocan.
-- =============================================================================
-- El "if exists" del drop trigger cubre el trigger, no la tabla: si ladder_members
-- ya se borro en una corrida anterior, esta linea suelta relation does not exist
-- y voltea toda la transaccion. Por eso va preguntando primero por la tabla.
do $$
begin
  if exists (select 1 from pg_tables
              where schemaname = 'public' and tablename = 'ladder_members') then
    execute 'drop trigger if exists ladder_close_gap on public.ladder_members';
  end if;
end $$;

drop function if exists public.close_ladder_gap();
drop function if exists public.join_ladder(text);
drop function if exists public.leave_ladder(text);

do $$
begin
  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime'
                and schemaname = 'public' and tablename = 'ladder_members') then
    alter publication supabase_realtime drop table public.ladder_members;
  end if;
end $$;

drop table if exists public.ladder_members;

-- La marca de "no llamar" vivió un rato en profiles, antes de que quedara claro
-- que es del club y no del jugador.
alter table public.profiles drop column if exists away_reason;
alter table public.profiles drop column if exists away_note;
alter table public.profiles drop column if exists away_from;
alter table public.profiles drop column if exists away_until;

alter table public.profiles  drop constraint if exists profiles_ladder_unique;
alter table public.profiles  drop column if exists ladder_pos;
alter table public.challenges drop column if exists ladder;
alter table public.bookings  drop column if exists ladder;
alter table public.bookings  drop column if exists ladder_defender;
alter table public.bookings  drop column if exists ladder_applied;

-- Al borrar ladder_pos, Postgres se lleva por delante el indice que lo incluia.
-- Se rehace solo sobre club_id, que es lo que consulta el directorio.
drop index if exists public.profiles_club_idx;
create index profiles_club_idx on public.profiles (club_id);

-- =============================================================================
-- 13. PERMISOS PARA EL CODIGO DEL SERVIDOR
-- Las Edge Functions se conectan con la llave secreta, que en la base es el rol
-- service_role. En este proyecto ese rol no traia permisos sobre nuestras tablas,
-- asi que sus consultas devolvian "permission denied for table profiles" aunque
-- la llave fuera la correcta y estuviera bien puesta.
--
-- No abre una puerta nueva: esa llave ya podia todo por el Admin API de
-- autenticacion, y solo la conoce el servidor. Lo que faltaba era el acceso a
-- las tablas.
--
-- El alter default privileges es para que las tablas que se agreguen despues no
-- repitan el mismo problema.
-- =============================================================================
grant usage on schema public to service_role;
grant all privileges on all tables    in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant execute       on all functions  in schema public to service_role;

alter default privileges in schema public grant all on tables    to service_role;
alter default privileges in schema public grant all on sequences to service_role;
