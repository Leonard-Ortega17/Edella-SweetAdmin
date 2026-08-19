-- ============================================================
-- EDALLA SWEETADMIN — MIGRACIÓN FASE 5
-- 1) Columna venta_items.sabor: permite contar ventas por
--    "producto + sabor" (p.ej. 'pave de klim', 'cheescake de nutella')
--    en el dashboard de productos más vendidos.
-- 2) FIX de las RPC registrar_venta() y registrar_gasto():
--    corrige el error `record "r" has no field "item"` generado por
--    `select * from jsonb_array_elements(...)` -> ahora usa
--    `select jsonb_array_elements(...) item`.
-- 3) registrar_venta() ahora persiste `sabor` en venta_items.
-- Aplicar UNA VEZ en Supabase SQL Editor (con backup previo).
-- ============================================================

-- ============================================================
-- 1) venta_items: columna sabor (opcional, texto libre por venta)
-- ============================================================
alter table venta_items add column sabor text;

-- ============================================================
-- 2) RPC registrar_venta() — REWRITE COMPLETO
--    * Fix jsonb_array_elements (línea `item` en el SELECT).
--    * Guarda sabor en cada venta_item (productos individuales y
--      los del desglose de promociones con origen='promocion').
--    * Lógica monetaria 60/20/20, recibido, deuda y promociones SIN cambio.
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
    insert into public.venta_items (venta_id, producto_id, cantidad, precio_unitario, origen, sabor)
    values (
      v_venta_id,
      (r.item->>'producto_id')::uuid,
      (r.item->>'cantidad')::integer,
      (r.item->>'precio_unitario')::integer,
      coalesce(r.item->>'origen', 'individual'),
      nullif(trim(coalesce(r.item->>'sabor', '')), '')
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
    -- Al usar a un deudor en una nueva venta a crédito se reactiva (estaba
    -- inactivo por haber saldado su deuda anterior). Se conserva en BD.
    update public.deudores
    set activo = true
    where public.deudores.id = p_deudor_id;

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
-- 3) RPC registrar_gasto() — REWRITE (solo el fix jsonb_array_elements)
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
    -- El encabezado (gastos.concepto y capital) es genérico cuando hay varias
    -- líneas; cada línea se conserva desglosada en gasto_items con su precio.
    if jsonb_array_length(p_items) > 1 then
      v_concepto_cabecera := 'Compra múltiple';
    elsif v_concepto_cabecera is null then
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

grant execute on function public.registrar_gasto(text, text, integer, text, timestamptz, jsonb) to authenticated;

-- ============================================================
-- 4) RPC registrar_abono() — REWRITE
--    Mantiene 60/20/20 sobre el abono. Al llegar el saldo a 0,
--    el deudor pasa a inactivo (pero NO se borra; queda disponible
--    para reutilizarse y la RPC registrar_venta lo reactiva).
-- ============================================================
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
  v_deudor_nombre text;
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

  select nombre into v_deudor_nombre from public.deudores
  where public.deudores.id = p_deudor_id;

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
  values (p_fecha, 'ingreso', 'reinversion', v_reinv, 'Abono deuda: ' || v_deudor_nombre, now());
  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
  values (p_fecha, 'ingreso', 'ahorro', v_ahor, 'Abono deuda: ' || v_deudor_nombre, now());
  insert into public.capital_movimientos (fecha, tipo, categoria, valor, concepto, created_at)
  values (p_fecha, 'ingreso', 'personal', v_pers, 'Abono deuda: ' || v_deudor_nombre, now());

  -- Si la deuda quedó saldada (saldo 0), el deudor se desactiva.
  if v_saldo - p_valor <= 0 then
    update public.deudores set activo = false where public.deudores.id = p_deudor_id;
  end if;

  return v_id;
end;
$$;

grant execute on function public.registrar_abono(uuid, integer, timestamptz) to authenticated;