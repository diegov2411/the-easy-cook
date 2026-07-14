# 🧠 Memoria del proyecto — The Easy Cook

Esta carpeta es el **diario del proyecto**: un registro de decisiones, contexto
y acuerdos, para que ninguna conversación futura pierda el hilo.

## Cómo usar esta carpeta

- Cada decisión o hito importante se anota aquí, con fecha.
- El reporte técnico completo vive en `../docs/handoff-the-easy-cook.md`.

---

## Bitácora

### 2026-07-14 — Preparación del entorno y publicación
- Se instaló **Node.js v24.18.0 LTS** (para verificar sintaxis con `node --check`).
- Se inicializó **Git** en la carpeta y se hizo el commit de punto de partida (v4.5.0).
- Se reorganizó el proyecto en carpetas: `app/`, `docs/`, `memoria/`.
- Se agregó `index.html` (página de bienvenida) y `README.md`.
- Se public en **GitHub Pages** (pblico). Repo: https://github.com/diegov2411/the-easy-cook
- **Enlace en vivo:** https://diegov2411.github.io/the-easy-cook/ (verificado funcionando).
- Cuenta de GitHub: `diegov2411`. Rama principal: `master`.

### 2026-07-14 — Ítem #2 completado (v4.6.0)
- **Parte A:** las alertas de stock crítico y bajo ahora sugieren cuánto comprar (≈ mín×2 − actual).
  Nota: el precio sugerido en platos caros y el ingrediente faltante en platos no disponibles YA existían.
- **Parte B:** nuevo componente `TodayChecklist` ("¿Qué hago hoy?") en el Dashboard, arriba del AlertCenter.
  Junta tareas accionables ordenadas por urgencia, cada una con botón que navega al módulo. Datos en vivo.
- Verificado con `node --check` en ambos archivos y abriendo la demo en el navegador (render correcto).
- Cambios idénticos en producción y demo. Subido a v4.6.0 con entrada en CHANGELOG.

### 2026-07-14 — Refinamientos v4.6.1 y v4.6.2
- **v4.6.1:** el panel "¿Qué hago hoy?" ahora es colapsable (igual que Alertas); ambos arrancan
  minimizados al abrir Inicio para dejar "Rendimiento de hoy" visible sin scroll.
- **v4.6.2:** arreglado hover pegajoso en las tarjetas (`Card`). Antes el resaltado se calculaba con
  estado de React (onMouseEnter/Leave) y se quedaba pegado si el navegador no mandaba el evento de
  salida (scroll, cambio de ventana). Ahora usa CSS `:hover` nativo vía `.ec-card-clickable`.
  Verificado en vivo: hover pinta border2 + lift; al salir vuelve a border. Sin estado JS que se atore.
