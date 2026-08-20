import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import { BOLSILLOS } from '../../lib/financiero'

const MESES = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
]

export default function Dashboard() {
  const [ventas, setVentas] = useState([])
  const [gastos, setGastos] = useState([])
  const [capital, setCapital] = useState([])
  const [deudaMovs, setDeudaMovs] = useState([])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)
  const [mes, setMes] = useState(String(new Date().getMonth() + 1)) // '1'..'12'

  async function cargar() {
    setCargando(true)
    setError(null)
    try {
      const [v, g, c, d] = await Promise.all([
        supabase.from('ventas').select('fecha, tipo, estado_pago, total, venta_items(producto_id, cantidad, origen, precio_unitario, productos(nombre)), venta_promociones(promocion_id, cantidad, precio_unitario, detalles, promociones(nombre))'),
        supabase.from('gastos').select('fecha, categoria, valor, gasto_items(concepto, valor, producto_relacionado)'),
        supabase.from('capital_movimientos').select('fecha, tipo, categoria, valor'),
        supabase.from('deuda_movimientos').select('fecha, tipo, valor, deudores(nombre)'),
      ])
      if (v.error) throw v.error
      if (g.error) throw g.error
      if (c.error) throw c.error
      if (d.error) throw d.error
      setVentas(v.data || [])
      setGastos(g.data || [])
      setCapital(c.data || [])
      setDeudaMovs(d.data || [])
    } catch (e) {
      setError(e.message)
    }
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  const enMes = (fechaStr) => {
    const f = new Date(fechaStr)
    if (mes === 'todos') return true
    return f.getMonth() + 1 === Number(mes)
  }

  const datos = useMemo(() => {
    const ventasMes = ventas.filter((v) => enMes(v.fecha))
    const gastosMes = gastos.filter((g) => enMes(g.fecha))
    const capitalMes = capital.filter((c) => enMes(c.fecha))
    const deudaMes = deudaMovs.filter((d) => enMes(d.fecha))

    // Ventas por producto (individual + desglose de promos). El precio de los
    // items de promo ya viene repartido = valorPromo / totalUnidades.
    const porProducto = {}
    for (const v of ventasMes) {
      for (const it of v.venta_items || []) {
        const nombre = it.productos?.nombre || 'Producto'
        const key = it.producto_id
        if (!porProducto[key]) porProducto[key] = { nombre, cantidad: 0, venta: 0 }
        porProducto[key].cantidad += it.cantidad
        porProducto[key].venta += it.cantidad * it.precio_unitario
      }
    }
    const topProductos = Object.values(porProducto).sort((a, b) => b.cantidad - a.cantidad)

    // Comparativa de promociones vendidas
    const porPromo = {}
    for (const v of ventasMes) {
      for (const p of v.venta_promociones || []) {
        const nombre = p.promociones?.nombre || 'Promoción'
        const key = p.promocion_id
        if (!porPromo[key]) porPromo[key] = { nombre, cantidad: 0, venta: 0 }
        porPromo[key].cantidad += p.cantidad
        porPromo[key].venta += p.cantidad * p.precio_unitario
      }
    }
    const comparativaPromos = Object.values(porPromo).sort((a, b) => b.venta - a.venta)

    // Gastos por concepto (desglosado)
    const porGasto = {}
    for (const g of gastosMes) {
      for (const l of g.gasto_items || []) {
        const key = l.concepto.trim().toLowerCase()
        if (!porGasto[key]) porGasto[key] = { concepto: l.concepto.trim(), valor: 0, categoria: g.categoria }
        porGasto[key].valor += l.valor
      }
    }
    const topGastos = Object.values(porGasto).sort((a, b) => b.valor - a.valor)

    // Resumen 60/20/20 (movimientos de capital del mes)
    const bolsillos = { reinversion: 0, ahorro: 0, personal: 0 }
    for (const m of capitalMes) {
      const delta = m.tipo === 'ingreso' ? m.valor : -m.valor
      bolsillos[m.categoria] = (bolsillos[m.categoria] || 0) + delta
    }

    const totalVentas = ventasMes.reduce((s, v) => s + v.total, 0)
    const totalGastos = gastosMes.reduce((s, g) => s + g.valor, 0)

    // Deudores del mes
    const porDeudor = {}
    for (const d of deudaMes) {
      const nombre = d.deudores?.nombre || 'Deudor'
      if (!porDeudor[nombre]) porDeudor[nombre] = 0
      porDeudor[nombre] += d.tipo === 'cargo' ? d.valor : -d.valor
    }

    return {
      topProductos,
      comparativaPromos,
      topGastos,
      bolsillos,
      totalVentas,
      totalGastos,
      porDeudor,
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ventas, gastos, capital, deudaMovs, mes])

  const totalCapital = BOLSILLOS.reduce((s, b) => s + (datos.bolsillos[b] || 0), 0)
  const luego = totalCapital + datos.totalVentas

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Dashboard</h2>
        <select value={mes} onChange={(e) => setMes(e.target.value)}>
          <option value="todos">Acumulado (todos)</option>
          {MESES.map((m, i) => (
            <option key={i + 1} value={String(i + 1)}>
              {m}
            </option>
          ))}
        </select>
      </header>

      {error && <p className="error">{error}</p>}
      {cargando && <p>Cargando...</p>}

      {!cargando && (
        <>
          <div className="capital-resumen">
            <div className="capital-tarjeta">
              <span className="capital-bolsillo">Vendido</span>
              <strong>{formatoCOP(datos.totalVentas)}</strong>
            </div>
            <div className="capital-tarjeta">
              <span className="capital-bolsillo">Gastado</span>
              <strong>{formatoCOP(datos.totalGastos)}</strong>
            </div>
            <div className="capital-tarjeta capital-total">
              <span className="capital-bolsillo">Neto</span>
              <strong>{formatoCOP(luego)}</strong>
            </div>
            {BOLSILLOS.map((b) => (
              <div key={b} className="capital-tarjeta">
                <span className="capital-bolsillo">{b}</span>
                <strong>{formatoCOP(datos.bolsillos[b] || 0)}</strong>
              </div>
            ))}
            <div className="capital-tarjeta capital-total">
              <span className="capital-bolsillo">Total capital</span>
              <strong>{formatoCOP(totalCapital)}</strong>
            </div>
          </div>

          <div className="grid-dash grid-graf">
            <div className="tarjeta-dash">
              <h3>Ventas por producto</h3>
              <div className="barras">
                {datos.topProductos.slice(0, 6).map((p) => (
                  <div key={'bar-' + p.nombre} className="barra-fila">
                    <span className="barra-nombre" title={p.nombre}>{p.nombre}</span>
                    <div className="barra-track">
                      <div
                        className="barra-valor"
                        style={{
                          width: (p.cantidad / (datos.topProductos[0]?.cantidad || 1)) * 100 + '%',
                        }}
                      />
                    </div>
                    <span className="barra-monto">{p.cantidad}</span>
                  </div>
                ))}
              </div>
            </div>

            <div className="tarjeta-dash">
              <h3>Gastos por concepto</h3>
              <div className="barras">
                {datos.topGastos.slice(0, 6).map((g) => (
                  <div key={'bar-' + g.concepto} className="barra-fila">
                    <span className="barra-nombre" title={g.concepto}>{g.concepto}</span>
                    <div className="barra-track">
                      <div
                        className="barra-valor"
                        style={{
                          width: (g.valor / (datos.topGastos[0]?.valor || 1)) * 100 + '%',
                        }}
                      />
                    </div>
                    <span className="barra-monto">{formatoCOP(g.valor)}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          <div className="grid-dash">
            <div className="tarjeta-dash">
              <h3>Top productos más vendidos</h3>
              <table className="tabla">
                <thead>
                  <tr><th>Producto</th><th>Cantidad</th><th>Venta</th></tr>
                </thead>
                <tbody>
                  {datos.topProductos.length === 0 && (
                    <tr><td colSpan="3">Sin ventas.</td></tr>
                  )}
                  {datos.topProductos.slice(0, 15).map((p) => (
                    <tr key={p.nombre}>
                      <td>{p.nombre}</td>
                      <td>{p.cantidad}</td>
                      <td>{formatoCOP(p.venta)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="tarjeta-dash">
              <h3>Comparativa de promociones</h3>
              <table className="tabla">
                <thead>
                  <tr><th>Promoción</th><th>Cantidad</th><th>Venta</th></tr>
                </thead>
                <tbody>
                  {datos.comparativaPromos.length === 0 && (
                    <tr><td colSpan="3">Sin promociones.</td></tr>
                  )}
                  {datos.comparativaPromos.slice(0, 15).map((p) => (
                    <tr key={p.nombre}>
                      <td>{p.nombre}</td>
                      <td>{p.cantidad}</td>
                      <td>{formatoCOP(p.venta)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="tarjeta-dash">
              <h3>Top gastos</h3>
              <table className="tabla">
                <thead>
                  <tr><th>Concepto</th><th>Categoría</th><th>Valor</th></tr>
                </thead>
                <tbody>
                  {datos.topGastos.length === 0 && (
                    <tr><td colSpan="3">Sin gastos.</td></tr>
                  )}
                  {datos.topGastos.slice(0, 15).map((g) => (
                    <tr key={g.concepto}>
                      <td>{g.concepto}</td>
                      <td>{g.categoria}</td>
                      <td>{formatoCOP(g.valor)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="tarjeta-dash">
              <h3>Deudores del periodo</h3>
              <table className="tabla">
                <thead>
                  <tr><th>Deudor</th><th>Saldo neto</th></tr>
                </thead>
                <tbody>
                  {Object.keys(datos.porDeudor).length === 0 && (
                    <tr><td colSpan="2">Sin movimientos de deuda.</td></tr>
                  )}
                  {Object.entries(datos.porDeudor).map(([nombre, saldo]) => (
                    <tr key={nombre}>
                      <td>{nombre}</td>
                      <td>{formatoCOP(saldo)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </section>
  )
}