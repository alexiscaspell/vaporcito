# Vaporcito Desktop (Tauri 2)

Shell nativo que arranca el motor Go (Vaporcito) como **sidecar** y muestra la GUI web en un WebView.

```
front/desktop/  →  Tauri shell
   └─ sidecar vaporcito  →  serve GUI en http://127.0.0.1:8384
```

El motor Go vive en `back/`; este shell solo empaqueta y muestra la GUI embebida.

## Requisitos

### Todos

- Node.js 18+
- Rust (rustup): https://rustup.rs
- Binario Go de Vaporcito (se puede generar con Docker; ver scripts)

### Linux (build / `tauri dev`)

```bash
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev patchelf pkg-config
```

### Windows (build)

- Visual Studio Build Tools (MSVC)
- WebView2 Runtime
- Rust `x86_64-pc-windows-msvc`

## Preparar el sidecar

Desde `front/desktop/`:

```bash
chmod +x scripts/*.sh
npm run prepare:sidecar          # Linux amd64
npm run prepare:sidecar:windows  # Windows amd64 (.exe) vía Docker
```

Esto compila desde `back/` (montando la raíz del repo) y deja archivos en `src-tauri/binaries/` con el sufijo de target triple que exige Tauri, por ejemplo:

- `vaporcito-x86_64-unknown-linux-gnu`
- `vaporcito-x86_64-pc-windows-msvc.exe`

## Desarrollo

```bash
cd front/desktop
npm install
npm run desktop:dev
```

Flujo al abrir la app:

1. Splash local (Vite)
2. Arranca `vaporcito serve --no-browser --gui-address=http://127.0.0.1:8384 --home=<app-data>/config`
3. Espera `/rest/noauth/health`
4. Navega el WebView a la GUI
5. Al cerrar, mata el sidecar

## Build

### Linux

```bash
npm run desktop:build:linux
```

Salida típica: `src-tauri/target/release/bundle/` (deb/AppImage/rpm según target).

### Windows

En Linux solo se prepara el sidecar:

```bash
npm run desktop:build:windows
```

El instalador se genera en una máquina Windows con `npm run tauri build`.

## Notas

- No reescribe el front AngularJS: reutiliza la GUI embebida del binario Go (`front/gui`).
- Puerto fijo `8384` en este spike; si está ocupado, el splash muestra error.
- Config/datos del motor: directorio de datos de la app (`app_data_dir/config`), no Docker.
