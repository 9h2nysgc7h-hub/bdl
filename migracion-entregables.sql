-- ============================================================
-- MIGRACIÓN · El alumno deja su entregable real al avisar que terminó
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

create table if not exists entregas (
  id bigint generated always as identity primary key,
  alumno_id uuid not null references profiles(id) on delete cascade,
  modulo_numero int not null,
  contenido text not null,
  created_at timestamptz not null default now(),
  unique (alumno_id, modulo_numero)
);

alter table entregas enable row level security;

drop policy if exists "ver propia entrega" on entregas;
create policy "ver propia entrega" on entregas for select
  using (alumno_id = auth.uid() or es_staff());

drop policy if exists "cargar propia entrega" on entregas;
create policy "cargar propia entrega" on entregas for insert
  with check (alumno_id = auth.uid());

drop policy if exists "editar propia entrega" on entregas;
create policy "editar propia entrega" on entregas for update
  using (alumno_id = auth.uid());

-- ============================================================
-- LISTO. Se carga sola cuando el alumno toca "Avisar que terminé" en
-- el dashboard, y se ve en Admin → Pedidos de desbloqueo.
-- ============================================================
