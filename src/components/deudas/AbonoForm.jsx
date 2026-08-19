import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'

export default function AbonoForm({ deudor, saldar = false, onHecho, onCancelar }) {
  const [valor, setValor] = useState(saldar ? deudor.saldo : '')
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)

  function validar() {
    if (valor === '' || Number(valor) <= 0)
      return 'El abono debe ser mayor que 0.'
    if (Number(valor) > deudor.saldo)
      return 'El abono no puede superar el saldo pendiente.'
    return null
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

    const { error: rpcError } = await supabase.rpc('registrar_abono', {
      p_deudor_id: deudor.id,
      p_valor: Number(valor),
    })

    setCargando(false)
    if (rpcError) {
      setError('No se pudo registrar el abono: ' + rpcError.message)
      return
    }
    onHecho()
  }

  return (
    <div className="modal-overlay">
      <form className="modal" onSubmit={handleSubmit}>
        <h2>{saldar ? `Saldar deuda — ${deudor.nombre}` : `Abono — ${deudor.nombre}`}</h2>
        <p className="promo-vacio">
          Saldo pendiente: <strong>{formatoCOP(deudor.saldo)}</strong>
        </p>

        <label>
          {saldar
            ? `Valor para saldar (COP) — equivale a todo el saldo`
            : 'Valor del abono (COP)'}
          <input
            type="number"
            min="1"
            step="1"
            value={valor}
            onChange={(e) => setValor(e.target.value)}
            required
          />
        </label>

        {error && <p className="error">{error}</p>}

        <div className="modal-acciones">
          <button type="button" className="btn-secundario" onClick={onCancelar}>
            Cancelar
          </button>
          <button type="submit" disabled={cargando}>
            {cargando ? 'Registrando...' : saldar ? 'Confirmar saldo' : 'Registrar abono'}
          </button>
        </div>
      </form>
    </div>
  )
}