import { useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'

export default function ProductoBuscador({
  onSeleccionar,
  soloActivos = true,
  excluirIds = [],
  placeholder = 'Buscar producto...',
}) {
  const [termino, setTermino] = useState('')
  const [resultados, setResultados] = useState([])
  const [buscando, setBuscando] = useState(false)
  const [error, setError] = useState(null)
  const [abierto, setAbierto] = useState(false)

  useEffect(() => {
    if (!termino.trim()) {
      setResultados([])
      setAbierto(false)
      return
    }

    let activo = true
    setBuscando(true)
    setError(null)

    let query = supabase
      .from('productos')
      .select('*')
      .ilike('nombre', `%${termino.trim()}%`)
      .order('nombre')

    if (soloActivos) {
      query = query.eq('activo', true)
    }

    query.then(({ data, error: err }) => {
      if (!activo) return
      setBuscando(false)
      if (err) {
        setError(err.message)
        setResultados([])
        return
      }
      const filtrados = (data || []).filter(
        (p) => !excluirIds.includes(p.id)
      )
      setResultados(filtrados)
      setAbierto(true)
    })

    return () => {
      activo = false
    }
  }, [termino, soloActivos, excluirIds])

  function seleccionar(producto) {
    onSeleccionar(producto)
    setTermino('')
    setResultados([])
    setAbierto(false)
  }

  return (
    <div className="buscador">
      <input
        type="text"
        value={termino}
        onChange={(e) => setTermino(e.target.value)}
        onFocus={() => termino.trim() && setAbierto(true)}
        onBlur={() => setTimeout(() => setAbierto(false), 150)}
        placeholder={placeholder}
        autoComplete="off"
      />
      {buscando && <span className="buscador-mensaje">Buscando...</span>}
      {error && <span className="error">{error}</span>}
      {abierto && (
        <ul className="buscador-lista">
          {resultados.length === 0 && (
            <li className="buscador-vacio">Sin resultados</li>
          )}
          {resultados.map((p) => (
            <li key={p.id}>
              <button
                type="button"
                className="buscador-item"
                onMouseDown={() => seleccionar(p)}
              >
                {p.nombre}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}