import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import { BOLSILLOS, calcularSaldos } from '../../lib/financiero'

export default function Capital() {
  const [movimientos, setMovimientos] = useState([])
  const [totales, setTotales] = useState({ reinversion: 0, ahorro: 0, personal: 0 })
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)

  async function cargar() {
    setCargando(true)
    setError(null)
    try {
      const [recientes, todos] = await Promise.all([
        supabase
          .from('capital_movimientos')
          .select('*')
          .order('fecha', { ascending: false })
          .limit(200),
        supabase.from('capital_movimientos').select('tipo, categoria, valor'),
      ])
      if (recientes.error) throw recientes.error
      if (todos.error) throw todos.error
      setMovimientos(recientes.data || [])
      setTotales(calcularSaldos(todos.data || []))
    } catch (e) {
      setError(e.message)
    }
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  const totalCapital = BOLSILLOS.reduce((acc, b) => acc + (totales[b] || 0), 0)

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Capital</h2>
      </header>

      {error && <p className="error">{error}</p>}
      {cargando && <p>Cargando...</p>}

      {!cargando && (
        <div className="capital-resumen">
          {BOLSILLOS.map((b) => (
            <div key={b} className="capital-tarjeta">
              <span className="capital-bolsillo">{b} (acumulado)</span>
              <strong>{formatoCOP(totales[b] || 0)}</strong>
            </div>
          ))}
          <div className="capital-tarjeta capital-total">
            <span className="capital-bolsillo">Total</span>
            <strong>{formatoCOP(totalCapital)}</strong>
          </div>
        </div>
      )}

      {!cargando && (
        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Tipo</th>
                <th>Bolsillo</th>
                <th>Concepto</th>
                <th>Valor</th>
              </tr>
            </thead>
            <tbody>
              {movimientos.length === 0 && (
                <tr>
                  <td colSpan="5">Sin movimientos.</td>
                </tr>
              )}
              {movimientos.map((m) => (
                <tr key={m.id}>
                  <td>{new Date(m.fecha).toLocaleDateString('es-CO')}</td>
                  <td>{m.tipo}</td>
                  <td>{m.categoria}</td>
                  <td>{m.concepto || '-'}</td>
                  <td>{formatoCOP(m.valor)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}