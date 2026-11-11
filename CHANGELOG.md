# Changelog

Todas las versiones de **Aura para macOS**. Este proyecto es un fork de
[antwny/aura](https://github.com/antwny/aura); el historial de la versión para
Linux hasta la 1.10.0 está en el repositorio original y en el historial de git
de este fork.

## [1.0.0] — 2026-11-11

Primera versión del port nativo para macOS 14+.

### Agregado
- Motor de fondos en Swift con AVFoundation: ventana a nivel de escritorio por
  pantalla, decodificación por hardware (VideoToolbox), ajuste Ajustar/Rellenar/Estirar
  por monitor y adaptación al conectar o desconectar pantallas.
- Pausa inteligente: apps a pantalla completa, ventanas encima (por pantalla y con
  cuatro niveles de sensibilidad), batería, modo de bajo consumo, bloqueo y reposo.
- Catálogos online portados del original: Bing UHD (con archivo histórico), Wallhaven,
  Minimalistic, MotionBGS y LiveWallpapers4Free, con descargas con progreso.
- Interfaz en SwiftUI: biblioteca, explorar, pantallas, ajustes y acerca de, en
  español e inglés.
- Ícono en la barra de menú con controles y volumen.
- Selector rápido con estilos panal, cinemático y clásico, y atajo global ⌃⌥Espacio.
- Comando `aura` (next, prev, toggle-pause, apply, status, volume, mode…).
- Tema claro/oscuro automático según el fondo (apagado por defecto), acento
  aproximado y fotograma como fondo de macOS, que se mantiene aunque se desinstale Aura.
- Conversión única de WebM, MKV y AVI con ffmpeg.
- Instalación con Homebrew: cask con la app ya compilada (`brew install --cask
  proskynete/aura/aura`) o fórmula que compila desde el código; también con
  `scripts/install.sh`.
- Release automático: al subir un tag `v*` se compila la app universal, se publica
  en GitHub Releases y se actualiza el tap.

### Reemplazado respecto al original
- El código en Rust para Linux (mpvpaper, Wayland, D-Bus, UPower, GameMode, COSMIC)
  se reemplazó por sus equivalentes de Apple. Ver `NOTICE.md`.
