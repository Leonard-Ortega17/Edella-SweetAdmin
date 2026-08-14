import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import Login from './components/Login'

export default function App() {
  const [session, setSession] = useState(null)
  const [checking, setChecking] = useState(true)

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
  }

  if (checking) {
    return <div className="center">Cargando...</div>
  }

  if (!session) {
    return <Login />
  }

  return (
    <div className="center">
      <h1>Edella SweetAdmin - Fase 1 completa</h1>
      <button onClick={handleSignOut}>Cerrar sesión</button>
    </div>
  )
}