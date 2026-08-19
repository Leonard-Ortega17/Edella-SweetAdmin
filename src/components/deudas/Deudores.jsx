import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import AbonoForm from './AbonoForm'

export default function Deudores() {
  const [deudores, setDeudores] = useState([])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)
  const [showAbono, setShowAbono] = useState(null) // { deudor, saldar? }

  async function cargar() {
    setCargando(true)
    setError(null)
    const { data: deud, error: errD } = await supabase
      .from('deudores')
      .select('*')
      .order('nombre')
    if (errD) {
      setError(errD.message)
      setCargando(false)
      return
    }
    const { data: movs, error: errM } = await supabase
      .from('deuda_movimientos')
      .select('deudor_id, tipo, valor')
    if (errM) {
      setError(errM.message)
      setCargando(false)
      return
    }
    const saldos = {}
    for (const m of movs || []) {
      saldos[m.deudor_id] = (saldos[m.deudor_id] || 0) + (m.tipo === 'cargo' ? m.valor : -m.valor)
    }
    const conSaldo = (deud || []).map((d) => ({
      ...d,
      saldo: saldos[d.id] || 0,
    }))
    setDeudores(conSaldo)
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  async function toggleActivo(d) {
    const { error } = await supabase
      .from('deudores')
      .update({ activo: !d.activo })
      .eq('id', d.id)
    if (error) {
      setError('No se pudo actualizar: ' + error.message)
      return
    }
    setError(null)
    await cargar()
  }

  function abrirAbono(d) {
    setShowAbono({ deudor: d, saldar: false })
  }

  function abrirSaldar(d) {
    setShowAbono({ deudor: d, saldar: true })
  }

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Deudores</h2>
      </header>

      <div className="filtros">
        <p className="promo-vacio">Los deudores se crean automáticamente al registrar una venta a crédito.</p>
      </div>

      {error && <p className="error">{error}</p>}
      {cargando && <p>Cargando...</p>}

      {!cargando && (
        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Saldo pendiente</th>
                <th>Estado</th>
                <th>Acciones</th>
              </tr>
            </thead>
            <tbody>
              {deudores.length === 0 && (
                <tr>
                  <td colSpan="4">Sin deudores.</td>
                </tr>
              )}
              {deudores.map((d) => (
                <tr key={d.id}>
                  <td>{d.nombre}</td>
                  <td>{formatoCOP(d.saldo)}</td>
                  <td>
                    <span className={d.activo ? 'badge ok' : 'badge no'}>
                      {d.activo ? 'Activo' : 'Inactivo'}
                    </span>
                  </td>
                  <td className="acciones">
                    <button
                      type="button"
                      onClick={() => abrirAbono(d)}
                      disabled={d.saldo <= 0}
                    >
                      Abono
                    </button>
                    <button
                      type="button"
                      onClick={() => abrirSaldar(d)}
                      disabled={d.saldo <= 0}
                    >
                      Saldar
                    </button>
                    <button type="button" onClick={() => toggleActivo(d)}>
                      {d.activo ? 'Desactivar' : 'Activar'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showAbono && (
        <AbonoForm
          deudor={showAbono.deudor}
          saldar={showAbono.saldar}
          onHecho={() => {
            setShowAbono(null)
            cargar()
          }}
          onCancelar={() => setShowAbono(null)}
        />
      )}
    </section>
  )
}