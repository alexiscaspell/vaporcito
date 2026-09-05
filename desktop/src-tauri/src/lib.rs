use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Manager, RunEvent, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_shell::process::CommandChild;
use tauri_plugin_shell::ShellExt;

const GUI_HOST: &str = "127.0.0.1";
const GUI_PORT: u16 = 8384;
const HEALTH_PATH: &str = "/rest/noauth/health";
const HEALTH_TIMEOUT: Duration = Duration::from_secs(45);
const HEALTH_POLL: Duration = Duration::from_millis(400);

struct SidecarState(Mutex<Option<CommandChild>>);

#[derive(Clone, Serialize)]
struct BootStatus {
    ready: bool,
    message: String,
    gui_url: String,
}

fn gui_url() -> String {
    format!("http://{GUI_HOST}:{GUI_PORT}")
}

fn health_url() -> String {
    format!("{}{HEALTH_PATH}", gui_url())
}

fn wait_for_health() -> Result<(), String> {
    let url = health_url();
    let started = std::time::Instant::now();
    while started.elapsed() < HEALTH_TIMEOUT {
        match ureq::get(&url).timeout(Duration::from_secs(2)).call() {
            Ok(resp) if (200..300).contains(&resp.status()) => return Ok(()),
            _ => std::thread::sleep(HEALTH_POLL),
        }
    }
    Err(format!(
        "Timed out waiting for Vaporcito GUI at {url}. Is port {GUI_PORT} free?"
    ))
}

fn start_sidecar(app: &AppHandle) -> Result<(), String> {
    let home = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app data dir: {e}"))?
        .join("config");
    std::fs::create_dir_all(&home).map_err(|e| format!("create config dir: {e}"))?;

    let home_str = home.to_string_lossy().to_string();
    let gui_address = format!("http://{GUI_HOST}:{GUI_PORT}");

    let sidecar = app
        .shell()
        .sidecar("vaporcito")
        .map_err(|e| format!("sidecar binary missing (run scripts/prepare-sidecar.sh): {e}"))?
        .args([
            "serve",
            "--no-browser",
            "--no-restart",
            "--gui-address",
            &gui_address,
            "--home",
            &home_str,
        ]);

    let (mut rx, child) = sidecar
        .spawn()
        .map_err(|e| format!("failed to spawn vaporcito sidecar: {e}"))?;

    {
        let state = app.state::<SidecarState>();
        let mut guard = state.0.lock().map_err(|_| "sidecar state lock poisoned")?;
        *guard = Some(child);
    }

    tauri::async_runtime::spawn(async move {
        while let Some(event) = rx.recv().await {
            match event {
                tauri_plugin_shell::process::CommandEvent::Stdout(line)
                | tauri_plugin_shell::process::CommandEvent::Stderr(line) => {
                    let text = String::from_utf8_lossy(&line);
                    eprintln!("[vaporcito] {text}");
                }
                tauri_plugin_shell::process::CommandEvent::Terminated(payload) => {
                    eprintln!("[vaporcito] exited: {payload:?}");
                    break;
                }
                _ => {}
            }
        }
    });

    Ok(())
}

fn stop_sidecar(app: &AppHandle) {
    if let Some(state) = app.try_state::<SidecarState>() {
        if let Ok(mut guard) = state.0.lock() {
            if let Some(child) = guard.take() {
                let _ = child.kill();
            }
        }
    }
}

fn open_gui_window(app: &AppHandle) -> Result<(), String> {
    let url = gui_url()
        .parse()
        .map_err(|e| format!("invalid gui url: {e}"))?;

    if let Some(window) = app.get_webview_window("main") {
        window
            .navigate(url)
            .map_err(|e| format!("navigate to gui: {e}"))?;
        return Ok(());
    }

    WebviewWindowBuilder::new(app, "main", WebviewUrl::External(url))
        .title("Vaporcito")
        .inner_size(1280.0, 800.0)
        .build()
        .map_err(|e| format!("create gui window: {e}"))?;
    Ok(())
}

fn set_boot_status(app: &AppHandle, ready: bool, message: String) {
    if let Some(state) = app.try_state::<Mutex<BootStatus>>() {
        if let Ok(mut status) = state.lock() {
            status.ready = ready;
            status.message = message;
            status.gui_url = gui_url();
        }
    }
}

#[tauri::command]
fn boot_status(state: State<'_, Mutex<BootStatus>>) -> BootStatus {
    state.lock().map(|g| g.clone()).unwrap_or(BootStatus {
        ready: false,
        message: "Starting…".into(),
        gui_url: gui_url(),
    })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(SidecarState(Mutex::new(None)))
        .manage(Mutex::new(BootStatus {
            ready: false,
            message: "Starting Vaporcito…".into(),
            gui_url: gui_url(),
        }))
        .invoke_handler(tauri::generate_handler![boot_status])
        .setup(|app| {
            let handle = app.handle().clone();

            std::thread::spawn(move || {
                if let Err(err) = start_sidecar(&handle) {
                    set_boot_status(&handle, false, err);
                    return;
                }

                set_boot_status(&handle, false, "Waiting for local GUI…".into());
                if let Err(err) = wait_for_health() {
                    set_boot_status(&handle, false, err);
                    stop_sidecar(&handle);
                    return;
                }

                set_boot_status(&handle, true, "Opening GUI…".into());
                if let Err(err) = open_gui_window(&handle) {
                    set_boot_status(&handle, false, err);
                }
            });

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building vaporcito desktop")
        .run(|app_handle, event| {
            if let RunEvent::ExitRequested { .. } | RunEvent::Exit = event {
                stop_sidecar(app_handle);
            }
        });
}
