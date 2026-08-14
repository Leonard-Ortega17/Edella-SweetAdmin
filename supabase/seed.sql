-- ============================================================
-- EDALLA SWEETADMIN — FASE 1: Esquema + RLS (2 cuentas autorizadas)
-- Valores monetarios en pesos colombianos (INTEGER, sin decimales)
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
-- 1) TABLAS (cada FK apunta solo a tablas ya creadas)
-- ============================================================

-- PRODUCTOS
create table productos (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  categoria   text not null check (categoria in ('cheesecake','pave','ancheta','otro')),
  precio_base integer not null check (precio_base >= 0),
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- PROMOCIONES
create table promociones (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null,
  descripcion  text,
  precio_promo integer not null check (precio_promo >= 0),
  activa       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- PROMOCION_PRODUCTOS (puente)
create table promocion_productos (
  promocion_id uuid not null references promociones(id) on delete cascade,
  producto_id  uuid not null references productos(id) on delete restrict,
  cantidad     integer not null default 1 check (cantidad > 0),
  primary key (promocion_id, producto_id)
);

-- DEUDORES
create table deudores (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- VENTAS
create table ventas (
  id           uuid primary key default gen_random_uuid(),
  fecha        timestamptz not null default now(),
  tipo         text not null check (tipo in ('normal','promocion','deuda')),
  propina      integer not null default 0 check (propina >= 0),
  total        integer not null check (total >= 0),
  promocion_id uuid references promociones(id) on delete set null,
  deudor_id    uuid references deudores(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- VENTA_ITEMS (puente)
create table venta_items (
  venta_id         uuid not null references ventas(id) on delete cascade,
  producto_id      uuid not null references productos(id) on delete restrict,
  cantidad         integer not null check (cantidad > 0),
  precio_unitario  integer not null check (precio_unitario >= 0),
  primary key (venta_id, producto_id)
);

-- GASTOS
create table gastos (
  id                    uuid primary key default gen_random_uuid(),
  fecha                 timestamptz not null default now(),
  categoria             text not null check (categoria in ('reinversion','ahorro','personal')),
  concepto              text not null,
  valor                 integer not null check (valor >= 0),
  producto_relacionado  text,
  created_at            timestamptz not null default now()
);

-- CAPITAL_MOVIMIENTOS (ledger, nunca se reescribe un saldo)
create table capital_movimientos (
  id         uuid primary key default gen_random_uuid(),
  fecha      timestamptz not null default now(),
  tipo       text not null check (tipo in ('ingreso','egreso')),
  categoria  text not null check (categoria in ('reinversion','ahorro','personal')),
  valor      integer not null check (valor >= 0),
  concepto   text,
  venta_id   uuid references ventas(id) on delete set null,
  gasto_id   uuid references gastos(id) on delete set null,
  created_at timestamptz not null default now()
);

-- DEUDA_MOVIMIENTOS
create table deuda_movimientos (
  id                     uuid primary key default gen_random_uuid(),
  deudor_id              uuid not null references deudores(id) on delete cascade,
  fecha                  timestamptz not null default now(),
  tipo                   text not null check (tipo in ('cargo','abono')),
  valor                  integer not null check (valor >= 0),
  venta_id               uuid references ventas(id) on delete set null,
  capital_movimiento_id  uuid references capital_movimientos(id) on delete set null,
  created_at             timestamptz not null default now()
);

-- APP_USUARIOS: allow-list de las 2 cuentas autorizadas
create table app_usuarios (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Índices útiles
create index if not exists idx_ventas_fecha   on ventas(fecha);
create index if not exists idx_capital_fecha  on capital_movimientos(fecha);
create index if not exists idx_gastos_fecha   on gastos(fecha);

-- ============================================================
-- 2) FUNCIÓN AUXILIAR de autorización (solo las 2 cuentas)
--    SECURITY DEFINER => revisa la allow-list sin bloquearse por RLS
--    set search_path = '' y referencias calificadas por seguridad
-- ============================================================
create or replace function public.edella_es_usuario_autorizado()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.app_usuarios
    where public.app_usuarios.user_id = auth.uid()
  );
$$;

-- ============================================================
-- 3) ROW LEVEL SECURITY (todas las tablas)
--    SELECT / INSERT / UPDATE / DELETE SOLO si es una de las 2 cuentas
-- ============================================================

alter table productos           enable row level security;
alter table promociones         enable row level security;
alter table promocion_productos enable row level security;
alter table ventas              enable row level security;
alter table venta_items         enable row level security;
alter table capital_movimientos enable row level security;
alter table gastos              enable row level security;
alter table deudores            enable row level security;
alter table deuda_movimientos   enable row level security;
alter table app_usuarios        enable row level security;

-- PRODUCTOS
create policy productos_select_auth on productos for select using (public.edella_es_usuario_autorizado());
create policy productos_insert_auth on productos for insert with check (public.edella_es_usuario_autorizado());
create policy productos_update_auth on productos for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy productos_delete_auth on productos for delete using (public.edella_es_usuario_autorizado());

-- PROMOCIONES
create policy promociones_select_auth on promociones for select using (public.edella_es_usuario_autorizado());
create policy promociones_insert_auth on promociones for insert with check (public.edella_es_usuario_autorizado());
create policy promociones_update_auth on promociones for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy promociones_delete_auth on promociones for delete using (public.edella_es_usuario_autorizado());

-- PROMOCION_PRODUCTOS
create policy promocion_productos_select_auth on promocion_productos for select using (public.edella_es_usuario_autorizado());
create policy promocion_productos_insert_auth on promocion_productos for insert with check (public.edella_es_usuario_autorizado());
create policy promocion_productos_update_auth on promocion_productos for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy promocion_productos_delete_auth on promocion_productos for delete using (public.edella_es_usuario_autorizado());

-- VENTAS
create policy ventas_select_auth on ventas for select using (public.edella_es_usuario_autorizado());
create policy ventas_insert_auth on ventas for insert with check (public.edella_es_usuario_autorizado());
create policy ventas_update_auth on ventas for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy ventas_delete_auth on ventas for delete using (public.edella_es_usuario_autorizado());

-- VENTA_ITEMS
create policy venta_items_select_auth on venta_items for select using (public.edella_es_usuario_autorizado());
create policy venta_items_insert_auth on venta_items for insert with check (public.edella_es_usuario_autorizado());
create policy venta_items_update_auth on venta_items for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy venta_items_delete_auth on venta_items for delete using (public.edella_es_usuario_autorizado());

-- CAPITAL_MOVIMIENTOS
create policy capital_movimientos_select_auth on capital_movimientos for select using (public.edella_es_usuario_autorizado());
create policy capital_movimientos_insert_auth on capital_movimientos for insert with check (public.edella_es_usuario_autorizado());
create policy capital_movimientos_update_auth on capital_movimientos for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy capital_movimientos_delete_auth on capital_movimientos for delete using (public.edella_es_usuario_autorizado());

-- GASTOS
create policy gastos_select_auth on gastos for select using (public.edella_es_usuario_autorizado());
create policy gastos_insert_auth on gastos for insert with check (public.edella_es_usuario_autorizado());
create policy gastos_update_auth on gastos for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy gastos_delete_auth on gastos for delete using (public.edella_es_usuario_autorizado());

-- DEUDORES
create policy deudores_select_auth on deudores for select using (public.edella_es_usuario_autorizado());
create policy deudores_insert_auth on deudores for insert with check (public.edella_es_usuario_autorizado());
create policy deudores_update_auth on deudores for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy deudores_delete_auth on deudores for delete using (public.edella_es_usuario_autorizado());

-- DEUDA_MOVIMIENTOS
create policy deuda_movimientos_select_auth on deuda_movimientos for select using (public.edella_es_usuario_autorizado());
create policy deuda_movimientos_insert_auth on deuda_movimientos for insert with check (public.edella_es_usuario_autorizado());
create policy deuda_movimientos_update_auth on deuda_movimientos for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy deuda_movimientos_delete_auth on deuda_movimientos for delete using (public.edella_es_usuario_autorizado());

-- APP_USUARIOS: los usuarios pueden LEER la lista, pero nadie puede escribirla.
-- Sin policies de INSERT/UPDATE/DELETE => solo postgres / service_role manipulan la allow-list.
create policy app_usuarios_select_auth on app_usuarios for select using (public.edella_es_usuario_autorizado());

-- ============================================================
-- 4) POBLAR LA ALLOW-LIST (2 cuentas autorizadas de Edella SweetAdmin)
-- ============================================================
insert into app_usuarios (user_id) values
  ('f06e169b-67e0-4361-a957-253a6f971630'),
  ('aca965c5-9a55-4ebb-b19b-543c3e57f73a');