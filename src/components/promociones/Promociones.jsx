import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { formatoCOP } from '../../lib/formato'
import PromocionForm from './PromocionForm'

export default function Promociones() {
  const [promociones, setPromociones] = useState([])
  const [cargando, setCargando] = useState(false)
  const [error, setError] = useState(null)
  const [mostrarForm, setMostrarForm] = useState(false)
  const [editar, setEditar] = useState(null)
  const [editarItems, setEditarItems] = useState([])

  async function cargar() {
    setCargando(true)
    setError(null)
    const { data, error: err } = await supabase
      .from('promociones')
      .select('*')
      .order('nombre')
    if (err) {
      setError(err.message)
    } else {
      setPromociones(data || [])
    }
    setCargando(false)
  }

  useEffect(() => {
    cargar()
  }, [])

  async function cargarItemsDe(promocionId) {
    const { data, error } = await supabase
      .from('promocion_productos')
      .select('producto_id, cantidad, productos(nombre)')
      .eq('promocion_id', promocionId)
    if (error) return { error: error.message, items: [] }
    const items = (data || []).map((r) => ({
      producto_id: r.producto_id,
      cantidad: r.cantidad,
      producto_nombre: r.productos?.nombre || 'Producto',
    }))
    return { error: null, items }
  }

  async function abrirNuevo() {
    setEditar(null)
    setEditarItems([])
    setMostrarForm(true)
  }

  async function abrirEditar(p) {
    setError(null)
    const { error: err, items } = await cargarItemsDe(p.id)
    if (err) {
      alert('No se pudieron cargar los productos: ' + err)
      return
    }
    setEditar(p)
    setEditarItems(items)
    setMostrarForm(true)
  }

  async function guardarPromocion(datos) {
    // Separar los campos propios de `promociones` de sus productos (`items`).
    // `items` NO es columna de `promociones`; va a la tabla `promocion_productos`.
    const { items, ...camposPromocion } = datos

    // 1) Guardar los datos base de la promoción
    let promocionId = editar?.id
    if (editar) {
      const { error } = await supabase
        .from('promociones')
        .update(camposPromocion)
        .eq('id', editar.id)
      if (error) return 'No se pudo actualizar la promoción: ' + error.message
    } else {
      const { data, error } = await supabase
        .from('promociones')
        .insert(camposPromocion)
        .select()
      if (error) return 'No se pudo crear la promoción: ' + error.message
      promocionId = data[0].id
    }

    // 2) Borrar los puentes existentes (fase 2: borrar + reinsertar)
    if (editar) {
      const { error: borradoError } = await supabase
        .from('promocion_productos')
        .delete()
        .eq('promocion_id', promocionId)
      if (borradoError)
        return 'Se actualizó la promoción pero no se pudieron limpiar sus productos: ' + borradoError.message
    }

    // 3) Reinsertar los productos
    const filas = items.map((i) => ({
      promocion_id: promocionId,
      producto_id: i.producto_id,
      cantidad: i.cantidad,
    }))

    if (filas.length > 0) {
      const { error: insertError } = await supabase
        .from('promocion_productos')
        .insert(filas)
      if (insertError)
        return 'La promoción se guardó pero no se pudieron guardar sus productos: ' + insertError.message
    }

    return null
  }

  async function handleGuardar(datos) {
    const err = await guardarPromocion(datos)
    if (err) {
      // Manejo estricto: no mostrar éxito si algo falló
      alert(err)
      return
    }
    setMostrarForm(false)
    setEditar(null)
    setEditarItems([])
    cargar()
  }

  async function toggleActiva(p) {
    const { error } = await supabase
      .from('promociones')
      .update({ activa: !p.activa })
      .eq('id', p.id)
    if (error) {
      alert('No se pudo actualizar la promoción: ' + error.message)
      return
    }
    cargar()
  }

  return (
    <section className="seccion">
      <header className="seccion-cabecera">
        <h2>Promociones</h2>
        <button onClick={abrirNuevo}>Nueva promoción</button>
      </header>

      {error && <p className="error">{error}</p>}
      {cargando && <p>Cargando...</p>}

      {!cargando && (
        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Descripción</th>
                <th>Precio</th>
                <th>Estado</th>
                <th>Acciones</th>
              </tr>
            </thead>
            <tbody>
              {promociones.length === 0 && (
                <tr>
                  <td colSpan="5">Sin promociones.</td>
                </tr>
              )}
              {promociones.map((p) => (
                <tr key={p.id}>
                  <td>{p.nombre}</td>
                  <td>{p.descripcion || '-'}</td>
                  <td>{formatoCOP(p.precio_promo)}</td>
                  <td>
                    <span className={p.activa ? 'badge ok' : 'badge no'}>
                      {p.activa ? 'Activa' : 'Inactiva'}
                    </span>
                  </td>
                  <td className="acciones">
                    <button onClick={() => abrirEditar(p)}>Editar</button>
                    <button onClick={() => toggleActiva(p)}>
                      {p.activa ? 'Desactivar' : 'Activar'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {mostrarForm && (
        <PromocionForm
          promocion={editar}
          productosIniciales={editarItems}
          onGuardar={handleGuardar}
          onCancelar={() => {
            setMostrarForm(false)
            setEditar(null)
            setEditarItems([])
          }}
        />
      )}
    </section>
  )
}