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
  ladder_pos     int,
  created_at     timestamptz not null default now()
);

-- La posición en la escalerilla es única dentro de cada club. DEFERRABLE porque
-- al intercambiar dos jugadores ambos quedan momentáneamente en la misma.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_ladder_unique') then
    alter table public.profiles
      add constraint profiles_ladder_unique unique (club_id, ladder_pos)
      deferrable initially deferred;
  end if;
end $$;

create index if not exists profiles_club_idx on public.profiles (club_id, ladder_pos);

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
  ladder     boolean not null default false,
  message    text default '',
  status     text not null default 'pendiente'
             check (status in ('pendiente','aceptada','rechazada','cancelada','caducada')),
  note       text default '',
  booking_id uuid,
  created_at timestamptz not null default now(),
  constraint challenges_distinct_players check (from_id <> to_id)
);

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
  ladder           boolean not null default false,
  ladder_defender  uuid references public.profiles(id) on delete set null,
  ladder_applied   boolean not null default false,
  created_at       timestamptz not null default now()
);

-- Esta es la regla que impide la doble reserva. Aunque dos personas acepten un
-- desafío en el mismo instante, la base de datos deja pasar solo a una.
create unique index if not exists bookings_slot_unique
  on public.bookings (club_id, match_date, match_time, court)
  where status = 'confirmada';

create index if not exists bookings_players_idx on public.bookings (player_a, player_b, match_date);

-- =============================================================================
-- 5. ESCALERILLA — ubicación automática
-- =============================================================================

-- Deja al jugador al final de la escalerilla de su club y cierra el hueco que
-- dejó en el club anterior.
create or replace function public.place_in_ladder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_pos int;
begin
  if tg_op = 'UPDATE' and new.club_id is not distinct from old.club_id then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.club_id is not null and old.ladder_pos is not null then
    update public.profiles
       set ladder_pos = ladder_pos - 1
     where club_id = old.club_id and ladder_pos > old.ladder_pos;
  end if;

  if new.club_id is null then
    new.ladder_pos := null;
    return new;
  end if;

  select coalesce(max(ladder_pos), 0) + 1 into next_pos
    from public.profiles where club_id = new.club_id;

  new.ladder_pos := next_pos;
  return new;
end $$;

drop trigger if exists profiles_place_in_ladder on public.profiles;
create trigger profiles_place_in_ladder
  before insert or update of club_id on public.profiles
  for each row execute function public.place_in_ladder();

-- Al borrarse una cuenta, los de abajo suben un puesto.
create or replace function public.close_ladder_gap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.club_id is not null and old.ladder_pos is not null then
    update public.profiles
       set ladder_pos = ladder_pos - 1
     where club_id = old.club_id and ladder_pos > old.ladder_pos;
  end if;
  return old;
end $$;

drop trigger if exists profiles_close_ladder_gap on public.profiles;
create trigger profiles_close_ladder_gap
  after delete on public.profiles
  for each row execute function public.close_ladder_gap();

-- =============================================================================
-- 6. PERFIL AUTOMÁTICO AL REGISTRARSE
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
-- 7. SEGURIDAD (RLS + permisos por columna)
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
  playing_since, available_days, preferred_slot, bio, role, ladder_pos, created_at
) on public.profiles to authenticated;
grant update (
  name, category, national_rank, club_id, hand, phone, comuna,
  playing_since, available_days, preferred_slot, bio
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

-- Retirar el propio desafío o rechazar uno recibido. Aceptar va por RPC.
drop policy if exists challenges_update on public.challenges;
create policy challenges_update on public.challenges
  for update to authenticated
  using (from_id = auth.uid() or to_id = auth.uid())
  with check (status in ('cancelada','rechazada'));

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
-- 8. ACEPTAR UN DESAFÍO = RESERVAR
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
  pos_from  int;
  pos_to    int;
begin
  select * into ch from public.challenges where id = p_challenge for update;
  if ch is null then
    raise exception 'Ese desafío ya no existe.';
  end if;
  if ch.to_id <> auth.uid() then
    raise exception 'Solo puede aceptar el jugador desafiado.';
  end if;
  if ch.status <> 'pendiente' then
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

  -- Rango de la escalerilla, revalidado al momento de aceptar.
  if ch.ladder then
    select ladder_pos into pos_from from public.profiles where id = ch.from_id;
    select ladder_pos into pos_to   from public.profiles where id = ch.to_id;
    if pos_from is null or pos_to is null or pos_to >= pos_from or pos_from - pos_to > 3 then
      update public.challenges
         set status = 'caducada',
             note = 'Las posiciones de la escalerilla cambiaron y el desafío quedó fuera de rango.'
       where id = ch.id;
      raise exception 'Las posiciones de la escalerilla cambiaron y el desafío quedó fuera de rango.';
    end if;
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
    player_a, player_b, ladder, ladder_defender
  ) values (
    ch.id, ch.club_id, chosen, ch.match_date, ch.match_time,
    ch.from_id, ch.to_id, ch.ladder, case when ch.ladder then ch.to_id else null end
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

-- =============================================================================
-- 9. REGISTRAR RESULTADO (y mover la escalerilla)
-- =============================================================================
create or replace function public.register_result(
  p_booking uuid,
  p_winner  uuid,
  p_score   text
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  bk        public.bookings;
  updated   public.bookings;
  pos_chal  int;
  pos_def   int;
  challenger uuid;
begin
  select * into bk from public.bookings where id = p_booking for update;
  if bk is null then
    raise exception 'Esa reserva no existe.';
  end if;
  if auth.uid() not in (bk.player_a, bk.player_b) then
    raise exception 'Solo los jugadores del partido pueden registrar el resultado.';
  end if;
  if bk.status <> 'confirmada' then
    raise exception 'El partido está cancelado.';
  end if;
  if p_winner not in (bk.player_a, bk.player_b) then
    raise exception 'El ganador debe ser uno de los dos jugadores.';
  end if;

  update public.bookings
     set winner_id = p_winner, score = coalesce(p_score, '')
   where id = bk.id
  returning * into updated;

  -- Escalerilla: si gana el desafiante, intercambian posiciones.
  if updated.ladder and not updated.ladder_applied then
    challenger := case when updated.ladder_defender = updated.player_b
                       then updated.player_a else updated.player_b end;

    if p_winner = challenger then
      set constraints all deferred;
      select ladder_pos into pos_chal from public.profiles where id = challenger;
      select ladder_pos into pos_def  from public.profiles where id = updated.ladder_defender;

      if pos_chal is not null and pos_def is not null then
        update public.profiles set ladder_pos = pos_def  where id = challenger;
        update public.profiles set ladder_pos = pos_chal where id = updated.ladder_defender;
      end if;
    end if;

    update public.bookings set ladder_applied = true where id = updated.id
    returning * into updated;
  end if;

  return updated;
end $$;

-- =============================================================================
-- 10. PERMISOS DE EJECUCIÓN
-- =============================================================================
grant execute on function public.accept_challenge(uuid) to authenticated;
grant execute on function public.register_result(uuid, uuid, text) to authenticated;
grant execute on function public.contact_of(uuid) to authenticated;
