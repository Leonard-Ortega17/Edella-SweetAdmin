import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import { BOLSILLOS } from '../../lib/financiero'

export default function Capital() {
  const [movimientos, setMovimientos] = useState([])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)

  async function cargar() {
    setCargando(true)
    setError(null)
    const { data, error: err } = await supabase
      .from('capital_movimientos')
      .select('*')
      .order('fecha', { ascending: false })
      .limit(200)
    if (err) {
      setError(err.message)
    } else {
      setMovimientos(data || [])
    }
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  function saldos() {
    const s = { reinversion: 0, ahorro: 0, personal: 0 }
    for (const m of movimientos) {
      const delta = m.tipo === 'ingreso' ? m.valor : -m.valor
      s[m.categoria] = (s[m.categoria] || 0) + delta
    }
    return s
  }

  const totales = saldos()
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
              <span className="capital-bolsillo">{b}</span>
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