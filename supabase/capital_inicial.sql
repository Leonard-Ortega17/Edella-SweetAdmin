-- ============================================================
-- CAPITAL INICIAL (corrección)
-- Reemplaza el capital cargado anteriormente ($ 782.340) por el
-- capital real ($ 168.000). Divide 60/20/20 como la app:
--   reinversion = valor*3/5, ahorro = valor/5, personal = resto
-- Ejecutar una sola vez en el SQL Editor de Supabase.
-- ============================================================

begin;

-- 1) Quitar los movimientos del capital anterior (concepto 'Capital inicial')
delete from public.capital_movimientos
where concepto = 'Capital inicial';

-- 2) Insertar el capital real, dividido automáticamente en los 3 bolsillos
--    $ 168.000 -> reinversion 100800, ahorro 33600, personal 33600 (suma = 168000)
insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
values
  (now(), 'ingreso', 'reinversion', 100800, 'Capital inicial', now()),
  (now(), 'ingreso', 'ahorro',      33600,  'Capital inicial', now()),
  (now(), 'ingreso', 'personal',    33600,  'Capital inicial', now());

commit;