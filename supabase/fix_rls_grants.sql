-- ============================================================
-- EDALLA SWEETADMIN — FIX: permission denied for table <x>
-- Causa: al rol `authenticated` le faltan los GRANT de tabla.
--        RLS es una capa posterior al permiso de tabla; sin GRANT,
--        Postgres corta la consulta antes de evaluar las policies.
-- Aplicar UNA VEZ en Supabase SQL Editor (proyecto ya creado).
-- ============================================================

grant usage on schema public to anon, authenticated;

-- Tablas de negocio: CRUD para el rol autenticado.
-- La allow-list de SOLO 2 cuentas la sigue imponiendo RLS mediante
-- public.edella_es_usuario_autorizado().
grant select, insert, update, delete
  on productos, promociones, promocion_productos,
     ventas, venta_items, capital_movimientos,
     gastos, deudores, deuda_movimientos
  to authenticated;

-- app_usuarios: SOLO lectura. Sin INSERT/UPDATE/DELETE =>
-- ningún usuario (ni siquiera autorizado) puede modificar la allow-list.
grant select
  on app_usuarios
  to authenticated;

-- Permitir ejecutar la función de autorización usada por las policies.
grant execute on function public.edella_es_usuario_autorizado()
  to anon, authenticated;
