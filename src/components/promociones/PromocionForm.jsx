import { useState } from 'react'
import ProductoBuscador from '../ProductoBuscador'

export default function PromocionForm({ promocion, productosIniciales, onGuardar, onCancelar }) {
  const [nombre, setNombre] = useState(promocion?.nombre || '')
  const [descripcion, setDescripcion] = useState(promocion?.descripcion || '')
  const [precioPromo, setPrecioPromo] = useState(promocion?.precio_promo ?? '')
  const [activa, setActiva] = useState(promocion?.activa ?? true)
  const [items, setItems] = useState(productosIniciales || [])
  const [error, setError] = useState(null)

  function agregarProducto(producto) {
    if (items.some((i) => i.producto_id === producto.id)) {
      setError('Ese producto ya está en la promoción.')
      return
    }
    setError(null)
    setItems((prev) => [
      ...prev,
      { producto_id: producto.id, producto_nombre: producto.nombre, cantidad: 1 },
    ])
  }

  function cambiarCantidad(productoId, valor) {
    setItems((prev) =>
      prev.map((i) =>
        i.producto_id === productoId ? { ...i, cantidad: Number(valor) } : i
      )
    )
  }

  function quitarProducto(productoId) {
    setItems((prev) => prev.filter((i) => i.producto_id !== productoId))
  }

  function validar() {
    if (!nombre.trim()) return 'El nombre es obligatorio.'
    if (precioPromo === '' || Number(precioPromo) < 0)
      return 'El precio de la promoción no puede ser negativo.'
    if (items.length > 0 && items.some((i) => !i.cantidad || i.cantidad <= 0))
      return 'La cantidad de cada producto debe ser mayor que 0.'
    // Sin duplicados
    if (new Set(items.map((i) => i.producto_id)).size !== items.length)
      return 'Un producto no puede repetirse en la promoción.'
    return null
  }

  function handleSubmit(event) {
    event.preventDefault()
    const err = validar()
    if (err) {
      setError(err)
      return
    }
    setError(null)
    onGuardar({
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      precio_promo: Number(precioPromo),
      activa: activa,
      items: items.map((i) => ({
        producto_id: i.producto_id,
        cantidad: i.cantidad,
      })),
    })
  }

  return (
    <div className="modal-overlay">
      <form className="modal modal-largo" onSubmit={handleSubmit}>
        <h2>{promocion ? 'Editar promoción' : 'Nueva promoción'}</h2>

        <label>
          Nombre
          <input
            type="text"
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
            required
          />
        </label>

        <label>
          Descripción
          <textarea
            value={descripcion}
            onChange={(e) => setDescripcion(e.target.value)}
            rows="2"
          />
        </label>

        <label>
          Precio promoción (COP)
          <input
            type="number"
            min="0"
            step="1"
            value={precioPromo}
            onChange={(e) => setPrecioPromo(e.target.value)}
            required
          />
        </label>

        <label className="check-row">
          <input
            type="checkbox"
            checked={activa}
            onChange={(e) => setActiva(e.target.checked)}
          />
          Activa
        </label>

        <div className="promo-productos">
          <h3>Productos de la promoción</h3>
          <ProductoBuscador
            onSeleccionar={agregarProducto}
            soloActivos
            excluirIds={items.map((i) => i.producto_id)}
            placeholder="Agregar producto (autocompletado)..."
          />

          {items.length === 0 && (
            <p className="promo-vacio">
              Opcional: los productos de la promoción se seleccionan en el momento de la venta.
            </p>
          )}

          {items.length > 0 && (
            <ul className="promo-lista">
              {items.map((i) => (
                <li key={i.producto_id} className="promo-item">
                  <span className="promo-nombre">{i.producto_nombre}</span>
                  <input
                    type="number"
                    min="1"
                    step="1"
                    value={i.cantidad}
                    onChange={(e) => cambiarCantidad(i.producto_id, e.target.value)}
                    className="promo-cantidad"
                    aria-label={`Cantidad de ${i.producto_nombre}`}
                  />
                  <button
                    type="button"
                    className="btn-secundario"
                    onClick={() => quitarProducto(i.producto_id)}
                  >
                    Quitar
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {error && <p className="error">{error}</p>}

        <div className="modal-acciones">
          <button type="button" className="btn-secundario" onClick={onCancelar}>
            Cancelar
          </button>
          <button type="submit">Guardar</button>
        </div>
      </form>
    </div>
  )
}