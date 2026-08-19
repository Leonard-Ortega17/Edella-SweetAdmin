import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import ProductoForm from './ProductoForm'

export default function Productos() {
  const [productos, setProductos] = useState([])
  const [categorias, setCategorias] = useState([])
  const [estado, setEstado] = useState({ buscando: false, error: null, listo: false })
  const [termino, setTermino] = useState('')
  const [categoriaFiltro, setCategoriaFiltro] = useState('')
  const [mostrarForm, setMostrarForm] = useState(false)
  const [editar, setEditar] = useState(null)

  useEffect(() => {
    cargarCategorias()
  }, [])

  async function cargarCategorias() {
    const { data, error } = await supabase
      .from('categorias')
      .select('*')
      .order('nombre')
    if (!error) setCategorias(data || [])
  }

  async function cargar() {
    setEstado({ buscando: true, error: null, listo: false })
    let query = supabase
      .from('productos')
      .select('*, categorias(nombre)')
      .order('nombre')

    if (termino.trim()) {
      query = query.ilike('nombre', `%${termino.trim()}%`)
    }
    if (categoriaFiltro) {
      query = query.eq('categoria_id', categoriaFiltro)
    }

    const { data, error } = await query
    setEstado({ buscando: false, error: error?.message || null, listo: true })
    if (!error) setProductos(data || [])
  }

  useEffect(() => {
    cargar()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [termino, categoriaFiltro])

  async function guardarProducto(datos) {
    if (editar) {
      const { error } = await supabase
        .from('productos')
        .update(datos)
        .eq('id', editar.id)
      if (error) return error.message
    } else {
      const { error } = await supabase.from('productos').insert(datos)
      if (error) return error.message
    }
    return null
  }

  async function handleGuardar(datos) {
    const err = await guardarProducto(datos)
    if (err) {
      alert('No se pudo guardar el producto: ' + err)
      return
    }
    setMostrarForm(false)
    setEditar(null)
    cargar()
    cargarCategorias()
  }

  async function handleNuevaCategoria(nombre) {
    const { data, error } = await supabase
      .from('categorias')
      .insert({ nombre })
      .select()
    if (error) return { ok: false, error: error.message }
    cargarCategorias()
    return { ok: true, categoria: data[0] }
  }

  async function toggleActivo(producto) {
    const { error } = await supabase
      .from('productos')
      .update({ activo: !producto.activo })
      .eq('id', producto.id)
    if (error) {
      alert('No se pudo actualizar el producto: ' + error.message)
      return
    }
    cargar()
  }

  function abrirNuevo() {
    setEditar(null)
    setMostrarForm(true)
  }

  function abrirEditar(p) {
    setEditar(p)
    setMostrarForm(true)
  }

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Productos</h2>
        <button onClick={abrirNuevo}>Nuevo producto</button>
      </header>

      <div className="filtros">
        <input
          type="text"
          placeholder="Buscar por nombre..."
          value={termino}
          onChange={(e) => setTermino(e.target.value)}
        />
        <select
          value={categoriaFiltro}
          onChange={(e) => setCategoriaFiltro(e.target.value)}
        >
          <option value="">Todas las categorías</option>
          {categorias.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre}
            </option>
          ))}
        </select>
      </div>

      {estado.error && <p className="error">{estado.error}</p>}
      {estado.buscando && <p>Cargando...</p>}

      {!estado.buscando && estado.listo && (
        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Categoría</th>
                <th>Precio base</th>
                <th>Estado</th>
                <th>Acciones</th>
              </tr>
            </thead>
            <tbody>
              {productos.length === 0 && (
                <tr>
                  <td colSpan="5">Sin productos.</td>
                </tr>
              )}
              {productos.map((p) => (
                <tr key={p.id}>
                  <td>{p.nombre}</td>
                  <td>{p.categorias?.nombre || '-'}</td>
                  <td>{formatoCOP(p.precio_base)}</td>
                  <td>
                    <span className={p.activo ? 'badge ok' : 'badge no'}>
                      {p.activo ? 'Activo' : 'Inactivo'}
                    </span>
                  </td>
                  <td className="acciones">
                    <button onClick={() => abrirEditar(p)}>Editar</button>
                    <button onClick={() => toggleActivo(p)}>
                      {p.activo ? 'Desactivar' : 'Activar'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {mostrarForm && (
        <ProductoForm
          producto={editar}
          categorias={categorias}
          onNuevaCategoria={handleNuevaCategoria}
          onGuardar={handleGuardar}
          onCancelar={() => {
            setMostrarForm(false)
            setEditar(null)
          }}
        />
      )}
    </section>
  )
}