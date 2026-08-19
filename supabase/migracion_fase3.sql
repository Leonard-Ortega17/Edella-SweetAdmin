-- ============================================================
-- EDALLA SWEETADMIN — MIGRACIÓN FASE 3
-- Ventas + ingresos + egresos + capital + deudas.
-- -> Conserva datos históricos.
-- -> Añade método/estado de pago, venta_items con id propio
--    (soporta multi-promo y doble registro), tabla venta_promociones,
--    y RPCs atómicas (SECURITY DEFINER + search_path='').
-- Aplicar UNA VEZ en Supabase SQL Editor.
-- ============================================================

-- ============================================================
-- 1) VENTAS: método y estado de pago + cliente opcional
--    (se migran después las filas históricas tipo='deuda')
-- ============================================================
alter table ventas add column metodo_pago text not null default 'efectivo'
  check (metodo_pago in ('efectivo','transferencia','nequi','daviplata','otro','credito'));

alter table ventas add column estado_pago text not null default 'pagado'
  check (estado_pago in ('pagado','credito'));

alter table ventas add column cliente_nombre text;

-- Conservar el significado histórico: las ventas de crédito marcadas
-- en la columna legacy `tipo='deuda'` pasan a estado/método 'credito'.
update ventas
set estado_pago = 'credito', metodo_pago = 'credito'
where tipo = 'deuda';

-- ============================================================
-- 2) VENTA_ITEMS: id propio (PK nueva) + columna origen
--    Backfill seguro para registros existentes antes de cambiar la PK.
-- ============================================================
alter table venta_items add column id uuid;

-- Todos los registros existentes reciben su uuid antes de NO en blanco/PK
update venta_items set id = public.gen_random_uuid() where id is null;

alter table venta_items alter column id set not null;
alter table venta_items alter column id set default public.gen_random_uuid();

alter table venta_items add column origen text not null default 'individual'
  check (origen in ('individual','promocion'));

-- Cambiar la PK compuesta -> PK en id (permite doble registro multi-promo)
alter table venta_items drop constraint venta_items_pkey;
alter table venta_items add primary key (id);

-- ============================================================
-- 3) NUEVA TABLA: venta_promociones (una venta puede tener varias promos)
-- ============================================================
create table venta_promociones (
  id              uuid primary key default public.gen_random_uuid(),
  venta_id        uuid not null references ventas(id) on delete cascade,
  promocion_id    uuid not null references promociones(id) on delete restrict,
  cantidad        integer not null default 1 check (cantidad > 0),
  precio_unitario integer not null check (precio_unitario >= 0),
  created_at      timestamptz not null default now()
);

-- ============================================================
-- 4) ÍNDICES (apoyo a ventas, stats y abonos)
-- ============================================================
create index if not exists idx_venta_items_venta_id on venta_items(venta_id);
create index if not exists idx_venta_promociones_venta_id on venta_promociones(venta_id);
create index if not exists idx_deuda_movimientos_deudor_id on deuda_movimientos(deudor_id);

-- ============================================================
-- 5) RLS + GRANTS de la nueva tabla (misma allow-list)
-- ============================================================
alter table venta_promociones enable row level security;

grant select, insert, update, delete on venta_promociones to authenticated;

create policy venta_promociones_select_auth on venta_promociones for select using (public.edella_es_usuario_autorizado());
create policy venta_promociones_insert_auth on venta_promociones for insert with check (public.edella_es_usuario_autorizado());
create policy venta_promociones_update_auth on venta_promociones for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy venta_promociones_delete_auth on venta_promociones for delete using (public.edella_es_usuario_autorizado());

-- ============================================================
-- 6) RPCs ATÓMICAS (SECURITY DEFINER + search_path seguro)
--    La autorización se valida explícitamente con edella_es_usuario_autorizado().
-- ============================================================

-- Registrar una venta de una operación completa.
-- p_recibido: dinero efectivamente recibido. Si viene NULL, se asume = p_total.
--  - capital (60/20/20) SOLO sobre p_recibido.
--  - si es crédito (p_estado_pago='credito') y hay deudor:
--    se crea un cargo en deuda_movimientos por (p_total - p_recibido).
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

  -- 1) Venta
  insert into public.ventas (fecha, tipo, propina, total, promocion_id, deudor_id, metodo_pago, estado_pago, cliente_nombre, created_at)
  values (p_fecha, p_tipo, coalesce(p_propina, 0), p_total, null, p_deudor_id, p_metodo_pago, p_estado_pago, p_cliente_nombre, now())
  returning id into v_venta_id;

  -- 2) Items (productos, incluye desglose de promociones con origen='promocion')
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

  -- 3) Promociones de la venta
  for r in select jsonb_array_elements(coalesce(p_promos, '[]'::jsonb)) item loop
    if (r.item->>'cantidad')::integer <= 0 then
      raise exception 'Cantidad de promocion invalida.';
    end if;
    if (r.item->>'precio_unitario')::integer < 0 then
      raise exception 'Precio unitario de promocion invalido.';
    end if;
    insert into public.venta_promociones (venta_id, promocion_id, cantidad, precio_unitario)
    values (
      v_venta_id,
      (r.item->>'promocion_id')::uuid,
      (r.item->>'cantidad')::integer,
      (r.item->>'precio_unitario')::integer
    );
  end loop;

  -- 4) Capital 60/20/20 SOLO sobre dinero recibido
  if v_recibido > 0 then
    v_reinv := (v_recibido * 3) / 5;      -- 60%
    v_ahor  := v_recibido / 5;            -- 20%
    v_pers  := v_recibido - v_reinv - v_ahor; -- 20% (resto, suma exacta)

    insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, venta_id, created_at)
    values (p_fecha, 'ingreso', 'reinversion', v_reinv, 'Venta', v_venta_id, now());
    insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, venta_id, created_at)
    values (p_fecha, 'ingreso', 'ahorro', v_ahor, 'Venta', v_venta_id, now());
    insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, venta_id, created_at)
    values (p_fecha, 'ingreso', 'personal', v_pers, 'Venta', v_venta_id, now());
  end if;

  -- 5) Deuda cargo (si es crédito y hay saldo pendiente)
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

-- Registrar un abono de deuda: abono + capital 60/20/20 sobre el valor.
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

  -- El deudor debe existir
  if not exists (select 1 from public.deudores where public.deudores.id = p_deudor_id) then
    raise exception 'El deudor no existe.';
  end if;

  -- Saldo pendiente = SUM(cargo) - SUM(abono) (nunca almacenado)
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

-- Registrar un gasto: egreso de capital en el bolsillo de su categoría.
create or replace function public.registrar_gasto(
  p_categoria text,
  p_concepto text,
  p_valor integer,
  p_producto_relacionado text default null,
  p_fecha timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gasto_id uuid;
begin
  if not public.edella_es_usuario_autorizado() then
    raise exception 'Acceso denegado: usuario no autorizado.';
  end if;

  if p_valor is null or p_valor <= 0 then
    raise exception 'El valor del gasto debe ser mayor que 0.';
  end if;
  if p_categoria is null or p_categoria not in ('reinversion', 'ahorro', 'personal') then
    raise exception 'Categoria de gasto invalida.';
  end if;
  if p_concepto is null or trim(p_concepto) = '' then
    raise exception 'El concepto es obligatorio.';
  end if;

  insert into public.gastos (fecha, categoria, concepto, valor, producto_relacionado, created_at)
  values (p_fecha, p_categoria, p_concepto, p_valor, p_producto_relacionado, now())
  returning id into v_gasto_id;

  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, gasto_id, created_at)
  values (p_fecha, 'egreso', p_categoria, p_valor, p_concepto, v_gasto_id, now());

  return v_gasto_id;
end;
$$;

-- ============================================================
-- 7) GRANTS EXECUTE de las RPCs (SOLO authenticated)
-- ============================================================
grant execute on function public.registrar_venta(integer, text, text, integer, uuid, text, timestamptz, text, integer, jsonb, jsonb) to authenticated;
grant execute on function public.registrar_abono(uuid, integer, timestamptz) to authenticated;
grant execute on function public.registrar_gasto(text, text, integer, text, timestamptz) to authenticated;