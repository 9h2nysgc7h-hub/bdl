-- ============================================================
-- MIGRACIÓN · Canje de código para desbloquear preview (self-serve)
-- Pegar en Supabase → SQL Editor → Run. Idempotente.
-- Requiere migracion-preview.sql ya corrida (columna es_preview).
-- ============================================================

-- El código que se revela al final de videos-ocultos.html. Para
-- rotarlo, cambiar el valor acá abajo y volver a correr este archivo.
-- No es información sensible: es la misma clave que ve cualquiera que
-- termine el video, no protege nada más allá de esta promo puntual.

create or replace function public.proteger_columnas_perfil()
returns trigger as $$
begin
  if not es_staff() then
    new.modulo_actual := old.modulo_actual;
    new.rol := old.rol;
    new.fecha_inicio := old.fecha_inicio;
    -- único bypass permitido: canjear_codigo_preview() marca esta bandera
    -- de sesión justo antes de su propio update, así que una llamada
    -- directa de un alumno a profiles.update({aprobado:true}) sigue
    -- bloqueada como siempre.
    if coalesce(current_setting('app.canje_preview_ok', true), '') <> 'true' then
      new.aprobado := old.aprobado;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.canjear_codigo_preview(codigo text)
returns boolean as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  if trim(upper(codigo)) <> 'BDLVIP' then
    return false;
  end if;
  perform set_config('app.canje_preview_ok', 'true', true);
  update profiles set aprobado = true, es_preview = true where id = auth.uid();
  return true;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function public.canjear_codigo_preview(text) to authenticated;
