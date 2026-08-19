import { useState } from 'react'

const vacio = {
  nombre: '',
  categoria_id: '',
  precio_base: '',
  activo: true,
}

export default function ProductoForm({
  producto,
  categorias,
  onNuevaCategoria,
  onGuardar,
  onCancelar,
}) {
  const [form, setForm] = useState(
    producto ? { ...producto } : { ...vacio }
  )
  const [crearCategoria, setCrearCategoria] = useState(false)
  const [nuevaCategoria, setNuevaCategoria] = useState('')
  const [creando, setCreando] = useState(false)
  const [error, setError] = useState(null)

  function actualizar(campo, valor) {
    setForm((f) => ({ ...f, [campo]: valor }))
  }

  async function guardarNuevaCategoria() {
    const nombre = nuevaCategoria.trim()
    if (!nombre) {
      setError('Escribe un nombre para la nueva categoría.')
      return
    }
    const duplicado = categorias.some(
      (c) => c.nombre.toLowerCase() === nombre.toLowerCase()
    )
    if (duplicado) {
      setError('Esa categoría ya existe.')
      return
    }

    setCreando(true)
    setError(null)
    const resultado = await onNuevaCategoria(nombre)
    setCreando(false)

    if (!resultado.ok) {
      setError(resultado.error)
      return
    }

    setForm((f) => ({ ...f, categoria_id: resultado.categoria.id }))
    setNuevaCategoria('')
    setCrearCategoria(false)
  }

  function validar() {
    if (!form.nombre.trim()) return 'El nombre es obligatorio.'
    if (!form.categoria_id) return 'La categoría es obligatoria.'
    if (form.precio_base === '' || Number(form.precio_base) < 0)
      return 'El precio base no puede ser negativo.'
    return null
  }

  function handleSubmit(event) {
    event.preventDefault()
    if (crearCategoria) {
      setError('Selecciona una categoría o crea y guarda la nueva primero.')
      return
    }
    const err = validar()
    if (err) {
      setError(err)
      return
    }
    setError(null)
    onGuardar({
      nombre: form.nombre.trim(),
      categoria_id: form.categoria_id,
      precio_base: Number(form.precio_base),
      activo: form.activo,
    })
  }

  return (
    <div className="modal-overlay">
      <form className="modal" onSubmit={handleSubmit}>
        <h2>{producto ? 'Editar producto' : 'Nuevo producto'}</h2>

        <label>
          Nombre
          <input
            type="text"
            value={form.nombre}
            onChange={(e) => actualizar('nombre', e.target.value)}
            required
          />
        </label>

        <label>
          Categoría
          {crearCategoria ? (
            <div className="nueva-categoria">
              <input
                type="text"
                value={nuevaCategoria}
                onChange={(e) => setNuevaCategoria(e.target.value)}
                placeholder="Nombre de la nueva categoría"
                autoFocus
              />
              <button
                type="button"
                onClick={guardarNuevaCategoria}
                disabled={creando}
              >
                {creando ? 'Guardando...' : 'Guardar'}
              </button>
              <button
                type="button"
                className="btn-secundario"
                onClick={() => {
                  setCrearCategoria(false)
                  setNuevaCategoria('')
                  setError(null)
                }}
              >
                Cancelar
              </button>
            </div>
          ) : (
            <div className="nueva-categoria">
              <select
                value={form.categoria_id}
                onChange={(e) => actualizar('categoria_id', e.target.value)}
                required
              >
                <option value="">Selecciona...</option>
                {categorias.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nombre}
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="btn-secundario"
                onClick={() => setCrearCategoria(true)}
              >
                + Crear nueva categoría
              </button>
            </div>
          )}
        </label>

        <label>
          Precio base (COP)
          <input
            type="number"
            min="0"
            step="1"
            value={form.precio_base}
            onChange={(e) => actualizar('precio_base', e.target.value)}
            required
          />
        </label>

        <label className="check-row">
          <input
            type="checkbox"
            checked={form.activo}
            onChange={(e) => actualizar('activo', e.target.checked)}
          />
          Activo
        </label>

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