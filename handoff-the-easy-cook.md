# 📋 Reporte de Handoff — App "The Easy Cook"

> **Propósito de este documento:** transferir todo el contexto de esta conversación a un nuevo chat de Claude, para continuar el desarrollo sin perder información. Está escrito para que otro Claude lo entienda de inmediato y sepa exactamente dónde retomar.

---

## 1. Resumen ejecutivo

**The Easy Cook** es una app de gestión para restaurantes (interfaz en español, mercado peruano). Es un **único archivo HTML autocontenido** que corre con React vía `createElement` (sin JSX, sin build step). No hay backend: **todo se guarda en `localStorage` del navegador.**

Existen **dos archivos que se mantienen sincronizados en código pero no en datos:**

| Archivo | Propósito | Ubicación |
|---|---|---|
| `the-easy-cook-V4.html` | Versión de producción real | `/mnt/user-data/outputs/` |
| `the-easy-cook-V4-DEMO.html` | Versión demo para mostrar a clientes | `/mnt/user-data/outputs/` |

**Versión actual: `v4.5.0`** ("Sprint 14 — Julio 2026"), idéntica en ambos archivos.

**Estado:** Hay una **tarea en curso sin empezar a codificar** (ver Sección 6). Ese es el punto exacto donde retomar.

---

## 2. Reglas de oro del proyecto (leer antes de tocar nada)

1. **Todo cambio de _código_ (funciones, componentes, lógica) se replica en AMBOS archivos, idéntico.** Los cambios de _datos_ (el objeto `INIT`) son intencionalmente distintos entre producción y demo.
2. **Sin JSX.** Todo es `h(tag, props, ...children)` donde `h = createElement`. También está disponible `Fragment`.
3. **Verificar sintaxis siempre** tras editar: extraer el script principal y correr `node --check`. Los números de línea cambian en cada edición, así que **siempre volver a buscar `grep -n "</script>"` antes de extraer** (hay un bundle de React minificado arriba con su propio `</script>`, y el `</script>` de cierre del script principal es el último).
4. **Flujo de entrega:** editar en el sandbox → `node --check` en ambos → copiar a `/mnt/user-data/outputs/` → `present_files`.
5. **Al terminar una feature:** subir versión (`APP_VERSION`, `APP_BUILD`) y agregar entrada al `CHANGELOG`, en ambos archivos.

---

## 3. Mapa de arquitectura (referencias rápidas)

Ubicaciones aproximadas dentro del `<script>` principal (siempre re-verificar con `grep`, cambian con cada edición):

| Elemento | Referencia | Notas |
|---|---|---|
| Destructuring de React | `const {useState,...,createElement:h,Fragment} = React;` (~L17416) | Define `h` y `Fragment` |
| `APP_VERSION` / `APP_BUILD` / `CHANGELOG` | ~L17400 | Historial de versiones |
| `INIT` | ~L17440 | Datos semilla completos. **En demo, `INIT` es más rico y con fechas corridas +99 días** para que "hoy" (12 jul 2026) tenga actividad |
| `DEMO_SEED_USERS` | cerca de `isFirstRun` | Objeto keyed por id de usuario (NO array), detecta credenciales demo sin personalizar |
| `getSettings(data)` | ~L17726 | Defaults de settings (igvMode, serviceCharge, foodCostTarget, restaurantName, ruc) |
| `canMakeRecipe` / `getMissingIngredients` | ~L17858 / ~L17875 | Cálculo de stock teórico. `getMissingIngredients` ahora incluye `productId` en cada resultado |
| `InfoTip` | antes de `MetricCard` | Tooltip táctil reutilizable (tap para abrir/cerrar, pensado para mobile) |
| `MetricCard` / `PLRow` | — | Ambos aceptan prop opcional `tip` |
| `AlertCenter` | ~L18140 | Centro de alertas del Dashboard |
| `Dashboard` | ~L18313 | Calcula `critical`, `lowStock`, `needsRecount`, etc. y los pasa a `AlertCenter` |
| `Sales` (Ventas) | ~L20641 | Contiene `addDish`, `doAddDishLine`, `closeOrder`, modales |
| `Abastecimiento` | ~L20033 | Compras. Contiene `applyToInventory` |
| `Inventory` | ~L19020 | Lista de insumos, badges de estado, barra `StockBar` |
| `SettingsPage` | — | Configuración + burbuja "Acerca de" |
| `App` | ~L24946 | Componente raíz, auto-login (solo en demo), gate de PinLogin/FirstRunSetup |

**Archivos de trabajo en el sandbox:**
- Producción: `/home/claude/work/app.html`
- Demo: `/home/claude/work/demo2.html`

---

## 4. Historial cronológico de lo construido

Ordenado por sprint/versión. Cada ítem ya está **implementado y entregado.**

### Aforo (personas por mesa)
Se agregó campo "N° de personas" a cada pedido en Ventas. Totales de personas atendidas por día (en la lista de Ventas), por semana y por mes (Reportes), y en el Dashboard.

### v4.0.0 — Burbuja "Acerca de" + onboarding descubierto
- Se movió el badge de versión "V2" del sidebar a una burbuja de información **"Acerca de The Easy Cook"** en Configuración (muestra versión, build, changelog, datos del negocio).
- **Hallazgo importante:** ya existía un flujo de onboarding completo (`isFirstRun` + `FirstRunSetup`) construido en una sesión anterior — obligatorio crear cuenta del dueño, opcional lo demás.
- **Bug corregido:** `AlertCenter` tenía props muertas (`missingBizFields`, `demoStaffLeft`, `noRecipes`, `noProducts`) que nunca se calculaban ni pasaban. Se conectaron. Solo se muestran para el rol `owner`.

### Creación de la versión Demo
- Auto-login (sin PIN, salta el onboarding).
- Banner naranja **"MODO DEMO"** con botón de reinicio de datos (dos toques para confirmar).
- Selector rápido de perfil/rol (sin PIN) reemplazando el botón de logout (icono 🔄).
- Badge "DEMO" junto a la marca en sidebar y topbar.
- `INIT` enriquecido con fechas actuales, 5 usuarios (incluye rol "Jefe de Salón"), negocio ya configurado ("El Mirador", con RUC, IGV incluido, cargo por servicio activo).

### Sub-receta de papas fritas
Se **reutilizó** la sub-receta ya existente `SR001` ("Papa Fritas Precocidas") en vez de duplicarla. Se le dio stock vía un registro de producción y se vinculó como ingrediente (`type:"subrecipe"`, 150g) dentro de la receta de **Lomo Saltado** (R001). La lógica de descuento de stock al cerrar pedido ya sabía manejar sub-recetas, así que solo fue cambio de datos.

### v4.2.0 — Producción por rendimiento real
En **Producción**, en vez de pedir "cuántos batches hiciste" (que forzaba matemática mental cuando el rendimiento no era exacto), ahora pide **"¿cuánto rendimiento obtuviste?"**. La app calcula hacia atrás, proporcionalmente, cuánto se consumió de cada ingrediente. Muestra el factor de escala (≈X batches) como referencia, y acredita al stock de la sub-receta el rendimiento real exacto ingresado.

### v4.3.0 / v4.3.1 — Tooltips "ⓘ" en lenguaje simple (InfoTip)
Componente reutilizable `InfoTip` (tap para abrir/cerrar, táctil/mobile). Explicaciones en lenguaje llano agregadas en:
- **Reportes semanal/mensual:** Costo de alimentos, Margen bruto, IGV, Mermas, Ticket promedio, Personas atendidas.
- **Recetas:** Costo receta, Costo % real (explica qué significan los colores rojo/amarillo/verde), Margen neto.
- **Configuración:** qué es el IGV (no todos saben que es el 18% de impuesto peruano); benchmark de food cost (28-32% casual, hasta 35% comida rápida).
- **Matriz de Menú:** leyenda **siempre visible** de Estrellas/Enigmas/Bueyes/Perros (antes solo se explicaba al tocar un plato).
- **Resumen Mensual:** cada variación vs mes anterior, con advertencia de que **a veces una flecha hacia abajo es la buena señal** (costo de alimentos, mermas, compras). Nota especial en Compras: que bajen no siempre es bueno (puede ser por vender menos).

### v4.4.0 — Sin bloqueo duro por falta de stock en Ventas
Antes, un plato sin stock teórico suficiente estaba **bloqueado** (no seleccionable, botón deshabilitado). Ahora se puede seleccionar y agregar igual, con un **modal de confirmación** ("¿Quieres agregarlo de todas formas?") que explica que el stock real de cocina puede diferir del registrado. El dropdown muestra "⚠️ — Sin stock teórico" en vez de desactivar la opción.

### v4.5.0 — Manejo de discrepancias de stock (real vs. teórico)
Tres cambios que resuelven qué pasa cuando el stock real difiere del sistema:

1. **Stock puede quedar negativo.** Antes `closeOrder` topaba en cero (ocultando el desfase). Ahora deja el negativo como señal honesta. Se **simplificó `closeOrder`**, eliminando una lógica vieja de "fallback a ingredientes crudos" para sub-recetas que solo existía por el viejo tope en cero.

2. **Override marca ingredientes para recontar.** Al confirmar "agregar de todas formas" con falta de stock, los ingredientes involucrados se marcan `needsRecount:true`. Esto aparece en:
   - Un nuevo alert **"🔢 X insumos con posible desfase — recuéntalos"** en el Alert Center.
   - Un badge **"🔢 Recontar"** directo en la fila del insumo en Inventario.
   - La bandera **solo se limpia con un Conteo de stock real** (no con una compra), porque recibir mercadería no verifica lo que hay físicamente en cocina.

3. **Las compras resetean desde cero.** Si el stock estaba negativo al confirmar una compra recibida, la nueva mercadería **ya no "paga" el déficit**: se toma el negativo como cero y se suma la cantidad comprada (`Math.max(0,p.stock) + qty`). Esto fue un pedido explícito del usuario.

- **Bug corregido de paso:** la barra de stock (`StockBar`) podía renderizar ancho inválido/negativo con stock negativo (los navegadores lo interpretan como "lleno"), haciendo que un insumo muy agotado se viera lleno. Se limitó a 0.

---

## 5. Lista de mejoras propuestas (roadmap)

Se le propuso al usuario una lista de 7 categorías para que un **dueño sin experiencia previa en restaurantes** maneje la app más fácil:

| # | Mejora | Estado |
|---|---|---|
| 1 | **Traducir jerga a lenguaje simple** (tooltips ⓘ) | ✅ Implementado (v4.3.0/4.3.1) |
| 2 | **Convertir alertas en "qué hago al respecto"** + checklist diario | 🔶 **EN CURSO — ver Sección 6** |
| 3 | Reducir fricción de setup (recetas pre-cargadas, sugerencias de precio) | ⬜ Pendiente |
| 4 | Generar confianza / reducir miedo a "romper algo" (undo, log visible) | ⬜ Pendiente |
| 5 | Números que se sientan reales (recap semanal en lenguaje llano, "health score" semáforo) | ⬜ Pendiente |
| 6 | Llevarle la info al dueño (resumen compartible, recordatorios) | ⬜ Pendiente |
| 7 | No abrumar el día 1 (modo simple, hints contextuales por módulo) | ⬜ Pendiente |

---

## 6. 🔶 TAREA EN CURSO — punto exacto donde retomar

El usuario pidió implementar el **ítem #2 completo**, en dos partes:

### Parte A — Alertas con acción concreta, no solo diagnóstico
> En vez de solo "food cost alto" → **"Sube el precio de este plato a S/X para volver a tu objetivo"**.
> En vez de solo "stock bajo" → **"Compra Y kg de esto esta semana"**.

### Parte B — Checklist diario "¿Qué hago hoy?" en el Dashboard
> Una sola lista accionable que junte: compras pendientes de confirmar, platos con precio por debajo del objetivo, insumos para contar — **sin que el dueño tenga que saber en qué módulo buscar cada cosa.**

### ⚠️ Estado real del trabajo
Solo se **ubicó** la función `AlertCenter` (~L18140 en `app.html`) con un `grep`. **NO se hizo ningún cambio de código todavía.** Aquí es donde continuar desde cero.

### Estructura actual de las alertas (para partir de ahí)
Cada alerta tiene la forma:
```
{ id, severity, icon, title, body:[...], actions:[{label, page}] }
```

Inventario de alertas existentes en `AlertCenter`:

| Alerta | Qué muestra hoy | Qué le falta (Parte A) |
|---|---|---|
| `critical` (stock crítico) | Déficit ("faltan X") | Sugerir cantidad concreta a comprar |
| `lowStock` (stock bajo) | Actual vs mínimo | Sugerir cantidad de compra concreta |
| `needsRecount` (v4.5.0) | "Contar stock →" | Ya es accionable, cumple el espíritu |
| `unavailable` (platos no disponibles) | Solo dice que no se puede | Decir qué ingrediente específico falta |
| `pricingAlerts` | Revisar qué contiene exactamente | Probablemente necesita precio sugerido |
| `pendingPurchases` | Solo lista | Bastante accionable; integrar al checklist |
| `todayWastage` / `cashMatchStatus` / `cashGap` | Diagnóstico | Revisar caso por caso |
| `missingBizFields`, `demoStaffLeft`, `noRecipes`, `noProducts` | Checklist de setup inicial | Ya tienen `page` de navegación |

### Sugerencia de implementación (idea, no código escrito)

1. **Stock bajo/crítico → cantidad de compra sugerida.** Ya existe lógica parecida en Abastecimiento:
   ```
   suggestedQty: Math.max(p.minStock*2 - p.stock, p.minStock)
   ```
   Reusarla y meterla en el `body` o como acción con texto tipo "Compra X kg esta semana".

2. **Pricing → precio sugerido.** Si el food cost % de un plato supera el objetivo, calcular el precio necesario para volver al target:
   ```
   precioSugerido = costoReceta / foodCostTarget   (ajustar por IGV según igvMode)
   ```
   Mostrarlo como sugerencia concreta ("Sube a S/X").

3. **Checklist "¿Qué hago hoy?"** — nuevo componente en el Dashboard (arriba o cerca del `AlertCenter`) que agregue en una sola lista tipo tareas (con checkboxes si se puede): compras pendientes (`pendingPurchases`), platos por debajo del objetivo de food cost, ingredientes con `needsRecount`, y alertas críticas de stock.

4. **Cierre estándar:** replicar en `app.html` Y `demo2.html`, subir a **v4.6.0** con entrada en `CHANGELOG`, `node --check` en ambos, copiar a outputs, `present_files`.

---

## 7. Checklist rápido para el nuevo Claude

- [ ] Leer este documento completo antes de tocar código.
- [ ] Confirmar que ambos archivos están en `v4.5.0` (`grep APP_VERSION`).
- [ ] Para la tarea en curso: empezar por la Parte A (alertas accionables) o Parte B (checklist) según prefiera el usuario — **preguntarle cuál primero si no lo especifica.**
- [ ] Cada cambio de código va en los DOS archivos.
- [ ] `node --check` tras cada edición (re-buscar `</script>` para los límites).
- [ ] Al terminar: bump a v4.6.0 + changelog, copiar a outputs, `present_files`.
- [ ] Recordar que el usuario prueba en su navegador; si no ve un cambio de datos, es caché de `localStorage` → usar el botón "Reiniciar datos" del banner demo, o mencionarlo.
