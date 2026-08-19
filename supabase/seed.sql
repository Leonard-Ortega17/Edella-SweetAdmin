-- ============================================================
-- EDALLA SWEETADMIN — FASE 1: Esquema + RLS (2 cuentas autorizadas)
-- Valores monetarios en pesos colombianos (INTEGER, sin decimales)
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
-- 1) TABLAS (cada FK apunta solo a tablas ya creadas)
-- ============================================================

-- CATEGORIAS (dinámicas)
create table categorias (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null unique,
  activa     boolean not null default true,
  created_at timestamptz not null default now()
);

insert into categorias (nombre) values
  ('cheesecake'), ('pave'), ('ancheta'), ('otro');

-- PRODUCTOS
create table productos (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  categoria_id uuid not null references categorias(id) on delete restrict,
  precio_base integer not null check (precio_base >= 0),
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists idx_productos_categoria_id on productos(categoria_id);

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
  id             uuid primary key default gen_random_uuid(),
  fecha          timestamptz not null default now(),
  tipo           text not null check (tipo in ('normal','promocion','deuda')),
  propina        integer not null default 0 check (propina >= 0),
  total          integer not null check (total >= 0),
  promocion_id   uuid references promociones(id) on delete set null,
  deudor_id      uuid references deudores(id) on delete set null,
  metodo_pago    text not null default 'efectivo'
    check (metodo_pago in ('efectivo','transferencia','nequi','daviplata','otro','credito')),
  estado_pago    text not null default 'pagado'
    check (estado_pago in ('pagado','credito')),
  cliente_nombre text,
  created_at     timestamptz not null default now()
);

-- VENTA_ITEMS (puente) — PK propia permite el doble registro individuo + promo
create table venta_items (
  id              uuid primary key default gen_random_uuid(),
  venta_id        uuid not null references ventas(id) on delete cascade,
  producto_id     uuid not null references productos(id) on delete restrict,
  cantidad        integer not null check (cantidad > 0),
  precio_unitario integer not null check (precio_unitario >= 0),
  origen          text not null default 'individual'
    check (origen in ('individual','promocion'))
);

-- VENTA_PROMOCIONES (una venta puede tener varias promociones)
create table venta_promociones (
  id              uuid primary key default gen_random_uuid(),
  venta_id        uuid not null references ventas(id) on delete cascade,
  promocion_id    uuid not null references promociones(id) on delete restrict,
  cantidad        integer not null default 1 check (cantidad > 0),
  precio_unitario integer not null check (precio_unitario >= 0),
  detalles        jsonb,
  created_at      timestamptz not null default now()
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

-- GASTO_ITEMS (conceptos de una operación de gasto; gastos es la cabecera)
create table gasto_items (
  id                   uuid primary key default gen_random_uuid(),
  gasto_id             uuid not null references gastos(id) on delete cascade,
  concepto             text not null,
  valor                integer not null check (valor >= 0),
  producto_relacionado text,
  created_at           timestamptz not null default now()
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
create index if not exists idx_venta_items_venta_id on venta_items(venta_id);
create index if not exists idx_venta_promociones_venta_id on venta_promociones(venta_id);
create index if not exists idx_deuda_movimientos_deudor_id on deuda_movimientos(deudor_id);
create index if not exists idx_gasto_items_gasto_id on gasto_items(gasto_id);

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

alter table categorias         enable row level security;
alter table productos           enable row level security;
alter table promociones         enable row level security;
alter table promocion_productos enable row level security;
alter table ventas              enable row level security;
alter table venta_items         enable row level security;
alter table venta_promociones   enable row level security;
alter table capital_movimientos enable row level security;
alter table gastos              enable row level security;
alter table gasto_items         enable row level security;
alter table deudores            enable row level security;
alter table deuda_movimientos   enable row level security;
alter table app_usuarios        enable row level security;

-- CATEGORIAS
create policy categorias_select_auth on categorias for select using (public.edella_es_usuario_autorizado());
create policy categorias_insert_auth on categorias for insert with check (public.edella_es_usuario_autorizado());
create policy categorias_update_auth on categorias for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy categorias_delete_auth on categorias for delete using (public.edella_es_usuario_autorizado());

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

-- VENTA_PROMOCIONES
create policy venta_promociones_select_auth on venta_promociones for select using (public.edella_es_usuario_autorizado());
create policy venta_promociones_insert_auth on venta_promociones for insert with check (public.edella_es_usuario_autorizado());
create policy venta_promociones_update_auth on venta_promociones for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy venta_promociones_delete_auth on venta_promociones for delete using (public.edella_es_usuario_autorizado());

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

-- GASTO_ITEMS
create policy gasto_items_select_auth on gasto_items for select using (public.edella_es_usuario_autorizado());
create policy gasto_items_insert_auth on gasto_items for insert with check (public.edella_es_usuario_autorizado());
create policy gasto_items_update_auth on gasto_items for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy gasto_items_delete_auth on gasto_items for delete using (public.edella_es_usuario_autorizado());

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
-- 4) PRIVILEGIOS DE TABLA (obligatorio: sin GRANT, `permission denied`)
--    RLS es una capa que actúa DESPUÉS del permiso de tabla.
--    Se concede al rol `authenticated`; la allow-list la impone RLS
--    (una 3ª cuenta autenticada recibe el GRANT, pero la policy
--     edella_es_usuario_autorizado() le devuelve false => sin acceso).
-- ============================================================

grant usage on schema public to anon, authenticated;

-- Tablas de negocio: CRUD para el rol autenticado
grant select, insert, update, delete
  on productos, categorias, promociones, promocion_productos,
     ventas, venta_items, venta_promociones,
     capital_movimientos, gastos, gasto_items, deudores, deuda_movimientos
  to authenticated;

-- app_usuarios: SOLO lectura para los autorizados.
-- Sin INSERT/UPDATE/DELETE => ningún usuario puede modificar la allow-list.
grant select
  on app_usuarios
  to authenticated;

-- Permitir ejecutar la función de autorización usada por las policies
grant execute on function public.edella_es_usuario_autorizado()
  to anon, authenticated;

-- ============================================================
-- 5) POBLAR LA ALLOW-LIST (2 cuentas autorizadas de Edella SweetAdmin)
-- ============================================================
insert into app_usuarios (user_id) values
  ('f06e169b-67e0-4361-a957-253a6f971630'),
  ('aca965c5-9a55-4ebb-b19b-543c3e57f73a');

-- ============================================================
-- 6) RPCs ATÓMICAS FASE 3 (SECURITY DEFINER + search_path='')
-- ============================================================
create or replace function public.registrar_venta(
  p_total integer,
  p_metodo_pago text default 'efectivo',
  p_estado_pago text default 'pagado',
  p_recibido integer default null,
  p_deudor_id uuid default null,
  p_cliente_nombre text default null,
  p_fecha timestamptz default now(),
  p_tipo text default 'normal',
  p_propina integer default 0,
  p_items jsonb default '[]'::jsonb,
  p_promos jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta_id uuid;
  v_recibido integer;
  r record;
  v_deuda integer;
  v_reinv integer;
  v_ahor integer;
  v_pers integer;
begin
  if not public.edella_es_usuario_autorizado() then
    raise exception 'Acceso denegado: usuario no autorizado.';
  end if;

  -- ---- Validación de entradas (integridad financiera) ----
  if p_total is null or p_total < 0 then
    raise exception 'p_total invalido.';
  end if;
  if p_propina is null or p_propina < 0 then
    raise exception 'p_propina invalida.';
  end if;
  if p_estado_pago is null or p_estado_pago not in ('pagado', 'credito') then
    raise exception 'p_estado_pago invalido.';
  end if;
  if p_metodo_pago is null or p_metodo_pago not in ('efectivo','transferencia','nequi','daviplata','otro','credito') then
    raise exception 'p_metodo_pago invalido.';
  end if;
  if p_tipo is null or p_tipo not in ('normal', 'promocion', 'deuda') then
    raise exception 'p_tipo invalido.';
  end if;

  v_recibido := coalesce(p_recibido, p_total);
  if v_recibido < 0 or v_recibido > p_total then
    raise exception 'p_recibido invalido (0 <= recibido <= total).';
  end if;

  -- Semántica de estado de pago
  if p_estado_pago = 'credito' then
    if p_deudor_id is null then
      raise exception 'Una venta a credito requiere deudor.';
    end if;
    if v_recibido = p_total then
      raise exception 'Una venta a credito no puede quedar totalmente recibida en el momento.';
    end if;
  else
    -- pagado
    if v_recibido <> p_total then
      raise exception 'En una venta pagada el monto recibido debe ser igual al total.';
    end if;
  end if;

  -- Al menos un ítem o una promoción
  if (p_items is null or jsonb_array_length(p_items) = 0)
     and (p_promos is null or jsonb_array_length(p_promos) = 0) then
    raise exception 'La venta debe tener al menos un producto o una promocion.';
  end if;

  insert into public.ventas (fecha, tipo, propina, total, promocion_id, deudor_id, metodo_pago, estado_pago, cliente_nombre, created_at)
  values (p_fecha, p_tipo, coalesce(p_propina, 0), p_total, null, p_deudor_id, p_metodo_pago, p_estado_pago, p_cliente_nombre, now())
  returning id into v_venta_id;

  for r in select jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) item loop
    if (r.item->>'cantidad')::integer <= 0 then
      raise exception 'Cantidad de producto invalida.';
    end if;
    if (r.item->>'precio_unitario')::integer < 0 then
      raise exception 'Precio unitario de producto invalido.';
    end if;
    if coalesce(r.item->>'origen', 'individual') not in ('individual', 'promocion') then
      raise exception 'Origen de item invalido.';
    end if;
    insert into public.venta_items (venta_id, producto_id, cantidad, precio_unitario, origen)
    values (
      v_venta_id,
      (r.item->>'producto_id')::uuid,
      (r.item->>'cantidad')::integer,
      (r.item->>'precio_unitario')::integer,
      coalesce(r.item->>'origen', 'individual')
    );
  end loop;

  for r in select jsonb_array_elements(coalesce(p_promos, '[]'::jsonb)) item loop
    if (r.item->>'cantidad')::integer <= 0 then
      raise exception 'Cantidad de promocion invalida.';
    end if;
    if (r.item->>'precio_unitario')::integer < 0 then
      raise exception 'Precio unitario de promocion invalido.';
    end if;
    insert into public.venta_promociones (venta_id, promocion_id, cantidad, precio_unitario, detalles)
    values (
      v_venta_id,
      (r.item->>'promocion_id')::uuid,
      (r.item->>'cantidad')::integer,
      (r.item->>'precio_unitario')::integer,
      case
        when r.item ? 'detalles' then (r.item->>'detalles')::jsonb
        else null
      end
    );
  end loop;

  if v_recibido > 0 then
    v_reinv := (v_recibido * 3) / 5;
    v_ahor  := v_recibido / 5;
    v_pers  := v_recibido - v_reinv - v_ahor;

    insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, venta_id, created_at)
    values (p_fecha, 'ingreso', 'reinversion', v_reinv, 'Venta', v_venta_id, now());
    insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, venta_id, created_at)
    values (p_fecha, 'ingreso', 'ahorro', v_ahor, 'Venta', v_venta_id, now());
    insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, venta_id, created_at)
    values (p_fecha, 'ingreso', 'personal', v_pers, 'Venta', v_venta_id, now());
  end if;

  if p_estado_pago = 'credito' and p_deudor_id is not null then
    v_deuda := p_total - v_recibido;
    if v_deuda > 0 then
      insert into public.deuda_movimientos (deudor_id, fecha, tipo, valor, venta_id, created_at)
      values (p_deudor_id, p_fecha, 'cargo', v_deuda, v_venta_id, now());
    end if;
  end if;

  return v_venta_id;
end;
$$;

create or replace function public.registrar_abono(
  p_deudor_id uuid,
  p_valor integer,
  p_fecha timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_reinv integer;
  v_ahor integer;
  v_pers integer;
  v_saldo integer;
begin
  if not public.edella_es_usuario_autorizado() then
    raise exception 'Acceso denegado: usuario no autorizado.';
  end if;

  if p_valor is null or p_valor <= 0 then
    raise exception 'El abono debe ser mayor que 0.';
  end if;

  if not exists (select 1 from public.deudores where public.deudores.id = p_deudor_id) then
    raise exception 'El deudor no existe.';
  end if;

  select coalesce(sum(valor), 0) into v_saldo
  from public.deuda_movimientos
  where deudor_id = p_deudor_id
    and tipo = 'cargo';

  select v_saldo - coalesce(sum(valor), 0) into v_saldo
  from public.deuda_movimientos
  where deudor_id = p_deudor_id
    and tipo = 'abono';

  if p_valor > v_saldo then
    raise exception 'El abono no puede superar el saldo pendiente.';
  end if;

  v_reinv := (p_valor * 3) / 5;
  v_ahor  := p_valor / 5;
  v_pers  := p_valor - v_reinv - v_ahor;

  insert into public.deuda_movimientos (deudor_id, fecha, tipo, valor, created_at)
  values (p_deudor_id, p_fecha, 'abono', p_valor, now())
  returning id into v_id;

  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
  values (p_fecha, 'ingreso', 'reinversion', v_reinv, 'Abono deuda', now());
  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
  values (p_fecha, 'ingreso', 'ahorro', v_ahor, 'Abono deuda', now());
  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
  values (p_fecha, 'ingreso', 'personal', v_pers, 'Abono deuda', now());

  return v_id;
end;
$$;

create or replace function public.registrar_gasto(
  p_categoria text,
  p_concepto text,
  p_valor integer,
  p_producto_relacionado text default null,
  p_fecha timestamptz default now(),
  p_items jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gasto_id uuid;
  v_total integer;
  v_concepto_cabecera text;
  r record;
begin
  if not public.edella_es_usuario_autorizado() then
    raise exception 'Acceso denegado: usuario no autorizado.';
  end if;

  if p_categoria is null or p_categoria not in ('reinversion', 'ahorro', 'personal') then
    raise exception 'Categoria de gasto invalida.';
  end if;

  -- Múltiples conceptos
  if p_items is not null and jsonb_array_length(p_items) > 0 then
    v_total := 0;
    v_concepto_cabecera := null;
    for r in select jsonb_array_elements(p_items) item loop
      if r.item->>'concepto' is null or trim(r.item->>'concepto') = '' then
        raise exception 'El concepto de cada linea es obligatorio.';
      end if;
      if (r.item->>'valor')::integer is null or (r.item->>'valor')::integer <= 0 then
        raise exception 'El valor de cada linea debe ser mayor que 0.';
      end if;
      if v_concepto_cabecera is null then
        v_concepto_cabecera := trim(r.item->>'concepto');
      end if;
      v_total := v_total + (r.item->>'valor')::integer;
    end loop;
    if v_total <= 0 then
      raise exception 'El total de la operacion debe ser mayor que 0.';
    end if;
    if v_concepto_cabecera is null then
      v_concepto_cabecera := 'Compra';
    end if;
  else
    if coalesce(trim(p_concepto), '') = '' then
      raise exception 'El concepto es obligatorio.';
    end if;
    if p_valor is null or p_valor <= 0 then
      raise exception 'El valor del gasto debe ser mayor que 0.';
    end if;
    v_total := p_valor;
    v_concepto_cabecera := trim(p_concepto);
  end if;

  insert into public.gastos (fecha, categoria, concepto, valor, producto_relacionado, created_at)
  values (p_fecha, p_categoria, v_concepto_cabecera, v_total, p_producto_relacionado, now())
  returning id into v_gasto_id;

  if p_items is not null and jsonb_array_length(p_items) > 0 then
    for r in select jsonb_array_elements(p_items) item loop
      insert into public.gasto_items (gasto_id, concepto, valor, producto_relacionado, created_at)
      values (
        v_gasto_id,
        r.item->>'concepto',
        (r.item->>'valor')::integer,
        nullif(trim(coalesce(r.item->>'producto_relacionado', '')), ''),
        now()
      );
    end loop;
  else
    insert into public.gasto_items (gasto_id, concepto, valor, producto_relacionado, created_at)
    values (v_gasto_id, p_concepto, p_valor, p_producto_relacionado, now());
  end if;

  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, gasto_id, created_at)
  values (p_fecha, 'egreso', p_categoria, v_total, v_concepto_cabecera, v_gasto_id, now());

  return v_gasto_id;
end;
$$;

grant execute on function public.registrar_venta(integer, text, text, integer, uuid, text, timestamptz, text, integer, jsonb, jsonb) to authenticated;
grant execute on function public.registrar_abono(uuid, integer, timestamptz) to authenticated;
grant execute on function public.registrar_gasto(text, text, integer, text, timestamptz, jsonb) to authenticated;