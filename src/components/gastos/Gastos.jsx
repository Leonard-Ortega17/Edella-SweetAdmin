import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import GastoForm from './GastoForm'

export default function Gastos() {
  const [gastos, setGastos] = useState([])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)
  const [mostrarForm, setMostrarForm] = useState(false)
  const [desplegado, setDesplegado] = useState(null)

  async function cargar() {
    setCargando(true)
    setError(null)
    const { data, error: err } = await supabase
      .from('gastos')
      .select('*, gasto_items(*)')
      .order('fecha', { ascending: false })
      .limit(100)
    if (err) {
      setError(err.message)
    } else {
      setGastos(data || [])
    }
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  async function confirmarGuardado() {
    setMostrarForm(false)
    await cargar()
  }

  function alternar(gastoId) {
    setDesplegado((actual) => (actual === gastoId ? null : gastoId))
  }

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Gastos</h2>
        <button onClick={() => setMostrarForm(true)}>Nuevo gasto</button>
      </header>

      {error && <p className="error">{error}</p>}
      {cargando && <p>Cargando...</p>}

      {!cargando && (
        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Concepto</th>
                <th>Categoría</th>
                <th>Total</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {gastos.length === 0 && (
                <tr>
                  <td colSpan="5">Sin gastos.</td>
                </tr>
              )}
              {gastos.map((g) => (
                <GastoFila
                  key={g.id}
                  gasto={g}
                  desplegado={desplegado === g.id}
                  onAlternar={() => alternar(g.id)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {mostrarForm && (
        <GastoForm
          onGuardado={confirmarGuardado}
          onCancelar={() => setMostrarForm(false)}
        />
      )}
    </section>
  )
}

function GastoFila({ gasto, desplegado, onAlternar }) {
  const lineas = gasto.gasto_items || []
  return (
    <>
      <tr className={desplegado ? 'fila-desplegada' : ''}>
        <td>{new Date(gasto.fecha).toLocaleDateString('es-CO')}</td>
        <td>{gasto.concepto}</td>
        <td>{gasto.categoria}</td>
        <td>{formatoCOP(gasto.valor)}</td>
        <td>
          <button type="button" className="btn-secundario" onClick={onAlternar}>
            {desplegado ? 'Ocultar' : 'Ver líneas'}
          </button>
        </td>
      </tr>
      {desplegado && (
        <tr>
          <td colSpan="5">
            <ul className="promo-lista">
              {lineas.length === 0 && <li className="promo-vacio">Sin líneas.</li>}
              {lineas.map((l) => (
                <li key={l.id} className="promo-item">
                  <span className="promo-nombre">
                    {l.concepto}
                    {l.producto_relacionado
                      ? ` — ${l.producto_relacionado}`
                      : ''}
                  </span>
                  <strong>{formatoCOP(l.valor)}</strong>
                </li>
              ))}
            </ul>
          </td>
        </tr>
      )}
    </>
  )
}
