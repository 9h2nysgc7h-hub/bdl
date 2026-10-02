-- ============================================================
-- SCHEMA · Plataforma BDL (Bastión De Líderes by Nave)
-- Pegar TODO en Supabase → SQL Editor → Run. Una sola vez.
-- Después correr seed.sql (carga los 11 módulos + 83 lecciones reales).
-- ============================================================

-- ---------- PERFILES ----------
-- Se crea solo cuando alguien se registra. El founder crea los accesos
-- a mano desde Authentication → Users → Add user (ver guía de despliegue).
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  rol text not null default 'alumno' check (rol in ('alumno','founder')),
  fecha_inicio date not null default current_date,
  modulo_actual int not null default 0,       -- semana más alta desbloqueada; la sube el founder a mano
  pidio_desbloqueo boolean not null default false, -- el alumno avisó que terminó y espera que lo desbloqueen
  created_at timestamptz not null default now()
);

-- Evita que un alumno se auto-desbloquee o se auto-ascienda a founder
-- llamando directo a la API (la UI nunca expone esos campos para editar,
-- pero RLS por sí solo no restringe columnas, solo filas).
create or replace function public.proteger_columnas_perfil()
returns trigger as $$
begin
  if not exists(select 1 from profiles where id = auth.uid() and rol = 'founder') then
    new.modulo_actual := old.modulo_actual;
    new.rol := old.rol;
    new.fecha_inicio := old.fecha_inicio;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_proteger_perfil on profiles;
create trigger trg_proteger_perfil
  before update on profiles
  for each row execute procedure public.proteger_columnas_perfil();

-- Alta automática de perfil cuando se crea un usuario en Authentication.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)));
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- CURRÍCULUM ----------
create table if not exists modulos (
  id int primary key,
  numero int not null,
  titulo text not null,
  orden int not null
);

create table if not exists lecciones (
  id text primary key,                 -- ej. '4.10'
  modulo_id int not null references modulos(id) on delete cascade,
  numero text not null,
  titulo text not null,
  duracion_min int not null,
  tipo text not null default 'video' check (tipo in ('video','entregable')),
  youtube_id text,                     -- se carga a medida que grabás (panel admin)
  orden int not null
);

-- ---------- PROGRESO POR ALUMNO ----------
create table if not exists progreso (
  alumno_id uuid not null references profiles(id) on delete cascade,
  leccion_id text not null references lecciones(id) on delete cascade,
  completado boolean not null default true,
  completado_at timestamptz not null default now(),
  primary key (alumno_id, leccion_id)
);

-- ---------- FOTO ANTES / DESPUÉS (Semana 0 vs. Semana 10) ----------
create table if not exists diagnostico (
  alumno_id uuid primary key references profiles(id) on delete cascade,
  lidera_equipo boolean,
  facturacion_cash numeric,
  show_rate numeric,
  close_rate numeric,
  leads_semana numeric,
  problema_grande text,
  respondido_at timestamptz not null default now()
);

create table if not exists cierre (
  alumno_id uuid primary key references profiles(id) on delete cascade,
  facturacion_cash numeric,
  show_rate numeric,
  close_rate numeric,
  leads_semana numeric,
  completado_at timestamptz not null default now()
);

-- ============================================================
-- RLS — cada alumno ve y edita solo lo suyo; el founder ve todo.
-- ============================================================
alter table profiles enable row level security;
alter table modulos enable row level security;
alter table lecciones enable row level security;
alter table progreso enable row level security;
alter table diagnostico enable row level security;
alter table cierre enable row level security;

create or replace function public.es_founder()
returns boolean as $$
  select exists(select 1 from profiles where id = auth.uid() and rol = 'founder');
$$ language sql security definer set search_path = public stable;

create policy "ver perfiles" on profiles for select
  using (auth.uid() = id or es_founder());
create policy "editar propio perfil" on profiles for update
  using (auth.uid() = id or es_founder());

create policy "ver modulos" on modulos for select
  using (auth.role() = 'authenticated');
create policy "founder edita modulos" on modulos for all
  using (es_founder());

create policy "ver lecciones" on lecciones for select
  using (auth.role() = 'authenticated');
create policy "founder edita lecciones" on lecciones for all
  using (es_founder());

create policy "ver progreso" on progreso for select
  using (auth.uid() = alumno_id or es_founder());
create policy "marcar propio progreso" on progreso for insert
  with check (auth.uid() = alumno_id);
create policy "desmarcar propio progreso" on progreso for delete
  using (auth.uid() = alumno_id);

create policy "ver diagnostico" on diagnostico for select
  using (auth.uid() = alumno_id or es_founder());
create policy "cargar propio diagnostico" on diagnostico for insert
  with check (auth.uid() = alumno_id);
create policy "editar propio diagnostico" on diagnostico for update
  using (auth.uid() = alumno_id);

create policy "ver cierre" on cierre for select
  using (auth.uid() = alumno_id or es_founder());
create policy "cargar propio cierre" on cierre for insert
  with check (auth.uid() = alumno_id);
create policy "editar propio cierre" on cierre for update
  using (auth.uid() = alumno_id);

-- ============================================================
-- LISTO. Seguí con seed.sql para cargar el currículum real.
-- ============================================================
