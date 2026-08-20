-- ============================================================
-- CAPITAL INICIAL
-- Carga el capital actual ($ 782.340) como ingreso dividido
-- en los 3 bolsillos con la regla 60/20/20 (igual que la app).
-- Ejecutar una sola vez en el SQL Editor de Supabase.
-- ============================================================

insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
values
  (now(), 'ingreso', 'reinversion', 469404, 'Capital inicial', now()),
  (now(), 'ingreso', 'ahorro',      156468, 'Capital inicial', now()),
  (now(), 'ingreso', 'personal',    156468, 'Capital inicial', now());