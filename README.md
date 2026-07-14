# 🍳 The Easy Cook

App de gestión para restaurantes (interfaz en español, mercado peruano). Es un
único archivo HTML autocontenido que corre con React vía `createElement` (sin
JSX, sin paso de compilación). No hay backend: todo se guarda en el
`localStorage` del navegador de cada dispositivo.

**Versión actual:** v4.5.0

## Estructura del proyecto

| Carpeta / archivo | Qué contiene |
|---|---|
| `index.html` | Página de bienvenida (elige Producción o Demo) |
| `app/the-easy-cook-V4.html` | Versión de **producción** |
| `app/the-easy-cook-V4-DEMO.html` | Versión **demo** para clientes |
| `docs/` | Documentación (reporte de handoff) |
| `memoria/` | Diario de decisiones y contexto del proyecto |

## Reglas del proyecto

1. Cada cambio de **código** se aplica en los **dos** archivos HTML, idéntico.
   Los cambios de **datos** (objeto `INIT`) son intencionalmente distintos.
2. Sin JSX: todo es `h(tag, props, ...children)` donde `h = createElement`.
3. Verificar sintaxis con Node después de cada cambio.
4. Al terminar una función: subir versión + entrada al CHANGELOG + commit en Git.

## Cómo abrir la app

Abre `index.html` en el navegador y elige Producción o Demo. Al publicarse en
GitHub Pages, se accede desde el enlace del repositorio.
