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
        ? `GUI: ${status.gui_url}`
        : "El motor se inicia en segundo plano y luego abre la interfaz web.";
    }
  } catch (err) {
    statusEl.textContent = `Error: ${String(err)}`;
  }
}

window.addEventListener("DOMContentLoaded", () => {
  refreshStatus();
  window.setInterval(refreshStatus, 500);
});
