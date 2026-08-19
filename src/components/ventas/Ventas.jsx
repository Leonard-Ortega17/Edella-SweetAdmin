import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import VentaForm from './VentaForm'

export default function Ventas() {
  const [ventas, setVentas] = useState([])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)
  const [mostrarForm, setMostrarForm] = useState(false)
  const [desplegado, setDesplegado] = useState(null)

  async function cargar() {
    setCargando(true)
    setError(null)
    const { data, error: err } = await supabase
      .from('ventas')
      .select(
        '*, deudores(nombre), venta_items(productos(nombre), cantidad, origen, precio_unitario), venta_promociones(promociones(nombre), cantidad, precio_unitario, detalles)'
      )
      .order('fecha', { ascending: false })
      .limit(100)
    if (err) {
      setError(err.message)
    } else {
      setVentas(data || [])
    }
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  async function confirmarGuardada() {
    setMostrarForm(false)
    await cargar()
  }

  function alternar(ventaId) {
    setDesplegado((actual) => (actual === ventaId ? null : ventaId))
  }

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Ventas</h2>
        <button onClick={() => setMostrarForm(true)}>Nueva venta</button>
      </header>

      {error && <p className="error">{error}</p>}
      {cargando && <p>Cargando...</p>}

      {!cargando && (
        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Detalle</th>
                <th>Cliente</th>
                <th>Método</th>
                <th>Total</th>
                <th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {ventas.length === 0 && (
                <tr>
                  <td colSpan="6">Sin ventas.</td>
                </tr>
              )}
              {ventas.map((v) => (
                <VentaFila
                  key={v.id}
                  venta={v}
                  desplegado={desplegado === v.id}
                  onAlternar={() => alternar(v.id)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {mostrarForm && (
        <VentaForm
          onGuardada={confirmarGuardada}
          onCancelar={() => setMostrarForm(false)}
        />
      )}
    </section>
  )
}

function VentaFila({ venta, desplegado, onAlternar }) {
  return (
    <>
      <tr className={desplegado ? 'fila-desplegada' : ''}>
        <td>{new Date(venta.fecha).toLocaleDateString('es-CO')}</td>
        <td>
          {venta.venta_items?.map((it) =>
            `${it.productos?.nombre} x${it.cantidad}${
              it.origen === 'promocion' ? ' (promo)' : ''
            }`
          ).join(', ')}
          {venta.venta_promociones?.map((p) =>
            ` + ${p.promociones?.nombre} x${p.cantidad} (promo)`
          )}
        </td>
        <td>{venta.cliente_nombre || venta.deudores?.nombre || '-'}</td>
        <td>{venta.metodo_pago}</td>
        <td>{formatoCOP(venta.total)}</td>
        <td>
          <div className="acciones">
            <span
              className={
                venta.estado_pago === 'credito' ? 'badge no' : 'badge ok'
              }
            >
              {venta.estado_pago}
            </span>
            <button type="button" className="btn-secundario" onClick={onAlternar}>
              {desplegado ? 'Ocultar' : 'Detalles'}
            </button>
          </div>
        </td>
      </tr>
      {desplegado && (
        <tr>
          <td colSpan="6">
            {Array.isArray(venta.venta_items) && venta.venta_items.length > 0 && (
              <div className="promo-detalle-historial">
                <strong>Productos</strong>
                <ul className="promo-lista">
                  {venta.venta_items.map((it) => (
                    <li key={it.id} className="promo-item">
                      <span className="promo-nombre">
                        {it.productos?.nombre} x{it.cantidad}
                        {it.origen === 'promocion' ? ' (promo)' : ''}
                      </span>
                      <strong>{formatoCOP(it.cantidad * it.precio_unitario)}</strong>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {venta.venta_promociones?.map((p) => (
              <div key={p.id} className="promo-detalle-historial">
                <strong>
                  Promoción: {p.promociones?.nombre} ×{p.cantidad} —{' '}
                  {formatoCOP(p.cantidad * p.precio_unitario)}
                </strong>
                {Array.isArray(p.detalles) && p.detalles.length > 0 && (
                  <ul className="promo-lista">
                    {p.detalles.map((unidad, i) => {
                      const pares = Array.isArray(unidad)
                        ? unidad.filter((x) => x && x.producto_id)
                        : []
                      if (pares.length === 0) return null
                      return (
                        <li key={i} className="promo-item">
                          <span className="promo-nombre">Unidad {i + 1}</span>
                          <span>
                            {pares
                              .map((x) =>
                                x.sabor
                                  ? `${x.nombre || x.producto_id} de ${x.sabor}`
                                  : x.nombre || x.producto_id
                              )
                              .join(', ')}
                          </span>
                        </li>
                      )
                    })}
                  </ul>
                )}
              </div>
            ))}
            {venta.venta_items?.length === 0 && !venta.venta_promociones?.length && (
              <p className="promo-vacio">Sin detalle.</p>
            )}
          </td>
        </tr>
      )}
    </>
  )
}