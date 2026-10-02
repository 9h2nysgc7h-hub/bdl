-- ============================================================
-- MIGRACIÓN · Registro público + aprobación de miembros + rol admin
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

alter table profiles add column if not exists email text;
alter table profiles add column if not exists aprobado boolean not null default false;

update profiles set email = u.email from auth.users u where profiles.id = u.id and profiles.email is null;
update profiles set aprobado = true where aprobado = false; -- las cuentas ya creadas (la tuya) quedan aprobadas de entrada

alter table profiles drop constraint if exists profiles_rol_check;
alter table profiles add constraint profiles_rol_check check (rol in ('alumno','founder','admin'));

-- El trigger de alta ahora guarda también el email y el nombre que la
-- persona puso al registrarse (antes solo lo hacía cuando vos la creabas
-- a mano desde el dashboard).
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nombre, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)), new.email);
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- founder Y admin tienen los mismos privilegios de gestión
create or replace function public.es_staff()
returns boolean as $$
  select exists(select 1 from profiles where id = auth.uid() and rol in ('founder','admin'));
$$ language sql security definer set search_path = public stable;

-- gatekeeper real: solo lecciones/módulos a aprobados (o staff) — si no,
-- alguien sin aprobar podría leer el currículum llamando directo a la API,
-- aunque la pantalla de "pendiente" se lo esconda en la interfaz.
create or replace function public.esta_aprobado()
returns boolean as $$
  select coalesce((select aprobado from profiles where id = auth.uid()), false) or es_staff();
$$ language sql security definer set search_path = public stable;

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
  for each row execute procedure proteger_columnas_perfil();

drop policy if exists "ver perfiles" on profiles;
create policy "ver perfiles" on profiles for select using (auth.uid() = id or es_staff());
drop policy if exists "editar propio perfil" on profiles;
create policy "editar propio perfil" on profiles for update using (auth.uid() = id or es_staff());

drop policy if exists "ver modulos" on modulos;
create policy "ver modulos" on modulos for select using (esta_aprobado());
drop policy if exists "founder edita modulos" on modulos;
drop policy if exists "staff edita modulos" on modulos;
create policy "staff edita modulos" on modulos for all using (es_staff());

drop policy if exists "ver lecciones" on lecciones;
create policy "ver lecciones" on lecciones for select using (esta_aprobado());
drop policy if exists "founder edita lecciones" on lecciones;
drop policy if exists "staff edita lecciones" on lecciones;
create policy "staff edita lecciones" on lecciones for all using (es_staff());

drop policy if exists "ver progreso" on progreso;
create policy "ver progreso" on progreso for select using (auth.uid() = alumno_id or es_staff());
drop policy if exists "marcar propio progreso" on progreso;
create policy "marcar propio progreso" on progreso for insert with check (auth.uid() = alumno_id and esta_aprobado());

drop policy if exists "ver diagnostico" on diagnostico;
create policy "ver diagnostico" on diagnostico for select using (auth.uid() = alumno_id or es_staff());
drop policy if exists "ver cierre" on cierre;
create policy "ver cierre" on cierre for select using (auth.uid() = alumno_id or es_staff());

-- ============================================================
-- LISTO en SQL. Falta un paso manual, en el dashboard (no acá):
-- Authentication → Providers → Email → apagar "Confirm email".
-- Así el que se registra entra directo a la pantalla de "pendiente de
-- aprobación", en vez de quedar esperando un mail de confirmación.
-- ============================================================
