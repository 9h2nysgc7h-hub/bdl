-- ============================================================
-- MIGRACIÓN · Recursos por lección (documentos, links, el entregable)
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

create table if not exists recursos (
  id bigint generated always as identity primary key,
  leccion_id text not null references lecciones(id) on delete cascade,
  titulo text not null,
  url text,
  descripcion text,
  orden int not null default 0,
  created_at timestamptz not null default now()
);

alter table recursos enable row level security;

drop policy if exists "ver recursos" on recursos;
create policy "ver recursos" on recursos for select using (esta_aprobado());

drop policy if exists "staff edita recursos" on recursos;
create policy "staff edita recursos" on recursos for all using (es_staff());

-- ============================================================
-- LISTO. Cada recurso se carga y se borra desde Admin → Recursos
-- por lección, dentro de la plataforma — no hace falta SQL para eso.
-- ============================================================
