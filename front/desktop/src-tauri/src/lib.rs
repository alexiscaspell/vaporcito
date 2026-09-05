use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
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

fn app_data_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map_err(|e| format!("app data dir: {e}"))
}

fn sidecar_log_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app_data_dir(app)?.join("vaporcito-sidecar.log"))
}

fn open_sidecar_log(path: &Path) -> Result<File, String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("create log dir: {e}"))?;
    }
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|e| format!("open sidecar log: {e}"))
}

fn write_log_line(file: &Mutex<Option<File>>, line: &str) {
    #[cfg(debug_assertions)]
    {
        eprint!("[vaporcito] {line}");
        if !line.ends_with('\n') {
            eprintln!();
        }
    }

    if let Ok(mut guard) = file.lock() {
        if let Some(f) = guard.as_mut() {
            let _ = writeln!(f, "{line}");
            let _ = f.flush();
        }
    }
}

/// Force options.startBrowser=false so the Go engine never calls xdg-open / browser.
fn ensure_start_browser_disabled(config_path: &Path) -> Result<(), String> {
    if !config_path.exists() {
        return Ok(());
    }

    let original =
        std::fs::read_to_string(config_path).map_err(|e| format!("read config.xml: {e}"))?;
    let mut updated = original.replace(
        "<startBrowser>true</startBrowser>",
        "<startBrowser>false</startBrowser>",
    );
    updated = updated.replace(
        "<startBrowser>True</startBrowser>",
        "<startBrowser>false</startBrowser>",
    );

    if !updated.contains("<startBrowser>") {
        if let Some(idx) = updated.find("<options>") {
            let insert_at = idx + "<options>".len();
            updated.insert_str(insert_at, "\n        <startBrowser>false</startBrowser>");
        }
    }

    if updated != original {
        std::fs::write(config_path, updated).map_err(|e| format!("write config.xml: {e}"))?;
    }
    Ok(())
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

fn start_sidecar(app: &AppHandle, log_file: &'static Mutex<Option<File>>) -> Result<(), String> {
    let data = app_data_dir(app)?;
    let home = data.join("config");
    std::fs::create_dir_all(&home).map_err(|e| format!("create config dir: {e}"))?;

    let config_xml = home.join("config.xml");
    ensure_start_browser_disabled(&config_xml)?;

    let log_path = sidecar_log_path(app)?;
    {
        let mut guard = log_file.lock().map_err(|_| "log lock poisoned")?;
        *guard = Some(open_sidecar_log(&log_path)?);
    }
    write_log_line(
        log_file,
        &format!("--- sidecar start {} ---", chrono_like_now()),
    );

    let home_str = home.to_string_lossy().to_string();
    let gui_address = format!("http://{GUI_HOST}:{GUI_PORT}");

    // --no-browser: never open the system browser (GUI stays in this WebView).
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
                    write_log_line(log_file, &text);
                }
                tauri_plugin_shell::process::CommandEvent::Terminated(payload) => {
                    write_log_line(log_file, &format!("exited: {payload:?}"));
                    break;
                }
                _ => {}
            }
        }
    });

    Ok(())
}

fn chrono_like_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("unix:{secs}")
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

/// Load the engine GUI inside the existing native window (never the system browser).
fn open_gui_window(app: &AppHandle) -> Result<(), String> {
    let url = gui_url()
        .parse()
        .map_err(|e| format!("invalid gui url: {e}"))?;

    // Patch config again in case the engine just generated defaults with startBrowser=true.
    if let Ok(data) = app_data_dir(app) {
        let _ = ensure_start_browser_disabled(&data.join("config").join("config.xml"));
    }

    if let Some(window) = app.get_webview_window("main") {
        window
            .navigate(url)
            .map_err(|e| format!("navigate to gui: {e}"))?;
        let _ = window.show();
        let _ = window.set_focus();
        return Ok(());
    }

    let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::External(url))
        .title("Vaporcito")
        .inner_size(1280.0, 800.0)
        .focused(true)
        .build()
        .map_err(|e| format!("create gui window: {e}"))?;
    let _ = window.set_focus();
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
    // Process-lifetime log handle shared with the sidecar reader task.
    static SIDECAR_LOG: Mutex<Option<File>> = Mutex::new(None);

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
                if let Err(err) = start_sidecar(&handle, &SIDECAR_LOG) {
                    set_boot_status(&handle, false, err);
                    return;
                }

                set_boot_status(
                    &handle,
                    false,
                    "Waiting for local engine (GUI stays in this window)…".into(),
                );
                if let Err(err) = wait_for_health() {
                    set_boot_status(&handle, false, err);
                    stop_sidecar(&handle);
                    return;
                }

                // Engine may have just written config.xml with startBrowser=true.
                if let Ok(data) = app_data_dir(&handle) {
                    let _ = ensure_start_browser_disabled(&data.join("config").join("config.xml"));
                }

                set_boot_status(&handle, true, "Loading GUI in desktop window…".into());
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
