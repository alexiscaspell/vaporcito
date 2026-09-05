import { invoke } from "@tauri-apps/api/core";

type BootStatus = {
  ready: boolean;
  message: string;
  gui_url: string;
};

async function refreshStatus() {
  const statusEl = document.querySelector("#status");
  const hintEl = document.querySelector("#hint");
  if (!statusEl) return;

  try {
    const status = await invoke<BootStatus>("boot_status");
    statusEl.textContent = status.message;
    if (hintEl) {
      hintEl.textContent = status.ready
        ? "Cargando la interfaz en esta ventana…"
        : "App de escritorio: el motor arranca en segundo plano; la GUI se muestra aquí (no en el navegador).";
    }
  } catch (err) {
    statusEl.textContent = `Error: ${String(err)}`;
  }
}

window.addEventListener("DOMContentLoaded", () => {
  refreshStatus();
  window.setInterval(refreshStatus, 500);
});
