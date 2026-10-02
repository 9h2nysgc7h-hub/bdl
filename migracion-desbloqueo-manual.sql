-- ============================================================
-- MIGRACIÓN · Desbloqueo manual por semana (reemplaza el automático por fecha)
-- Tu proyecto ya tiene schema.sql corrido — con esto solo agregás lo nuevo.
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

alter table profiles add column if not exists modulo_actual int not null default 0;
alter table profiles add column if not exists pidio_desbloqueo boolean not null default false;

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

-- ============================================================
-- LISTO. Semana 0 queda abierta para todos por defecto (modulo_actual=0).
-- Las siguientes las vas desbloqueando vos desde el panel Admin de la app.
-- ============================================================
