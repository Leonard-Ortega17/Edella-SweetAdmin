import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import ProductoBuscador from '../ProductoBuscador'

export default function PromocionForm({ promocion, productosIniciales, onGuardar, onCancelar }) {
  const [nombre, setNombre] = useState(promocion?.nombre || '')
  const [descripcion, setDescripcion] = useState(promocion?.descripcion || '')
  const [precioPromo, setPrecioPromo] = useState(promocion?.precio_promo ?? '')
  const [activa, setActiva] = useState(promocion?.activa ?? true)
  const [tipo, setTipo] = useState(promocion?.tipo || 'fija')
  const [pagoCantidad, setPagoCantidad] = useState(promocion?.pago_cantidad ?? 2)
  const [regaloCantidad, setRegaloCantidad] = useState(promocion?.regalo_cantidad ?? 1)
  const [pagoCategoria, setPagoCategoria] = useState(promocion?.pago_categoria_id || '')
  const [regaloCategoria, setRegaloCategoria] = useState(promocion?.regalo_categoria_id || '')
  const [categorias, setCategorias] = useState([])
  const [items, setItems] = useState(productosIniciales || [])
  const [error, setError] = useState(null)

  useEffect(() => {
    supabase
      .from('categorias')
      .select('id, nombre')
      .order('nombre')
      .then(({ data }) => setCategorias(data || []))
  }, [])

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
    if (tipo === 'regalo') {
      if (!pagoCategoria)
        return 'Selecciona la categoría de los productos que se PAGAN.'
      if (!regaloCategoria)
        return 'Selecciona la categoría de los productos que se REGALAN.'
      if (!Number(pagoCantidad) || Number(pagoCantidad) < 1)
        return 'La cantidad de productos pagados debe ser al menos 1.'
      if (!Number(regaloCantidad) || Number(regaloCantidad) < 1)
        return 'La cantidad de productos regalados debe ser al menos 1.'
      return null
    }
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
    const esRegalo = tipo === 'regalo'
    onGuardar({
      nombre: nombre.trim(),
      descripcion: descripcion.trim(),
      activa: activa,
      tipo: tipo,
      // Una promo de regalo no tiene precio fijo: el total de la venta lo
      // define la suma de los productos pagados que se elijan en la venta.
      precio_promo: esRegalo ? 0 : Number(precioPromo),
      pago_cantidad: esRegalo ? Number(pagoCantidad) : 1,
      regalo_cantidad: esRegalo ? Number(regaloCantidad) : 1,
      pago_categoria_id: esRegalo && pagoCategoria ? pagoCategoria : null,
      regalo_categoria_id: esRegalo && regaloCategoria ? regaloCategoria : null,
      items: esRegalo
        ? []
        : items.map((i) => ({
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
          Tipo de promoción
          <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
            <option value="fija">Precio fijo</option>
            <option value="regalo">Regalo y gratis (sin precio fijo)</option>
          </select>
        </label>

        {tipo === 'fija' && (
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
        )}

        {tipo === 'regalo' && (
          <div className="campo-seccion">
            <h3>Composición de la promoción</h3>
            <p className="promo-vacio">
              Sin precio fijo: el total de la venta es la suma de los productos
              pagados elegidos (+ propina). Los productos regalados valen $0.
            </p>
            <label>
              Compras
              <div className="nueva-categoria">
                <input
                  type="number"
                  min="1"
                  step="1"
                  value={pagoCantidad}
                  onChange={(e) => setPagoCantidad(e.target.value)}
                  aria-label="Cantidad pagada"
                />
                <span>unidad(es) de la categoría</span>
                <select
                  value={pagoCategoria}
                  onChange={(e) => setPagoCategoria(e.target.value)}
                  required
                >
                  <option value="">Selecciona...</option>
                  {categorias.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nombre}
                    </option>
                  ))}
                </select>
              </div>
            </label>
            <label>
              Regalas
              <div className="nueva-categoria">
                <input
                  type="number"
                  min="1"
                  step="1"
                  value={regaloCantidad}
                  onChange={(e) => setRegaloCantidad(e.target.value)}
                  aria-label="Cantidad regalada"
                />
                <span>unidad(es) de la categoría</span>
                <select
                  value={regaloCategoria}
                  onChange={(e) => setRegaloCategoria(e.target.value)}
                  required
                >
                  <option value="">Selecciona...</option>
                  {categorias.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nombre}
                    </option>
                  ))}
                </select>
              </div>
            </label>
            <p className="promo-vacio">
              Ejemplo: compras 2 de "pave" y regalas 1 de "pave". Al registrar
              una venta eliges esos productos buscando por nombre dentro de
              cada categoría.
            </p>
          </div>
        )}

        <label className="check-row">
          <input
            type="checkbox"
            checked={activa}
            onChange={(e) => setActiva(e.target.checked)}
          />
          Activa
        </label>

        {tipo === 'fija' && (
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
        )}

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
