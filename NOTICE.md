# Aviso de obra derivada

Este repositorio contiene un **port para macOS** de [Aura](https://github.com/antwny/aura),
creado por **Antwny** ([YouTube](https://www.youtube.com/@antwny)) y publicado bajo la
licencia GPL-3.0-or-later.

Conforme a la sección 5 de la GPL-3.0, se deja constancia de que esta es una
**versión modificada** del programa original:

- **Fecha de la modificación:** noviembre de 2026.
- **Qué cambió:** se reescribió el programa en Swift para macOS. El motor de
  reproducción (mpvpaper/Wayland), la bandeja, la comunicación entre procesos (D-Bus),
  la detección de energía (UPower), la pausa en juegos (GameMode) y la integración con
  el tema de COSMIC se reemplazaron por sus equivalentes de Apple (AVFoundation, AppKit,
  IOKit, notificaciones distribuidas y la apariencia de macOS). La interfaz se rehízo
  en SwiftUI.
- **Qué se tomó del original:** el diseño general de la app, las opciones de
  configuración, la lógica de los catálogos online (Bing, Wallhaven, Minimalistic,
  MotionBGS, LiveWallpapers4Free), el algoritmo de extracción de color, los nombres de
  los comandos de terminal y el ícono.

Este port no está afiliado ni respaldado por el autor original. Los errores que tenga
son de este port, no del proyecto original.

Se distribuye bajo los mismos términos: **GPL-3.0-or-later** (ver `LICENSE`).
