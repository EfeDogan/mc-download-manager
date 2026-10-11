use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use mcdm_core::{
    BridgeConfig, DownloadAction, DownloadKind, DownloadManager, DownloadRequest, DownloadSummary,
    serve,
};
use serde::Serialize;
use tauri::{
    Manager, State,
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
};
use tokio::net::TcpListener;
use uuid::Uuid;

const BRIDGE_STARTING: &str = "starting";

struct AppState {
    manager: DownloadManager,
    bridge_port: u16,
    bridge_status: Arc<RwLock<String>>,
    download_directory: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeInfo {
    bridge_port: u16,
    bridge_status: String,
    download_directory: String,
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
        download_directory: state.download_directory.clone(),
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
) -> Result<String, String> {
    let request = DownloadRequest {
        url,
        filename: filename.unwrap_or_default(),
        referer: String::new(),
        user_agent: String::new(),
        cookie_header: String::new(),
        cookies: Vec::new(),
        kind: DownloadKind::File,
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
            let manager = DownloadManager::new(config.download_directory.clone())?;
            let bridge_status = Arc::new(RwLock::new(BRIDGE_STARTING.to_owned()));

            app.manage(AppState {
                manager: manager.clone(),
                bridge_port: config.port,
                bridge_status: bridge_status.clone(),
                download_directory: config.download_directory.display().to_string(),
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
            download_action
        ])
        .run(tauri::generate_context!())
        .expect("error while running MC Download Manager");
}
