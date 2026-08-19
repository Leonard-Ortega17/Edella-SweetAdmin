-- ============================================================
-- EDALLA SWEETADMIN — MIGRACIÓN FASE 4
-- 1) Detalles de promociones (venta_promociones.detalles jsonb).
-- 2) Gastos múltiples: gastos = cabecera de operación + tabla gasto_items.
-- 3) Backfill NO destructivo de gastos existentes -> 1 item por gasto.
-- Aplicar UNA VEZ en Supabase SQL Editor (con backup previo).
-- ============================================================

-- ============================================================
-- 1) VENTA_PROMOCIONES: columna `detalles` (snapshot congelado de la venta)
--    JSONB flexible: array por unidad o null si no hay detalles.
--    No toca filas existentes (quedan en null).
-- ============================================================
alter table venta_promociones add column detalles jsonb;

-- ============================================================
-- 2) NUEVA TABLA: gasto_items (conceptos de una operación de gasto)
--    gastos pasa a ser la CABECERA de la operación (total = SUM(items)).
-- ============================================================
create table gasto_items (
  id                   uuid primary key default extensions.gen_random_uuid(),
  gasto_id             uuid not null references gastos(id) on delete cascade,
  concepto             text not null,
  valor                integer not null check (valor >= 0),
  producto_relacionado text,
  created_at           timestamptz not null default now()
);

create index if not exists idx_gasto_items_gasto_id on gasto_items(gasto_id);

-- ============================================================
-- 3) RLS + POLICIES de gasto_items (misma allow-list)
-- ============================================================
alter table gasto_items enable row level security;

create policy gasto_items_select_auth on gasto_items for select using (public.edella_es_usuario_autorizado());
create policy gasto_items_insert_auth on gasto_items for insert with check (public.edella_es_usuario_autorizado());
create policy gasto_items_update_auth on gasto_items for update using (public.edella_es_usuario_autorizado()) with check (public.edella_es_usuario_autorizado());
create policy gasto_items_delete_auth on gasto_items for delete using (public.edella_es_usuario_autorizado());

grant select, insert, update, delete on gasto_items to authenticated;

-- ============================================================
-- 4) BACKFILL NO DESTRUCTIVO: cada gasto existente -> 1 gasto_item.
--    No borra ni altera gastos, ni recalcula capital.
--    gastos.valor ya era el total; lo conserva como cabecera.
-- ============================================================
insert into gasto_items (gasto_id, concepto, valor, producto_relacionado, created_at)
select g.id, g.concepto, g.valor, g.producto_relacionado, g.created_at
from gastos g
where not exists (
  select 1 from gasto_items gi where gi.gasto_id = g.id
);

-- ============================================================
-- 5) RPC registrar_venta() — extendida con `detalles` de promociones.
--    La lógica monetaria (p_total, 60/20/20, deuda, recibido,
--    validaciones financieras) NO cambia.
--    SECURITY DEFINER + search_path='' + allow-list se mantienen.
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

  -- 3) Promociones de la venta (con `detalles` opcional congelado en la venta)
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

  -- 4) Capital 60/20/20 SOLO sobre dinero recibido
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

grant execute on function public.registrar_venta(integer, text, text, integer, uuid, text, timestamptz, text, integer, jsonb, jsonb) to authenticated;

-- ============================================================
-- 6) RPC registrar_gasto() — extendida con `p_items jsonb`.
--    Cada línea es independiente: el "concepto general" ya no existe;
--    la cabecera de `gastos` usa el concepto de la primera línea.
--    Línea única (retrocompatible) o múltiples conceptos:
--      -> cabecera en gastos (total = SUM(items.valor))
--      -> gasto_items por concepto
--      -> UN único egreso de capital por el total
--    Atómico: si algo falla, no queda nada registrado.
--    IMPORTANTE: eliminamos el overload antiguo de 5 argumentos para
--    evitar funciones duplicadas/ambigüedad; solo queda UNA firma.
-- ============================================================
drop function if exists public.registrar_gasto(text, text, integer, text, timestamptz);

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
    -- El concepto de cabecera usa el de la primera línea; si no, uno genérico.
    if v_concepto_cabecera is null then
      v_concepto_cabecera := 'Compra';
    end if;
  else
    -- Línea única (retrocompatible con el comportamiento anterior)
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

  -- UN único egreso de capital por el total de la operación
  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, gasto_id, created_at)
  values (p_fecha, 'egreso', p_categoria, v_total, v_concepto_cabecera, v_gasto_id, now());

  return v_gasto_id;
end;
$$;

grant execute on function public.registrar_gasto(text, text, integer, text, timestamptz, jsonb) to authenticated;