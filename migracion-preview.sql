-- ============================================================
-- MIGRACIÓN · Cuentas de preview (acceso solo a videos sueltos)
-- Pegar en Supabase → SQL Editor → Run. Idempotente.
-- ============================================================

alter table profiles add column if not exists es_preview boolean not null default false;
comment on column profiles.es_preview is 'Cuenta de preview: ve todo el catálogo pero solo puede reproducir las lecciones en la whitelist (PREVIEW_LECCIONES en index.html). No usa modulo_actual.';
