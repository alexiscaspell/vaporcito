# Vaporcito Desktop (Tauri 2)

Aplicación de **escritorio nativa**: ventana Tauri + WebView + motor Go empaquetado como sidecar.

**No hace falta Electron.** Tauri genera AppImage / deb / instalador Windows con una ventana propia; la GUI no debe abrirse en el navegador del sistema.

```
front/desktop/          → shell Tauri (ventana nativa)
  └─ sidecar vaporcito  → motor Go (GUI en http://127.0.0.1:8384, --no-browser)
```

## Dev vs producto

| Comando | Qué es |
|---------|--------|
| `npm run desktop:dev` | **Solo desarrollo**: verás terminales (Vite + Rust). Normal. |
| `npm run desktop:build:linux` | **Producto**: AppImage/deb en `src-tauri/target/release/bundle/` |
| Abrir el AppImage/deb/.exe | App de escritorio: una ventana, sin navegador |

Si solo ves “una terminal y el navegador”, casi seguro estás en `desktop:dev` / Docker / binario Go suelto, **no** en el bundle instalable.

## Requisitos

### Todos

- Node.js **20+** (recomendado 22; con nvm: `nvm install 22 && nvm use 22`)
- Rust (rustup): https://rustup.rs
- Sidecar Go (scripts abajo)

### Linux (obligatorio para WebView)

Sin estas deps la ventana nativa no arranca y parece que “solo hay terminal”:

```bash
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev \
  patchelf pkg-config libdbus-1-dev
```

### Windows

- Visual Studio Build Tools (MSVC)
- WebView2 Runtime
- Target Rust `x86_64-pc-windows-msvc`

## Preparar el sidecar

Desde `front/desktop/`:

```bash
chmod +x scripts/*.sh
npm run prepare:sidecar          # Linux amd64
npm run prepare:sidecar:windows  # Windows amd64 (.exe) vía Docker
```

Archivos esperados en `src-tauri/binaries/`:

- `vaporcito-x86_64-unknown-linux-gnu`
- `vaporcito-x86_64-pc-windows-msvc.exe`

## Desarrollo (ventana + logs en terminal)

```bash
cd front/desktop
npm install
npm run desktop:dev
```

Flujo:

1. Splash en la **ventana** Tauri
2. Sidecar: `vaporcito serve --no-browser --gui-address=http://127.0.0.1:8384`
3. Health check → la misma ventana navega a la GUI (no `xdg-open`)
4. Al cerrar la ventana, se mata el sidecar

Logs del motor en release: `app_data_dir/vaporcito-sidecar.log` (en Linux suele ser `~/.local/share/com.vaporcito.app/`).

## Build de la app de escritorio

### Linux

```bash
cd front/desktop
npm run desktop:build:linux
```

Salida típica:

```text
src-tauri/target/release/bundle/deb/*.deb      ← instalable (recomendado)
src-tauri/target/release/bundle/rpm/*.rpm
src-tauri/target/release/bundle/appimage/*.AppImage  ← requiere librsvg2-dev
```

Si AppImage falla con `failed to run linuxdeploy`, instalá:

```bash
sudo apt install librsvg2-dev
```

El `.deb` que ya generaste sirve como app de escritorio:

```bash
sudo apt install ./src-tauri/target/release/bundle/deb/Vaporcito_*.deb
```

### Windows

En una máquina Windows (o en CI `windows-latest`):

```bash
cd front/desktop
VERSION=1.2.3 BUNDLE_VERSION=1.2.3 npm run desktop:build:windows
```

Requisitos: Node.js, Rust MSVC, WebView2. Artefactos en `src-tauri/target/release/bundle/` (`.msi` / NSIS `.exe`).

El pipeline de GitHub Actions (push a `develop`/`main`) construye desktop Linux + Windows y los adjunta a la Release junto con los binarios CLI.

## Checklist si se abre el navegador

1. ¿Estás ejecutando el **AppImage/deb/.exe** o solo `tauri dev` / Docker?
2. ¿Están instaladas las deps WebKit (`libwebkit2gtk-4.1-dev`)?
3. ¿Existe el sidecar en `src-tauri/binaries/`?
4. Revisá el log: `~/.local/share/com.vaporcito.app/vaporcito-sidecar.log`
5. En config del motor debe quedar `<startBrowser>false</startBrowser>` (el shell lo fuerza).

## Notas

- La GUI Angular sigue embebida en el binario Go (`front/gui`); Tauri solo la muestra en WebView.
- Puerto fijo `8384`; si está ocupado, el splash muestra error.
- Datos: directorio de la app (`app_data_dir/config`), no Docker.
