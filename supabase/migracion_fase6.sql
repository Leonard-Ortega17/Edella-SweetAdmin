-- ============================================================
-- EDELLA SWEETADMIN — MIGRACIÓN FASE 6
-- Nuevo reparto de ingresos: 75% Reinversión / 10% Ahorro / 15% Personal
-- (antes 60/20/20). Aplica SOLO a ventas y abonos NUEVOS; los saldos
-- ya registrados no se recalculan.
--
-- Cambia las funciones:
--   registrar_venta():  reparto 60/20/20 -> 75/10/15 sobre lo recibido
--   registrar_abono():  reparto 60/20/20 -> 75/10/15 sobre el abono
--
-- Fórmula con enteros (suma EXACTA, sin decimales):
--   reinversion = valor * 3 / 4            -> 75%
--   ahorro      = valor / 10               -> 10%
--   personal    = valor - reinv - ahorro   -> resto (aprox. 15%), suma exacta
--
-- El resto de la lógica (recibido, deuda, promociones, gastos) NO cambia.
-- Aplicar UNA VEZ en Supabase SQL Editor (con backup previo).
-- ============================================================

-- ============================================================
-- 1) RPC registrar_venta() — reparto 75/10/15
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
    v_reinv := (v_recibido * 3) / 4;          -- 75%
    v_ahor  := v_recibido / 10;               -- 10%
    v_pers  := v_recibido - v_reinv - v_ahor; -- 15% (resto, suma exacta)

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
-- 2) RPC registrar_abono() — reparto 75/10/15
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

  v_reinv := (p_valor * 3) / 4;          -- 75%
  v_ahor  := p_valor / 10;               -- 10%
  v_pers  := p_valor - v_reinv - v_ahor; -- 15% (resto, suma exacta)

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