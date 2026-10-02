-- ============================================================
-- MIGRACIÓN · Antigüedad de pedidos + último acceso + avisos en app
-- Pegar TODO en Supabase → SQL Editor → Run. Es idempotente.
-- ============================================================

alter table profiles add column if not exists pidio_desbloqueo_at timestamptz;
alter table profiles add column if not exists ultimo_acceso timestamptz;
alter table profiles add column if not exists aprobado_visto boolean not null default false;
alter table profiles add column if not exists modulo_visto int not null default 0;

-- No hace falta tocar el trigger de protección de columnas: estas cuatro
-- las puede escribir cada alumno sobre su propia fila sin riesgo (no
-- afectan aprobación, rol ni semana desbloqueada — eso lo sigue
-- protegiendo proteger_columnas_perfil igual que antes).

-- ============================================================
-- LISTO.
-- ============================================================
