import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import Login from './components/Login'
import Nav from './components/Nav'
import Dashboard from './components/dashboard/Dashboard'
import Productos from './components/productos/Productos'
import Promociones from './components/promociones/Promociones'
import Ventas from './components/ventas/Ventas'
import Gastos from './components/gastos/Gastos'
import Deudores from './components/deudas/Deudores'
import Capital from './components/capital/Capital'

export default function App() {
  const [session, setSession] = useState(null)
  const [checking, setChecking] = useState(true)
  const [vista, setVista] = useState('ventas')

  useEffect(() => {
    supabase.auth
      .getSession()
      .then(({ data: { session } }) => {
        setSession(session)
        setChecking(false)
      })
      .catch(() => setChecking(false))

    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setSession(session)
      }
    )

    return () => {
      listener.subscription.unsubscribe()
    }
  }, [])

  async function handleSignOut() {
    await supabase.auth.signOut()
    setVista('ventas')
  }

  if (checking) {
    return <div className="center">Cargando...</div>
  }

  if (!session) {
    return <Login />
  }

  const vistas = {
    dashboard: <Dashboard />,
    ventas: <Ventas />,
    productos: <Productos />,
    promociones: <Promociones />,
    gastos: <Gastos />,
    deudores: <Deudores />,
    capital: <Capital />,
  }

  return (
    <div className="app">
      <Nav vista={vista} onChange={setVista} onSignOut={handleSignOut} />
      <main className="contenido">{vistas[vista]}</main>
    </div>
  )
}