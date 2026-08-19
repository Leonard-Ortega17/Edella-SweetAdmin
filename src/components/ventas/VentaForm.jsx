import { useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import {
  METODOS_PAGO,
  redimensionarDetalles,
  normalizarDetallesParaEnviar,
  articulosDeUnidad,
} from '../../lib/financiero'
import ProductoBuscador from '../ProductoBuscador'

let contadorInstancia = 0
function nuevoIdInstancia() {
  contadorInstancia += 1
  return `promo-${contadorInstancia}`
}

export default function VentaForm({ onGuardada, onCancelar }) {
  const [items, setItems] = useState([])
  const [promos, setPromos] = useState([])
  const [composiciones, setComposiciones] = useState({})
  const [promosDisponibles, setPromosDisponibles] = useState([])
  const [deudores, setDeudores] = useState([])
  const [propina, setPropina] = useState('')
  const [metodoPago, setMetodoPago] = useState('efectivo')
  const [cliente, setCliente] = useState('')
  const [deudorId, setDeudorId] = useState('')
  const [nuevoDeudor, setNuevoDeudor] = useState('')
  const [pagoInicial, setPagoInicial] = useState('')
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)
  const [promoAgregar, setPromoAgregar] = useState('')
  const seleccionPrevia = useRef('')

  const esCredito = metodoPago === 'credito'

  useEffect(() => {
    supabase.from('promociones').select('*').eq('activa', true).order('nombre').then(
      ({ data, error }) => {
        if (!error) setPromosDisponibles(data || [])
      }
    )
    // Se cargan TODOS los deudores (activos e inactivos) para poder reutilizar
    // a un deudor saldado en una nueva venta a crédito; la RPC lo reactiva.
    supabase.from('deudores').select('*').order('nombre').then(
      ({ data, error }) => {
        if (!error) setDeudores(data || [])
      }
    )
  }, [])

  // REGLA DE NEGOCIO (estructura, no filtro):
  // `items` contiene SOLO productos agregados manualmente por el usuario y
  // son la ÚNICA fuente de dinero por producto. Los productos de una promoción
  // viven en `composiciones` y se vuelcan SOLO a `construirDesglose()` con
  // origen='promocion' (dato/estadística). Por construcción, el desglose
  // NUNCA está en `items`, así que nunca puede sumar al total ni cobrarse
  // dos veces. `ventas.total` es siempre la fuente autoritativa de dinero.
  function subtotalMonetario() {
    return items.reduce((s, i) => s + i.cantidad * i.precio_unitario, 0)
  }
  function subtotalPromos() {
    return promos.reduce((s, p) => s + p.cantidad * p.precio_unitario, 0)
  }
  function totalVenta() {
    return subtotalMonetario() + subtotalPromos() + (Number(propina) || 0)
  }

  function agregarProducto(producto) {
    setItems((prev) => {
      const existente = prev.find((i) => i.producto_id === producto.id)
      if (existente) {
        return prev.map((i) =>
          i.producto_id === producto.id ? { ...i, cantidad: i.cantidad + 1 } : i
        )
      }
      return [
        ...prev,
        {
          producto_id: producto.id,
          nombre: producto.nombre,
          cantidad: 1,
          precio_unitario: producto.precio_base,
          origen: 'individual',
        },
      ]
    })
  }

  function cambiarCantidadItem(productoId, valor) {
    setItems((prev) =>
      prev.map((i) =>
        i.producto_id === productoId ? { ...i, cantidad: Number(valor) } : i
      )
    )
  }
  function quitarItem(productoId) {
    setItems((prev) => prev.filter((i) => i.producto_id !== productoId))
  }

  async function agregarPromocion(promocionId) {
    if (!promocionId) return
    const promo = promosDisponibles.find((p) => p.id === promocionId)
    if (!promo) return

    const { data, error: err } = await supabase
      .from('promocion_productos')
      .select('producto_id, cantidad, productos(nombre, precio_base)')
      .eq('promocion_id', promocionId)
    if (err) {
      setError('No se pudieron cargar los productos de la promoción: ' + err.message)
      return
    }

    setError(null)
    // Cada instancia de promoción es independiente: puede agregarse varias veces
    // y cada una conserva su propio id y sus propios detalles.
    setPromos((prev) => [
      ...prev,
      {
        id: nuevoIdInstancia(),
        promocion_id: promo.id,
        nombre: promo.nombre,
        cantidad: 1,
        precio_unitario: promo.precio_promo,
        detalles: [],
      },
    ])
    setComposiciones((prev) => ({
      ...prev,
      [promocionId]: (data || []).map((r) => ({
        producto_id: r.producto_id,
        nombre: r.productos?.nombre || 'Producto',
        cantidad_por_promo: r.cantidad,
        precio_unitario: r.productos?.precio_base || 0,
      })),
    }))
    setPromoAgregar('')
  }

  function actualizarPromo(id, fn) {
    setPromos((prev) => prev.map((p) => (p.id === id ? fn(p) : p)))
  }

  function cambiarCantidadPromo(id, valor) {
    actualizarPromo(id, (p) => ({
      ...p,
      cantidad: Number(valor),
      detalles: redimensionarDetalles(p.detalles, Number(valor)),
    }))
  }

  function quitarPromo(id) {
    setPromos((prev) => prev.filter((p) => p.id !== id))
  }

  // Detalles por unidad: lista de productos seleccionados (sin sabor ni valor).
  function agregarArticulo(id, indice) {
    actualizarPromo(id, (p) => {
      const detalles = Array.isArray(p.detalles) ? p.detalles.slice() : []
      while (detalles.length <= indice) detalles.push([])
      const unidad = Array.isArray(detalles[indice]) ? detalles[indice].slice() : []
      unidad.push({ producto_id: '', nombre: '' })
      detalles[indice] = unidad
      return { ...p, detalles }
    })
  }

  function seleccionarArticulo(id, indice, pos, producto) {
    actualizarPromo(id, (p) => {
      const detalles = Array.isArray(p.detalles) ? p.detalles.slice() : []
      while (detalles.length <= indice) detalles.push([])
      const unidad = (Array.isArray(detalles[indice]) ? detalles[indice] : []).map(
        (a, i) =>
          i === pos ? { ...a, producto_id: producto.id, nombre: producto.nombre } : a
      )
      detalles[indice] = unidad
      return { ...p, detalles }
    })
  }

  function quitarArticulo(id, indice, pos) {
    actualizarPromo(id, (p) => {
      const detalles = Array.isArray(p.detalles) ? p.detalles.slice() : []
      while (detalles.length <= indice) detalles.push([])
      const unidad = Array.isArray(detalles[indice]) ? detalles[indice].slice() : []
      unidad.splice(pos, 1)
      detalles[indice] = unidad
      return { ...p, detalles }
    })
  }

  function limpiarArticulo(id, indice, pos) {
    actualizarPromo(id, (p) => {
      const detalles = Array.isArray(p.detalles) ? p.detalles.slice() : []
      while (detalles.length <= indice) detalles.push([])
      const unidad = (Array.isArray(detalles[indice]) ? detalles[indice] : []).map(
        (a, i) => (i === pos ? { ...a, producto_id: '', nombre: '' } : a)
      )
      detalles[indice] = unidad
      return { ...p, detalles }
    })
  }

  // Desglose por producto (origen='promocion') generado desde los detalles
  // elegidos en cada unidad: cada artículo {producto_id, nombre} de una unidad
  // produce una fila de venta_items, alimentando el "productos mas vendidos".
  // Regla de reparto: el valor total de cada promo (precio_unitario * cantidad)
  // se divide en partes iguales entre TODAS las unidades de producto que la
  // promo aporta, de modo que en el dashboard la ganancia de la promo quede
  // repartida igualmente entre sus productos (ej. promo $20.000 de 2 sabores
  // con 1 unidad cada uno -> $10.000 por producto).
  function construirDesglose() {
    const desglose = []
    for (const promo of promos) {
      const comp = composiciones[promo.promocion_id] || []
      const unidades = Array.isArray(promo.detalles) ? promo.detalles : []
      const tieneDetalles = unidades.some(
        (u) => Array.isArray(u) && u.some((a) => a && a.producto_id)
      )

      const filas = []
      if (tieneDetalles) {
        for (const unidad of unidades) {
          if (!Array.isArray(unidad)) continue
          for (const a of unidad) {
            if (!a || !a.producto_id) continue
            const base = comp.find((c) => c.producto_id === a.producto_id)
            filas.push({
              producto_id: a.producto_id,
              cantidad: 1,
              base: base ? base.precio_unitario : 0,
            })
          }
        }
      } else {
        for (const c of comp) {
          filas.push({
            producto_id: c.producto_id,
            cantidad: promo.cantidad * c.cantidad_por_promo,
            base: c.precio_unitario,
          })
        }
      }

      if (filas.length === 0) continue

      const totalUnidades = filas.reduce((s, f) => s + f.cantidad, 0)
      const valorPromo = (promo.precio_unitario || 0) * (promo.cantidad || 1)
      // Precio unitario repartido: cada unidad de producto vale lo mismo.
      const precioRepartido =
        totalUnidades > 0 ? Math.floor(valorPromo / totalUnidades) : 0

      for (const f of filas) {
        desglose.push({
          producto_id: f.producto_id,
          cantidad: f.cantidad,
          precio_unitario: precioRepartido,
          origen: 'promocion',
        })
      }
    }
    return desglose
  }

  function validar() {
    if (items.length === 0 && promos.length === 0)
      return 'La venta debe tener al menos un producto o una promoción.'
    if (esCredito && !deudorId && !nuevoDeudor.trim())
      return 'Para una venta a crédito debes seleccionar o crear un deudor.'
    if (esCredito) {
      const inicial = Number(pagoInicial) || 0
      if (inicial < 0 || inicial > totalVenta())
        return 'El pago inicial no puede ser negativo ni superar el total.'
    }
    return null
  }

  async function crearDeudorSiNecesario() {
    if (deudorId) return { id: deudorId, error: null }
    const nombre = nuevoDeudor.trim()
    const { data, error } = await supabase
      .from('deudores')
      .insert({ nombre })
      .select()
    if (error) return { id: null, error: error.message }
    return { id: data[0].id, error: null }
  }

  async function handleSubmit(event) {
    event.preventDefault()
    const err = validar()
    if (err) {
      setError(err)
      return
    }
    setError(null)
    setCargando(true)

    let deudor = null
    if (esCredito) {
      deudor = await crearDeudorSiNecesario()
      if (deudor.error) {
        setCargando(false)
        setError('No se pudo crear el deudor: ' + deudor.error)
        return
      }
    }

    const p_items_items = items.map((i) => ({
      producto_id: i.producto_id,
      cantidad: i.cantidad,
      precio_unitario: i.precio_unitario,
      origen: 'individual',
    }))
    const p_items_desglose = construirDesglose()
    const p_items = [...p_items_items, ...p_items_desglose]

    const p_promos = promos.map((p) => ({
      promocion_id: p.promocion_id,
      cantidad: p.cantidad,
      precio_unitario: p.precio_unitario,
      detalles: normalizarDetallesParaEnviar(p.detalles),
    }))

    let p_recibido = null
    if (esCredito) {
      p_recibido = Number(pagoInicial) || 0
    }

    const { data: ventaId, error: rpcError } = await supabase.rpc(
      'registrar_venta',
      {
        p_total: totalVenta(),
        p_metodo_pago: metodoPago,
        p_estado_pago: esCredito ? 'credito' : 'pagado',
        p_recibido: esCredito ? p_recibido : null,
        p_deudor_id: esCredito ? deudor.id : null,
        p_cliente_nombre: cliente.trim() || null,
        p_tipo: promos.length > 0 ? 'promocion' : 'normal',
        p_propina: Number(propina) || 0,
        p_items,
        p_promos,
      }
    )

    setCargando(false)
    if (rpcError) {
      setError('No se pudo registrar la venta: ' + rpcError.message)
      return
    }
    onGuardada(ventaId)
  }

  function handleSelectPromo(value) {
    // Evitar doble disparo del onChange del <select> al resetear el valor.
    if (value === seleccionPrevia.current) {
      setPromoAgregar('')
      return
    }
    seleccionPrevia.current = value
    agregarPromocion(value)
  }

  return (
    <div className="modal-overlay">
      <form className="modal modal-largo" onSubmit={handleSubmit}>
        <h2>Nueva venta</h2>

        <div className="campo-seccion">
          <h3>Productos</h3>
          <ProductoBuscador
            onSeleccionar={agregarProducto}
            excluirIds={items.map((i) => i.producto_id)}
            placeholder="Agregar producto (autocompletado)..."
          />
          {items.length === 0 && <p className="promo-vacio">Sin productos individuales.</p>}
          {items.length > 0 && (
            <ul className="promo-lista">
              {items.map((i) => (
                <li key={i.producto_id} className="promo-item">
                  <span className="promo-nombre">{i.nombre}</span>
                  <input
                    type="number"
                    min="1"
                    step="1"
                    value={i.cantidad}
                    onChange={(e) => cambiarCantidadItem(i.producto_id, e.target.value)}
                    className="promo-cantidad"
                  />
                  <button
                    type="button"
                    className="btn-secundario"
                    onClick={() => quitarItem(i.producto_id)}
                  >
                    Quitar
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="campo-seccion">
          <h3>Promociones</h3>
          <select value={promoAgregar} onChange={(e) => handleSelectPromo(e.target.value)}>
            <option value="">Selecciona una promoción...</option>
            {promosDisponibles.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombre} ({formatoCOP(p.precio_promo)})
              </option>
            ))}
          </select>
          {promos.length === 0 && <p className="promo-vacio">Sin promociones en la venta.</p>}
          {promos.length > 0 && (
            <ul className="promo-lista">
              {promos.map((p, idx) => (
                <li key={p.id} className="promo-item promo-item-columna">
                  <div className="promo-fila">
                    <span className="promo-nombre">
                      {p.nombre} ({formatoCOP(p.precio_unitario)}){promos.length > 1 ? ` — #${idx + 1}` : ''}
                    </span>
                    <input
                      type="number"
                      min="1"
                      step="1"
                      value={p.cantidad}
                      onChange={(e) => cambiarCantidadPromo(p.id, e.target.value)}
                      className="promo-cantidad"
                    />
                    <button
                      type="button"
                      className="btn-secundario"
                      onClick={() => quitarPromo(p.id)}
                    >
                      Quitar
                    </button>
                  </div>
                  <PromoDetalles
                    promoId={p.id}
                    cantidad={p.cantidad}
                    detalles={p.detalles}
                    onAgregarArticulo={agregarArticulo}
                    onSeleccionarArticulo={seleccionarArticulo}
                    onLimpiarArticulo={limpiarArticulo}
                    onQuitarArticulo={quitarArticulo}
                  />
                </li>
              ))}
            </ul>
          )}
        </div>

        <label>
          Propina (COP)
          <input
            type="number"
            min="0"
            step="1"
            value={propina}
            onChange={(e) => setPropina(e.target.value)}
          />
        </label>

        <label>
          Cliente (opcional)
          <input
            type="text"
            value={cliente}
            onChange={(e) => setCliente(e.target.value)}
          />
        </label>

        <label>
          Método de pago
          <select value={metodoPago} onChange={(e) => setMetodoPago(e.target.value)}>
            {METODOS_PAGO.map((m) => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
        </label>

        {esCredito && (
          <div className="campo-seccion">
            <h3>Venta a crédito</h3>
            <label>
              Deudor
              <select value={deudorId} onChange={(e) => setDeudorId(e.target.value)}>
                <option value="">Selecciona un deudor...</option>
                {deudores.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.nombre}
                  </option>
                ))}
              </select>
            </label>
            <label>
              O crea uno nuevo
              <input
                type="text"
                value={nuevoDeudor}
                onChange={(e) => setNuevoDeudor(e.target.value)}
                placeholder="Nombre del nuevo deudor"
              />
            </label>
            <label>
              Pago inicial (COP)
              <input
                type="number"
                min="0"
                step="1"
                value={pagoInicial}
                onChange={(e) => setPagoInicial(e.target.value)}
              />
            </label>
          </div>
        )}

        <div className="venta-total">
          <span>Total</span>
          <strong>{formatoCOP(totalVenta())}</strong>
        </div>

        {error && <p className="error">{error}</p>}

        <div className="modal-acciones">
          <button type="button" className="btn-secundario" onClick={onCancelar}>
            Cancelar
          </button>
          <button type="submit" disabled={cargando}>
            {cargando ? 'Registrando...' : 'Confirmar venta'}
          </button>
        </div>
      </form>
    </div>
  )
}

// Editor de detalles por unidad: cada unidad selecciona uno o más productos
// con autocompletado. No hay "sabor" ni "valor": el precio de la promoción
// ya quedó fijado al agregarla. El producto elegido se conserva visible.
function PromoDetalles({
  promoId,
  cantidad,
  detalles,
  onAgregarArticulo,
  onSeleccionarArticulo,
  onLimpiarArticulo,
  onQuitarArticulo,
}) {
  const n = Number(cantidad) || 0
  if (n <= 0) return null

  const unidades = Array.from({ length: n }, (_, i) => i)

  return (
    <div className="promo-detalles">
      {unidades.map((indice) => {
        const articulos = articulosDeUnidad(detalles, indice)
        return (
          <div key={indice} className="promo-detalle-unidad">
            <span className="promo-detalle-titulo">Unidad {indice + 1}</span>
            {articulos.map((a, pos) => (
              <div key={pos} className="promo-detalle-par">
                {a.producto_id ? (
                  <>
                    <span className="promo-detalle-elegido">{a.nombre || 'Producto'}</span>
                    <button
                      type="button"
                      className="btn-secundario"
                      onClick={() => onLimpiarArticulo(promoId, indice, pos)}
                    >
                      Cambiar
                    </button>
                  </>
                ) : (
                  <ProductoBuscador
                    onSeleccionar={(producto) =>
                      onSeleccionarArticulo(promoId, indice, pos, producto)
                    }
                    soloActivos
                    placeholder="Seleccionar producto..."
                  />
                )}
                <button
                  type="button"
                  className="btn-secundario"
                  onClick={() => onQuitarArticulo(promoId, indice, pos)}
                >
                  Quitar
                </button>
              </div>
            ))}
            <button
              type="button"
              className="btn-secundario"
              onClick={() => onAgregarArticulo(promoId, indice)}
            >
              + Agregar artículo
            </button>
          </div>
        )
      })}
    </div>
  )
}
