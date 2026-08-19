-- ============================================================
-- LIMPIEZA DE DATOS DE PRUEBA
-- Borra ventas, gastos, capital, deudas, productos y promociones.
-- CONSERVA: categorias y app_usuarios (login) y toda la estructura/RLS.
-- Ejecutar en el SQL Editor de Supabase.
-- ============================================================

-- Detalle de ventas
delete from venta_items;
delete from venta_promociones;
-- Ventas (cabeceras)
delete from ventas;

-- Detalle de gastos
delete from gasto_items;
-- Gastos (cabeceras)
delete from gastos;

-- Movimientos de capital
delete from capital_movimientos;

-- Movimientos de deuda (abonos y cargos)
delete from deuda_movimientos;
-- Deudores
delete from deudores;

-- Relación de productos en promociones
delete from promocion_productos;
-- Promociones
delete from promociones;
-- Productos
delete from productos;

-- El esquema, RLS, categorias y app_usuarios siguen intactos.