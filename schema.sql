-- ============================================================
-- SCHEMA · Plataforma BDL (Bastión De Líderes by Nave)
-- Pegar TODO en Supabase → SQL Editor → Run. Una sola vez.
-- Después correr seed.sql (carga los 11 módulos + 83 lecciones reales).
-- ============================================================

-- ---------- PERFILES ----------
-- Se crea solo cuando alguien se registra (registro público, con
-- aprobación manual después — ver aprobado más abajo).
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  email text,
  rol text not null default 'alumno' check (rol in ('alumno','founder','admin')),
  fecha_inicio date not null default current_date,
  modulo_actual int not null default 0,       -- semana más alta desbloqueada; la sube el founder/admin a mano
  pidio_desbloqueo boolean not null default false, -- el alumno avisó que terminó y espera que lo desbloqueen
  pidio_desbloqueo_at timestamptz,     -- cuándo avisó, para ver antigüedad en Admin
  ultimo_acceso timestamptz,           -- se actualiza solo en cada login
  aprobado_visto boolean not null default false, -- ya vio el banner de "te aprobaron"
  modulo_visto int not null default 0, -- última semana cuyo desbloqueo ya vio
  aprobado boolean not null default false,    -- alguien tiene que aprobarlo desde Admin → Miembros antes de que entre
  created_at timestamptz not null default now()
);

-- founder Y admin tienen los mismos privilegios de gestión
create or replace function public.es_staff()
returns boolean as $$
  select exists(select 1 from profiles where id = auth.uid() and rol in ('founder','admin'));
$$ language sql security definer set search_path = public stable;

-- gatekeeper real del contenido: sin aprobar (y sin ser staff), no se
-- puede leer el currículum ni marcar progreso, aunque se llame directo
-- a la API y no solo a través de la interfaz.
create or replace function public.esta_aprobado()
returns boolean as $$
  select coalesce((select aprobado from profiles where id = auth.uid()), false) or es_staff();
$$ language sql security definer set search_path = public stable;

-- Evita que alguien se auto-apruebe, se auto-desbloquee o se auto-ascienda
-- llamando directo a la API (la UI nunca expone esos campos para editar,
-- pero RLS por sí solo no restringe columnas, solo filas).
create or replace function public.proteger_columnas_perfil()
returns trigger as $$
begin
  if not es_staff() then
    new.modulo_actual := old.modulo_actual;
    new.rol := old.rol;
    new.fecha_inicio := old.fecha_inicio;
    new.aprobado := old.aprobado;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_proteger_perfil on profiles;
create trigger trg_proteger_perfil
  before update on profiles
  for each row execute procedure public.proteger_columnas_perfil();

-- Registra solo cuándo empezó y terminó cada semana: al aprobar arranca
-- el reloj de la Semana 0; cada cambio de modulo_actual cierra la
-- semana anterior y abre la nueva. No hace falta cargar nada a mano.
create or replace function public.registrar_avance_semana()
returns trigger as $$
begin
  if coalesce(old.aprobado,false) = false and new.aprobado = true then
    insert into avance_semanas (alumno_id, modulo_numero, iniciado_at)
    values (new.id, 0, now());
  end if;

  if new.modulo_actual is distinct from old.modulo_actual then
    update avance_semanas set completado_at = now()
      where alumno_id = new.id and modulo_numero = old.modulo_actual and completado_at is null;
    insert into avance_semanas (alumno_id, modulo_numero, iniciado_at)
      select new.id, new.modulo_actual, now()
      where not exists (
        select 1 from avance_semanas where alumno_id = new.id and modulo_numero = new.modulo_actual
      );
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_registrar_avance on profiles;
create trigger trg_registrar_avance
  after update on profiles
  for each row execute procedure public.registrar_avance_semana();

-- Alta automática de perfil cuando alguien se registra. El nombre y
-- apellido que puso en el formulario viaja en raw_user_meta_data.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nombre, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)), new.email);
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
  miniatura_url text,                  -- opcional: miniatura propia subida desde Admin
  orden int not null
);

-- ---------- RECURSOS POR LECCIÓN ----------
-- Documentos, links o la consigna del entregable, colgados debajo del
-- video de cada lección. Se cargan y borran desde Admin, no por SQL.
create table if not exists recursos (
  id bigint generated always as identity primary key,
  leccion_id text not null references lecciones(id) on delete cascade,
  titulo text not null,
  url text,
  descripcion text,
  orden int not null default 0,
  created_at timestamptz not null default now()
);

-- ---------- PROGRESO POR ALUMNO ----------
create table if not exists progreso (
  alumno_id uuid not null references profiles(id) on delete cascade,
  leccion_id text not null references lecciones(id) on delete cascade,
  completado boolean not null default true,
  completado_at timestamptz not null default now(),
  primary key (alumno_id, leccion_id)
);

-- ---------- ENTREGABLES: lo que el alumno deja al avisar que terminó ----------
create table if not exists entregas (
  id bigint generated always as identity primary key,
  alumno_id uuid not null references profiles(id) on delete cascade,
  modulo_numero int not null,
  contenido text not null,
  created_at timestamptz not null default now(),
  unique (alumno_id, modulo_numero)
);

-- ---------- HISTORIAL: cuándo empezó y terminó cada semana ----------
-- Se registra solo con un trigger — ver registrar_avance_semana más abajo.
create table if not exists avance_semanas (
  id bigint generated always as identity primary key,
  alumno_id uuid not null references profiles(id) on delete cascade,
  modulo_numero int not null,
  iniciado_at timestamptz not null default now(),
  completado_at timestamptz
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
-- RLS — cada alumno ve y edita solo lo suyo; founder/admin ven todo.
-- ============================================================
alter table profiles enable row level security;
alter table modulos enable row level security;
alter table lecciones enable row level security;
alter table recursos enable row level security;
alter table progreso enable row level security;
alter table entregas enable row level security;
alter table avance_semanas enable row level security;
alter table diagnostico enable row level security;
alter table cierre enable row level security;

create policy "ver perfiles" on profiles for select
  using (auth.uid() = id or es_staff());
create policy "editar propio perfil" on profiles for update
  using (auth.uid() = id or es_staff());

create policy "ver modulos" on modulos for select
  using (esta_aprobado());
create policy "staff edita modulos" on modulos for all
  using (es_staff());

create policy "ver lecciones" on lecciones for select
  using (esta_aprobado());
create policy "staff edita lecciones" on lecciones for all
  using (es_staff());

create policy "ver recursos" on recursos for select
  using (esta_aprobado());
create policy "staff edita recursos" on recursos for all
  using (es_staff());

create policy "ver progreso" on progreso for select
  using (auth.uid() = alumno_id or es_staff());

create policy "ver propia entrega" on entregas for select
  using (alumno_id = auth.uid() or es_staff());
create policy "cargar propia entrega" on entregas for insert
  with check (alumno_id = auth.uid());
create policy "editar propia entrega" on entregas for update
  using (alumno_id = auth.uid());

create policy "ver avance" on avance_semanas for select
  using (alumno_id = auth.uid() or es_staff());
create policy "marcar propio progreso" on progreso for insert
  with check (auth.uid() = alumno_id and esta_aprobado());
create policy "desmarcar propio progreso" on progreso for delete
  using (auth.uid() = alumno_id);

create policy "ver diagnostico" on diagnostico for select
  using (auth.uid() = alumno_id or es_staff());
create policy "cargar propio diagnostico" on diagnostico for insert
  with check (auth.uid() = alumno_id);
create policy "editar propio diagnostico" on diagnostico for update
  using (auth.uid() = alumno_id);

create policy "ver cierre" on cierre for select
  using (auth.uid() = alumno_id or es_staff());
create policy "cargar propio cierre" on cierre for insert
  with check (auth.uid() = alumno_id);
create policy "editar propio cierre" on cierre for update
  using (auth.uid() = alumno_id);

-- ---------- STORAGE: miniaturas propias ----------
insert into storage.buckets (id, name, public)
values ('miniaturas', 'miniaturas', true)
on conflict (id) do nothing;

-- No hace falta habilitar RLS acá: storage.objects ya la trae activada
-- de fábrica en Supabase, y el rol del SQL Editor no es dueño de esa
-- tabla para poder tocarla (tiraría "must be owner of table objects").

create policy "ver miniaturas" on storage.objects for select
  using (bucket_id = 'miniaturas');

create policy "staff sube miniaturas" on storage.objects for insert
  with check (bucket_id = 'miniaturas' and es_staff());
create policy "staff actualiza miniaturas" on storage.objects for update
  using (bucket_id = 'miniaturas' and es_staff());
create policy "staff borra miniaturas" on storage.objects for delete
  using (bucket_id = 'miniaturas' and es_staff());

-- ============================================================
-- LISTO en SQL. Seguí con seed.sql. Después, en el dashboard (no en
-- SQL): Authentication → Providers → Email → apagar "Confirm email",
-- así el que se registra entra directo a la pantalla de "pendiente de
-- aprobación" en vez de quedar esperando un mail.
-- ============================================================
