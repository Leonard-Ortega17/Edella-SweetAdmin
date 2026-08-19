-- ============================================================
-- EDALLA SWEETADMIN — MIGRACIÓN: CATEGORÍAS DINÁMICAS
-- Convierte `productos.categoria` (text + CHECK hardcodeado) en
-- una relación normalizada con una tabla `categorias`.
-- NO destruye datos existentes; crea las categorías actuales y
-- relaciona los productos con ellas.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLA CATEGORIAS
-- ------------------------------------------------------------
create table categorias (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null unique,
  activa     boolean not null default true,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2) RLS + GRANTS de categorias (misma función de allow-list)
-- ------------------------------------------------------------
alter table categorias enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on categorias to authenticated;

create policy categorias_select_auth on categorias for select using (public.edella_es_usuario_autorizado());
create policy categorias_insert_auth on categorias for insert with check (public.edella_es_usuario_autorizado());
create policy categorias_update_auth on categorias for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy categorias_delete_auth on categorias for delete using (public.edella_es_usuario_autorizado());

-- ------------------------------------------------------------
-- 3) SEMILLAR CATEGORÍAS INICIALES
--    Categorías canónicas de la Fase 1 + cualquier categoría
--    distinta que ya exista en productos (para no perder nada).
-- ------------------------------------------------------------
insert into categorias (nombre)
select x.nombre
from (values ('cheesecake'), ('pave'), ('ancheta'), ('otro')) as x(nombre)
where not exists (
  select 1 from categorias c where lower(c.nombre) = x.nombre
);

insert into categorias (nombre)
select distinct categoria
from productos
where not exists (
  select 1 from categorias c where lower(c.nombre) = lower(productos.categoria)
);

-- ------------------------------------------------------------
-- 4) RELACIONAR PRODUCTOS CON CATEGORIAS
-- ------------------------------------------------------------
alter table productos add column categoria_id uuid
  references categorias(id) on delete restrict;

update productos p
set categoria_id = c.id
from categorias c
where lower(c.nombre) = lower(p.categoria);

-- Ya sin productos sin categoría: hacer la relación obligatoria
alter table productos alter column categoria_id set not null;

-- ------------------------------------------------------------
-- 5) QUITAR LA COLUMNA DE TEXTO (y su CHECK hardcodeado)
--    Las categorías ahora viven únicamente en la tabla `categorias`.
-- ------------------------------------------------------------
alter table productos drop column categoria;

-- Índice para consultas/estadísticas por categoría (ventas futuras).
create index if not exists idx_productos_categoria_id
  on productos(categoria_id);