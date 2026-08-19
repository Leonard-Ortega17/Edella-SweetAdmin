import { useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'

// Input de texto con autocompletado de conceptos previos de gastos.
// Compara insensible a mayúsculas (trim + lowercase) para sugerir conceptos
// ya registrados (p.ej. "mototaxi" completa "Mototaxi") y evitar duplicados.
export default function ConceptoBuscador({
  onCambio,
  onSeleccionar,
  valor,
  placeholder = 'Concepto',
}) {
  const [termino, setTermino] = useState(valor || '')
  const [conceptos, setConceptos] = useState([])
  const [abierto, setAbierto] = useState(false)
  const [sinCargar, setSinCargar] = useState(true)

  useEffect(() => {
    if (sinCargar) {
      supabase
        .from('gasto_items')
        .select('concepto')
        .then(({ data }) => {
          const unicos = new Set()
          for (const d of data || []) {
            if (d.concepto) unicos.add(String(d.concepto).trim())
          }
          setConceptos([...unicos])
          setSinCargar(false)
        })
    }
  }, [sinCargar])

  const textoNormalizado = (t) => String(t || '').trim().toLowerCase()

  const sugerencias =
    termino.trim().length > 0
      ? conceptos
          .filter((c) => textoNormalizado(c).includes(textoNormalizado(termino)))
          .slice(0, 8)
      : []

  function seleccionar(c) {
    setTermino(c)
    setAbierto(false)
    onCambio?.(c)
    onSeleccionar?.(c)
  }

  return (
    <div className="buscador">
      <input
        type="text"
        value={termino}
        onChange={(e) => {
          setTermino(e.target.value)
          setAbierto(true)
          onCambio?.(e.target.value)
        }}
        onFocus={() => termino.trim() && setAbierto(true)}
        onBlur={() => setTimeout(() => setAbierto(false), 150)}
        placeholder={placeholder}
        autoComplete="off"
      />
      {abierto && (
        <ul className="buscador-lista">
          {sugerencias.length === 0 && termino.trim() && (
            <li className="buscador-vacio">Nuevo concepto</li>
          )}
          {sugerencias.map((c) => (
            <li key={c}>
              <button
                type="button"
                className="buscador-item"
                onMouseDown={() => seleccionar(c)}
              >
                {c}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}