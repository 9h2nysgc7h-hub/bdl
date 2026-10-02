-- ============================================================
-- MIGRACIÓN · Miniaturas propias por lección (Supabase Storage)
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

alter table lecciones add column if not exists miniatura_url text;

-- Bucket público para las miniaturas (cualquiera las puede VER, pero
-- solo founder/admin las puede subir o borrar — ver políticas abajo).
insert into storage.buckets (id, name, public)
values ('miniaturas', 'miniaturas', true)
on conflict (id) do nothing;

-- No hace falta "alter table storage.objects enable row level security" —
-- en Supabase esa tabla ya viene con RLS activado de fábrica, y el rol
-- que corre el SQL Editor no es dueño de esa tabla para poder tocarlo
-- (da el error "must be owner of table objects" si se intenta).

drop policy if exists "ver miniaturas" on storage.objects;
create policy "ver miniaturas" on storage.objects for select
  using (bucket_id = 'miniaturas');

drop policy if exists "staff sube miniaturas" on storage.objects;
create policy "staff sube miniaturas" on storage.objects for insert
  with check (bucket_id = 'miniaturas' and es_staff());

drop policy if exists "staff actualiza miniaturas" on storage.objects;
create policy "staff actualiza miniaturas" on storage.objects for update
  using (bucket_id = 'miniaturas' and es_staff());

drop policy if exists "staff borra miniaturas" on storage.objects;
create policy "staff borra miniaturas" on storage.objects for delete
  using (bucket_id = 'miniaturas' and es_staff());

-- ============================================================
-- LISTO. Se sube desde Admin → Cargar videos → columna Miniatura,
-- sin tocar nada más acá.
-- ============================================================
