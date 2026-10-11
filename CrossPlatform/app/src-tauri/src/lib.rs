use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
};

use mcdm_core::{
    BridgeConfig, DownloadAction, DownloadKind, DownloadManager, DownloadRequest, DownloadSummary,
    discover_video_tool, serve,
};
use serde::Serialize;
use serde_json::{Value, json};
use tauri::{
    AppHandle, Manager, State,
    menu::{Menu, MenuItem},
    path::BaseDirectory,
    tray::TrayIconBuilder,
};
use tokio::net::TcpListener;
use uuid::Uuid;

const BRIDGE_STARTING: &str = "starting";

struct AppState {
    manager: DownloadManager,
    bridge_port: u16,
    bridge_status: Arc<RwLock<String>>,
    download_directory: PathBuf,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeInfo {
    bridge_port: u16,
    bridge_status: String,
    download_directory: String,
    video_available: bool,
}

#[tauri::command]
async fn runtime_info(state: State<'_, AppState>) -> Result<RuntimeInfo, String> {
    let bridge_status = state
        .bridge_status
        .read()
        .map_err(|_| "bridge status lock is unavailable".to_owned())?
        .clone();
    Ok(RuntimeInfo {
        bridge_port: state.bridge_port,
        bridge_status,
        download_directory: state.download_directory.display().to_string(),
        video_available: state.manager.video_available(),
    })
}

#[tauri::command]
async fn list_downloads(state: State<'_, AppState>) -> Result<Vec<DownloadSummary>, String> {
    Ok(state.manager.list().await)
}

#[tauri::command]
async fn add_download(
    state: State<'_, AppState>,
    url: String,
    filename: Option<String>,
    kind: DownloadKind,
) -> Result<String, String> {
    let request = DownloadRequest {
        url,
        filename: filename.unwrap_or_default(),
        referer: String::new(),
        user_agent: String::new(),
        cookie_header: String::new(),
        cookies: Vec::new(),
        kind,
        headers: HashMap::new(),
        segments: None,
    };
    state
        .manager
        .add(request)
        .await
        .map(|id| id.to_string())
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn install_browser_extension(app: AppHandle, state: State<'_, AppState>) -> Result<String, String> {
    let source = app
        .path()
        .resolve("browser-extension", BaseDirectory::Resource)
        .map_err(|error| format!("could not locate bundled extension: {error}"))?;
    let destination = state
        .download_directory
        .join("Browser Plugins")
        .join("ChromiumExtension");
    copy_directory(&source, &destination)
        .map_err(|error| format!("could not copy browser extension: {error}"))?;
    Ok(destination.display().to_string())
}

#[tauri::command]
fn install_firefox_extension(app: AppHandle, state: State<'_, AppState>) -> Result<String, String> {
    let source = app
        .path()
        .resolve("browser-extension", BaseDirectory::Resource)
        .map_err(|error| format!("could not locate bundled extension: {error}"))?;
    let destination = state
        .download_directory
        .join("Browser Plugins")
        .join("FirefoxExtension");
    let manifest = prepare_firefox_extension(&source, &destination)?;
    Ok(manifest.display().to_string())
}

fn prepare_firefox_extension(source: &Path, destination: &Path) -> Result<PathBuf, String> {
    copy_directory(source, destination)
        .map_err(|error| format!("could not copy Firefox extension: {error}"))?;
    let manifest_path = destination.join("manifest.json");
    let manifest_bytes = fs::read(&manifest_path)
        .map_err(|error| format!("could not read Firefox manifest: {error}"))?;
    let mut manifest: Value = serde_json::from_slice(&manifest_bytes)
        .map_err(|error| format!("could not parse Firefox manifest: {error}"))?;
    manifest["background"] = json!({ "scripts": ["background.js"] });
    let permissions = manifest
        .get_mut("permissions")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| "Firefox manifest permissions are missing".to_owned())?;
    permissions.retain(|permission| permission.as_str() != Some("nativeMessaging"));
    manifest["browser_specific_settings"] = json!({
        "gecko": {
            "id": "mc-download-manager@mstcvk.github.io",
            "strict_min_version": "140.0",
            "data_collection_permissions": { "required": ["none"] }
        }
    });
    let manifest_bytes = serde_json::to_vec_pretty(&manifest)
        .map_err(|error| format!("could not serialize Firefox manifest: {error}"))?;
    fs::write(&manifest_path, manifest_bytes)
        .map_err(|error| format!("could not write Firefox manifest: {error}"))?;
    Ok(manifest_path)
}

fn copy_directory(source: &Path, destination: &Path) -> std::io::Result<()> {
    fs::create_dir_all(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let target = destination.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_directory(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

#[tauri::command]
async fn download_action(
    state: State<'_, AppState>,
    id: String,
    action: DownloadAction,
) -> Result<(), String> {
    let id = Uuid::parse_str(&id).map_err(|_| "invalid download id".to_owned())?;
    state
        .manager
        .action(id, action)
        .await
        .map_err(|error| error.to_string())
}

fn update_bridge_status(status: &RwLock<String>, value: impl Into<String>) {
    if let Ok(mut current) = status.write() {
        *current = value.into();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let config = BridgeConfig::default();
            let bundled_tool_name = if cfg!(windows) {
                "tools/yt-dlp.exe"
            } else {
                "tools/yt-dlp"
            };
            let bundled_tool = app
                .path()
                .resolve(bundled_tool_name, BaseDirectory::Resource)
                .ok()
                .filter(|path| path.is_file());
            let video_tool = discover_video_tool(bundled_tool);
            let manager =
                DownloadManager::with_video_tool(config.download_directory.clone(), video_tool)?;
            let bridge_status = Arc::new(RwLock::new(BRIDGE_STARTING.to_owned()));

            app.manage(AppState {
                manager: manager.clone(),
                bridge_port: config.port,
                bridge_status: bridge_status.clone(),
                download_directory: config.download_directory.clone(),
            });

            let show =
                MenuItem::with_id(app, "show", "Show MC Download Manager", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;
            let mut tray = TrayIconBuilder::new()
                .tooltip("MC Download Manager")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.build(app)?;

            tauri::async_runtime::spawn(async move {
                let address = format!("127.0.0.1:{}", config.port);
                match TcpListener::bind(&address).await {
                    Ok(listener) => {
                        update_bridge_status(&bridge_status, "running");
                        if let Err(error) = serve(listener, manager).await {
                            update_bridge_status(&bridge_status, format!("error: {error}"));
                        }
                    }
                    Err(error) => {
                        update_bridge_status(&bridge_status, format!("error: {error}"));
                    }
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            runtime_info,
            list_downloads,
            add_download,
            download_action,
            install_browser_extension,
            install_firefox_extension
        ])
        .run(tauri::generate_context!())
        .expect("error while running MC Download Manager");
}

#[cfg(test)]
mod tests {
    use std::{env, fs};

    use uuid::Uuid;

    use super::{copy_directory, prepare_firefox_extension};

    #[test]
    fn copies_nested_browser_extension_files() {
        let root = env::temp_dir().join(format!("mcdm-extension-test-{}", Uuid::new_v4()));
        let source = root.join("source");
        let destination = root.join("destination");
        fs::create_dir_all(source.join("icons")).unwrap();
        fs::write(source.join("manifest.json"), b"{}").unwrap();
        fs::write(source.join("icons/icon.png"), b"icon").unwrap();

        copy_directory(&source, &destination).unwrap();

        assert_eq!(fs::read(destination.join("manifest.json")).unwrap(), b"{}");
        assert_eq!(
            fs::read(destination.join("icons/icon.png")).unwrap(),
            b"icon"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn prepares_a_firefox_specific_manifest_without_changing_the_source() {
        let root = env::temp_dir().join(format!("mcdm-firefox-test-{}", Uuid::new_v4()));
        let source = root.join("source");
        let destination = root.join("destination");
        fs::create_dir_all(&source).unwrap();
        let chromium_manifest = br#"{
          "manifest_version": 3,
          "permissions": ["downloads", "nativeMessaging"],
          "background": {"service_worker": "background.js"}
        }"#;
        fs::write(source.join("manifest.json"), chromium_manifest).unwrap();
        fs::write(source.join("background.js"), b"// fixture").unwrap();

        let manifest_path = prepare_firefox_extension(&source, &destination).unwrap();
        let manifest: serde_json::Value =
            serde_json::from_slice(&fs::read(manifest_path).unwrap()).unwrap();

        assert_eq!(manifest["background"]["scripts"][0], "background.js");
        assert!(manifest["background"].get("service_worker").is_none());
        assert_eq!(
            manifest["browser_specific_settings"]["gecko"]["id"],
            "mc-download-manager@mstcvk.github.io"
        );
        assert!(
            manifest["permissions"]
                .as_array()
                .unwrap()
                .iter()
                .all(|permission| permission != "nativeMessaging")
        );
        assert_eq!(
            fs::read(source.join("manifest.json")).unwrap(),
            chromium_manifest
        );
        fs::remove_dir_all(root).unwrap();
    }
}
