# Edella SweetAdmin — Plan de proyecto: Gestor de inventario y finanzas

## 1. Resumen funcional (para validar que entendí bien)

| Módulo | Qué hace |
|---|---|
| **Ventas (Ingresos)** | Registrar ventas de productos individuales o combos/promociones, con propina opcional |
| **Egresos (Gastos)** | Registrar gastos clasificados en Reinversión, Ahorro o Personal |
| **Capital disponible** | 3 "bolsillos" (60% Reinversión / 20% Ahorro / 20% Personal) que suben con ventas y bajan con gastos |
| **Deudores** | Personas que deben dinero; cada abono que hacen entra al capital al momento de recibirse |
| **Productos** | Catálogo editable (cheesecakes, paves, anchetas) para evitar duplicados por error de tipeo |
| **Promociones** | Combos guardados, historial de qué tanto se venden, y desglose a nivel de producto individual |
| **Feedback mensual** | Comparativas mes a mes, histórico acumulado que nunca se borra |
| **Multiusuario** | Tú y tu pareja, desde cualquier celular o computador, datos siempre sincronizados |

---

## 2. Modelo de datos (entidades clave)

Esto es lo más importante de organizar antes de codear, porque de aquí sale todo lo demás.

### `productos`
- id, nombre, categoria (cheesecake / pave / ancheta / otro), precio_base, activo

### `promociones`
- id, nombre, descripcion, precio_promo, activa
- `promocion_productos` (tabla puente): promocion_id, producto_id, cantidad

### `ventas`
- id, fecha, tipo (`normal` | `promocion` | `deuda`), propina, total, promocion_id (nullable), deudor_id (nullable)
- `venta_items` (tabla puente): venta_id, producto_id, cantidad, precio_unitario
  - **Clave:** cuando una venta es de una promoción, además de guardar la promoción, se insertan aquí también los productos individuales (cheesecake fresa +1, pave klim +1). Así el top de productos más vendidos incluye lo vendido dentro de promos, tal como pediste.

### `capital_movimientos` (ledger, nunca se sobreescribe un saldo)
- id, fecha, tipo (`ingreso` | `egreso`), categoria (`reinversion` | `ahorro` | `personal`), valor, concepto, venta_id / gasto_id (referencia)
- El "capital disponible" de cada bolsillo **no se guarda como un número que se edita**, se calcula sumando este historial. Esto es importante: así nunca pierdes trazabilidad de por qué el saldo es el que es, y los reportes mensuales salen gratis (solo filtras por fecha).

### `gastos`
- id, fecha, categoria (reinversion/ahorro/personal), concepto, valor, producto_relacionado (nullable, ej. "leche klim", "fresas") — esto te permite comparar cuánto entra vs. cuánto sale por insumo específico

### `deudores`
- id, nombre, activo (si tiene saldo pendiente)
- `deuda_movimientos`: deudor_id, fecha, tipo (`cargo` | `abono`), valor, venta_id (nullable, solo en el `cargo` inicial), capital_movimiento_id (nullable, se llena cuando el tipo es `abono`, referenciando el ingreso que ese abono generó en capital)
- El nombre **nunca se borra** aunque la deuda llegue a 0 — solo se saca de la "lista activa de deudores".
- Un `cargo` (venta a crédito) no toca `capital_movimientos`. Un `abono` sí crea, en el mismo momento, su(s) movimiento(s) en `capital_movimientos` repartidos 60/20/20.

### Usuarios
- Solo 2 cuentas (tú y tu pareja), gestionadas por el sistema de autenticación de Supabase. No hace falta tabla propia.

---

## 3. Reglas de negocio a tener claras

1. **División 60/20/20:** cada venta genera 3 movimientos automáticos en `capital_movimientos` (reinversión, ahorro, personal) proporcionales al total.
2. **Todo dinero recibido en una venta entra al reparto**, no solo el precio del producto: propina, domicilio que el cliente decide dejarle, o cualquier "vueltas" que el cliente diga que se quede, se suma al total de esa venta y se reparte 60/20/20 igual que el resto. No hay una categoría aparte para esto — todo es capital ganado en la venta.
3. **Selección de productos por catálogo, no texto libre:** al registrar una venta, se busca/selecciona desde `productos` (autocompletado tipo "escribe 'che' y aparecen las opciones"). Esto evita que "Fresa", "fresa" y "Fresaa" cuenten como productos distintos en las estadísticas.
4. **Promociones = venta doble registro:** 1 venta de la promoción (para comparar promos entre sí) + N ventas de producto individual (para el top de productos).
5. **Anchetas:** se manejan como un producto normal más del catálogo (no como una combinación de sub-productos armada aparte). Si en el futuro retoman esa línea con fuerza, se puede reconsiderar modelarlas como combos.
6. **Deudores — capital y deuda se mueven en paralelo:** al registrar la venta a crédito, **no** se genera ningún movimiento de capital, solo un `cargo` en `deuda_movimientos` (todavía no ha entrado dinero real). Pero cada **abono** que la persona vaya haciendo sí genera, en el mismo momento, un movimiento en `capital_movimientos` (repartido 60/20/20) **y** una reducción del saldo pendiente de esa deuda. Ejemplo: deuda de $18.000, capital actual $100.000 → abonan $10.000 → deuda queda en $8.000 **y** capital queda en $110.000, en la misma acción. No hace falta esperar a que la deuda llegue a $0 para que el dinero cuente.
7. **Histórico que nunca se borra:** no existe un "cierre de mes" que resetee datos. Los feedbacks mensuales son simplemente consultas filtradas por fecha sobre las mismas tablas que crecen para siempre. El acumulado histórico es la suma de todos los meses.

---

## 4. Decisiones ya confirmadas

- **Propina y extras:** entran al total de la venta y se reparten 60/20/20 igual que el resto (ver regla 2 de la sección 3).
- **Abonos de deudas:** se reparten al capital en el mismo momento en que se reciben, no hay que esperar a saldar completo (ver regla 6 de la sección 3).
- **Anchetas:** se manejan como producto normal del catálogo, no como combo (ver regla 5 de la sección 3).

---

## 5. Stack tecnológico recomendado

| Capa | Tecnología | Por qué |
|---|---|---|
| **Frontend** | React + Vite, como PWA (se puede "agregar a inicio" en el celular y se ve como app) | Vas a publicar en Netlify, que es para sitios estáticos — React/Vite compila a HTML/JS estático perfecto para eso. Ya conoces React (lo usaste en Cafetería Luna). |
| **Base de datos + backend** | Supabase (Postgres gratis + autenticación + API automática) | Es gratis, no requiere servidor que tú administres, el modelo relacional (tablas con relaciones) encaja perfecto con este sistema tipo contable (ventas, movimientos, deudas). Ya lo usaste antes, así que reaprovechas experiencia. |
| **Autenticación** | Supabase Auth, solo 2 usuarios (tú y tu pareja) | Row Level Security (RLS) restringe el acceso a solo esas 2 cuentas, sin necesidad de programar tu propio sistema de login. |
| **Hosting** | Netlify (conectado a un repo de GitHub, deploy automático) | Gratis, y es justo lo que ya dominas. |

**Por qué no una app nativa (React Native) como Cafetería Luna:** aquí no necesitas tienda de apps ni Expo — con un link de Netlify accesible desde cualquier navegador (celular o PC) ya cumples el requisito de "acceso desde cualquier parte", y te ahorras la complejidad de builds nativos.

---

## 6. Cómo queda la arquitectura de despliegue

```
[Celular / PC de Leonard]  ─┐
                             ├──► Netlify (sitio web React) ──► Supabase (Postgres + Auth)
[Celular / PC de tu pareja] ─┘
```

- El sitio en Netlify **no guarda nada localmente** — cada acción (venta, gasto, abono) escribe directamente a Supabase por internet.
- Como los datos viven en Supabase (nube), da igual desde qué dispositivo se registre: siempre es la misma base de datos.
- Variables de entorno (URL y llave pública de Supabase) se configuran en el panel de Netlify — son seguras de exponer porque RLS controla quién puede leer/escribir, no la llave en sí.

**Un detalle importante del plan gratuito de Supabase (verificado, agosto 2026):** un proyecto gratuito se "pausa" automáticamente si pasa **7 días sin ninguna solicitud**. Como van a registrar ventas o gastos casi a diario, esto no debería afectarlos — pero si algún mes el negocio está muy quieto, hay que recordar entrar a la app al menos una vez por semana (o configurar un ping automático gratuito con GitHub Actions, que también es gratis). El plan gratuito de Netlify (300 créditos/mes) es más que suficiente para un sitio de uso privado de 2 personas con tráfico bajo.

---

## 7. Escalabilidad futura

Como el modelo de datos ya es una base de datos relacional "de verdad" (Postgres) y no un archivo local, cuando el negocio crezca tienes 2 caminos sin perder el histórico:

1. **Subir de plan en Supabase** (a partir de $25/mes) si superan el límite gratuito de 500 MB — para una app de este tipo (texto/números, sin fotos pesadas) eso tardaría años.
2. **Reconstruir o mejorar el frontend** (más reportes, más automatización, app nativa, etc.) reutilizando exactamente la misma base de datos — no se pierde ni un solo dato histórico, porque el histórico vive en Supabase, no en el código de la interfaz.

---

## 8. Fases sugeridas de desarrollo (para ahorrar tokens con Claude Code)

Te recomiendo pedirle a Claude Code el proyecto **por fases separadas**, no todo de un solo prompt gigante — así cada sesión es más corta y precisa:

1. **Fase 1 — Base:** esquema de Supabase (tablas + RLS), proyecto React/Vite conectado, login de 2 usuarios.
2. **Fase 2 — Catálogo:** CRUD de productos y promociones (con buscador/autocompletado).
3. **Fase 3 — Ventas y gastos:** formularios de ingreso/egreso, incluida la lógica de promociones (doble registro) y el reparto 60/20/20.
4. **Fase 4 — Deudores:** alta de personas, abonos, saldar deuda, traslado a capital.
5. **Fase 5 — Dashboards y feedback mensual:** comparativas, top de productos, top de gastos, comparativa de promociones.
6. **Fase 6 — Pulido:** diseño amigable, PWA (ícono en el celular), despliegue final en Netlify.

Puedes pegarle a Claude Code la sección 2 (modelo de datos) completa como contexto en la Fase 1, y luego en cada fase siguiente solo necesita saber el esquema ya creado, no repetir todo el documento.

---

## 9. Estado del plan

Todas las reglas de negocio quedaron definidas. El proyecto se llama **Edella SweetAdmin** (Edella = el emprendimiento; SweetAdmin = este sistema de gestión). Con esto ya puedes empezar la Fase 1 con Claude Code.
