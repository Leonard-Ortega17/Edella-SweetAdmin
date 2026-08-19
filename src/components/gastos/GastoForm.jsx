import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { CATEGORIAS_GASTO } from '../../lib/financiero'
import { formatoCOP } from '../../lib/formato'
import ProductoBuscador from '../ProductoBuscador'
import ConceptoBuscador from '../ConceptoBuscador'

export default function GastoForm({ onGuardado, onCancelar }) {
  const [categoria, setCategoria] = useState('')
  const [lineas, setLineas] = useState([{ concepto: '', valor: '', producto: null }])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)

  function actualizarLinea(indice, campo, valor) {
    setLineas((prev) =>
      prev.map((l, i) => (i === indice ? { ...l, [campo]: valor } : l))
    )
  }

  function seleccionarProducto(indice, producto) {
    setLineas((prev) =>
      prev.map((l, i) =>
        i === indice
          ? {
              ...l,
              producto: { id: producto.id, nombre: producto.nombre },
            }
          : l
      )
    )
  }

  function limpiarProducto(indice) {
    setLineas((prev) =>
      prev.map((l, i) => (i === indice ? { ...l, producto: null } : l))
    )
  }

  function agregarLinea() {
    setLineas((prev) => [
      ...prev,
      { concepto: '', valor: '', producto: null },
    ])
  }

  function quitarLinea(indice) {
    setLineas((prev) => prev.filter((_, i) => i !== indice))
  }

  function total() {
    return lineas.reduce((s, l) => s + (Number(l.valor) || 0), 0)
  }

  function validar() {
    if (!categoria) return 'La categoría es obligatoria.'
    if (lineas.length === 0) return 'Debe haber al menos una línea.'
    for (const l of lineas) {
      if (!l.concepto.trim()) return 'El concepto de cada línea es obligatorio.'
      if (l.valor === '' || Number(l.valor) <= 0)
        return 'El valor de cada línea debe ser mayor que 0.'
    }
    if (total() <= 0) return 'El total de la operación debe ser mayor que 0.'
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

    const p_items = lineas.map((l) => ({
      concepto: l.concepto.trim(),
      valor: Number(l.valor),
      producto_relacionado: l.producto ? l.producto.nombre : null,
    }))

    const { error: rpcError } = await supabase.rpc('registrar_gasto', {
      p_categoria: categoria,
      p_concepto: '',
      p_valor: total(),
      p_producto_relacionado: null,
      p_items,
    })

    setCargando(false)
    if (rpcError) {
      setError('No se pudo registrar el gasto: ' + rpcError.message)
      return
    }
    onGuardado()
  }

  return (
    <div className="modal-overlay">
      <form className="modal modal-largo" onSubmit={handleSubmit}>
        <h2>Nuevo gasto</h2>

        <label>
          Categoría
          <select
            value={categoria}
            onChange={(e) => setCategoria(e.target.value)}
            required
          >
            <option value="">Selecciona...</option>
            {CATEGORIAS_GASTO.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>

        <div className="campo-seccion">
          <h3>Detalle</h3>
          {lineas.map((l, i) => (
            <div key={i} className="gasto-linea gasto-linea-columna">
              <ConceptoBuscador
                valor={l.concepto}
                placeholder="Concepto"
                onCambio={(v) => actualizarLinea(i, 'concepto', v)}
              />
              <input
                type="number"
                min="1"
                step="1"
                value={l.valor}
                onChange={(e) => actualizarLinea(i, 'valor', e.target.value)}
                placeholder="Valor"
                aria-label={`Valor línea ${i + 1}`}
              />
              {l.producto ? (
                <div className="gasto-relacionado">
                  <span className="promo-detalle-elegido">{l.producto.nombre}</span>
                  <button
                    type="button"
                    className="btn-secundario"
                    onClick={() => limpiarProducto(i)}
                  >
                    Quitar
                  </button>
                </div>
              ) : (
                <ProductoBuscador
                  onSeleccionar={(p) => seleccionarProducto(i, p)}
                  soloActivos
                  placeholder="Producto relacionado..."
                />
              )}
              <button
                type="button"
                className="btn-secundario"
                onClick={() => quitarLinea(i)}
                disabled={lineas.length === 1}
              >
                Quitar
              </button>
            </div>
          ))}
          <button type="button" className="btn-secundario" onClick={agregarLinea}>
            + Agregar concepto
          </button>
        </div>

        <div className="venta-total">
          <span>Total</span>
          <strong>{formatoCOP(total())}</strong>
        </div>

        {error && <p className="error">{error}</p>}

        <div className="modal-acciones">
          <button type="button" className="btn-secundario" onClick={onCancelar}>
            Cancelar
          </button>
          <button type="submit" disabled={cargando}>
            {cargando ? 'Registrando...' : 'Registrar compra'}
          </button>
        </div>
      </form>
    </div>
  )
}