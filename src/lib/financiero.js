// Lógica financiera de Edella SweetAdmin (Fase 3).

export const BOLSILLOS = ['reinversion', 'ahorro', 'personal']
export const CATEGORIAS_GASTO = ['reinversion', 'ahorro', 'personal']
export const METODOS_PAGO = [
  'efectivo',
  'transferencia',
  'nequi',
  'daviplata',
  'otro',
  'credito',
]

// Divide un monto en 3 bolsillos 60/20/20 usando enteros (COP).
// Los 2 primeros usan truncamiento; el personal absorbe el resto
// para que la suma sea EXACTAMENTE igual a `valor`.
export function dividir60_20_20(valor) {
  const reinversion = Math.floor((valor * 3) / 5)
  const ahorro = Math.floor(valor / 5)
  const personal = valor - reinversion - ahorro
  return { reinversion, ahorro, personal }
}

// Redimensiona un array de `detalles` (uno por unidad de promoción) a la
// cantidad deseada. Si crece, rellena con `null` (sin detalles). Si decrece,
// descarta únicamente las unidades sobrantes. Conserva los detalles ya escritos.
export function redimensionarDetalles(detalles, cantidad) {
  const actual = Array.isArray(detalles) ? detalles : []
  const n = Number(cantidad) || 0
  if (n <= 0) return []
  return Array.from({ length: n }, (_, i) => (i < actual.length ? actual[i] : null))
}

// Asegura que la unidad `indice` tenga un array de artículos {producto_id, nombre, sabor}.
export function articulosDeUnidad(detalles, indice) {
  const unidad = Array.isArray(detalles) && detalles[indice] ? detalles[indice] : null
  return Array.isArray(unidad) ? unidad : []
}

// Serializa los detalles para guardarlos en la RPC (JSONB) y para alimentar el
// desglose de "productos mas vendidos" con {producto_id, nombre, sabor}.
// Cada unidad es un array de artículos sin entradas vacías.
// Devuelve null si no hay ningún detalle en ninguna unidad.
export function normalizarDetallesParaEnviar(detalles) {
  if (!Array.isArray(detalles) || detalles.length === 0) return null
  const resultado = detalles.map((unidad) => {
    if (!Array.isArray(unidad)) return []
    return unidad
      .filter((a) => a && typeof a === 'object' && a.producto_id)
      .map((a) => ({
        producto_id: a.producto_id,
        nombre: a.nombre || '',
        sabor: a.sabor || '',
      }))
  })
  const tieneAlgo = resultado.some((unidad) => unidad.length > 0)
  return tieneAlgo ? resultado : null
}