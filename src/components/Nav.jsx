const items = [
  ['dashboard', 'Dashboard'],
  ['ventas', 'Ventas'],
  ['productos', 'Productos'],
  ['promociones', 'Promociones'],
  ['gastos', 'Gastos'],
  ['deudores', 'Deudores'],
  ['capital', 'Capital'],
]

export default function Nav({ vista, onChange, onSignOut }) {
  return (
    <nav className="nav">
      <span className="nav-marca">Edella SweetAdmin</span>
      <div className="nav-items">
        {items.map(([clave, etiqueta]) => (
          <button
            key={clave}
            className={vista === clave ? 'nav-link activo' : 'nav-link'}
            onClick={() => onChange(clave)}
          >
            {etiqueta}
          </button>
        ))}
        <button className="nav-link nav-cerrar" onClick={onSignOut}>
          Cerrar sesión
        </button>
      </div>
    </nav>
  )
}