use std::{net::SocketAddr, path::PathBuf};

use axum::{
    Json, Router,
    extract::{Request, State},
    http::{HeaderMap, HeaderValue, Method, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::net::TcpListener;
use uuid::Uuid;

use crate::{
    download::DownloadManager,
    model::{DownloadAction, DownloadRequest},
};

const ORIGIN_PREFIXES: &[&str] = &[
    "chrome-extension://",
    "safari-web-extension://",
    "moz-extension://",
];

#[derive(Clone, Debug)]
pub struct BridgeConfig {
    pub port: u16,
    pub download_directory: PathBuf,
}

impl Default for BridgeConfig {
    fn default() -> Self {
        let download_directory = dirs::download_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("MC Download Manager");
        Self {
            port: 48213,
            download_directory,
        }
    }
}

#[derive(Clone)]
struct BridgeState {
    manager: DownloadManager,
    port: u16,
}

#[derive(Deserialize)]
struct ActionRequest {
    id: String,
    action: DownloadAction,
}

pub async fn serve(listener: TcpListener, manager: DownloadManager) -> std::io::Result<()> {
    let port = listener.local_addr()?.port();
    axum::serve(listener, router(manager, port)).await
}

pub async fn run(config: BridgeConfig) -> Result<(), Box<dyn std::error::Error>> {
    let manager = DownloadManager::new(config.download_directory)?;
    let address = SocketAddr::from(([127, 0, 0, 1], config.port));
    let listener = TcpListener::bind(address).await?;
    serve(listener, manager).await?;
    Ok(())
}

pub fn router(manager: DownloadManager, port: u16) -> Router {
    let state = BridgeState { manager, port };
    Router::new()
        .route("/ping", get(ping).options(preflight))
        .route("/download", post(download).options(preflight))
        .route("/downloads", get(downloads).options(preflight))
        .route("/action", post(action).options(preflight))
        .fallback(not_found)
        .layer(middleware::from_fn_with_state(state.clone(), authorize))
        .with_state(state)
}

async fn authorize(State(state): State<BridgeState>, request: Request, next: Next) -> Response {
    let headers = request.headers();
    if !host_allowed(headers, state.port) || !extension_request(headers) {
        return json_error(StatusCode::FORBIDDEN, "forbidden");
    }

    let allowed_origin = headers
        .get(header::ORIGIN)
        .and_then(|value| value.to_str().ok())
        .filter(|origin| origin_allowed(origin))
        .map(str::to_owned);
    let mut response = next.run(request).await;
    let response_headers = response.headers_mut();
    response_headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response_headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    if let Some(origin) = allowed_origin.and_then(|value| HeaderValue::from_str(&value).ok()) {
        response_headers.insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, origin);
        response_headers.insert(header::VARY, HeaderValue::from_static("Origin"));
        response_headers.insert(
            header::ACCESS_CONTROL_ALLOW_HEADERS,
            HeaderValue::from_static("Content-Type, X-MCDM-Extension"),
        );
        response_headers.insert(
            header::ACCESS_CONTROL_ALLOW_METHODS,
            HeaderValue::from_static("GET, POST, OPTIONS"),
        );
        response_headers.insert(
            HeaderNameExt::private_network(),
            HeaderValue::from_static("true"),
        );
        response_headers.insert(
            HeaderNameExt::local_network(),
            HeaderValue::from_static("true"),
        );
    }
    response
}

struct HeaderNameExt;

impl HeaderNameExt {
    fn private_network() -> header::HeaderName {
        header::HeaderName::from_static("access-control-allow-private-network")
    }

    fn local_network() -> header::HeaderName {
        header::HeaderName::from_static("access-control-allow-local-network")
    }
}

fn origin_allowed(origin: &str) -> bool {
    !origin.is_empty()
        && origin != "null"
        && ORIGIN_PREFIXES
            .iter()
            .any(|prefix| origin.starts_with(prefix))
}

fn extension_request(headers: &HeaderMap) -> bool {
    match headers
        .get(header::ORIGIN)
        .and_then(|value| value.to_str().ok())
    {
        Some(origin) => origin_allowed(origin),
        None => headers
            .get("x-mcdm-extension")
            .and_then(|value| value.to_str().ok())
            .is_some_and(|value| !value.is_empty()),
    }
}

fn host_allowed(headers: &HeaderMap, port: u16) -> bool {
    let Some(host) = headers
        .get(header::HOST)
        .and_then(|value| value.to_str().ok())
    else {
        return false;
    };
    let host = host.to_ascii_lowercase();
    host == format!("127.0.0.1:{port}")
        || host == format!("localhost:{port}")
        || host == format!("[::1]:{port}")
}

async fn preflight(method: Method) -> impl IntoResponse {
    if method == Method::OPTIONS {
        Json(json!({ "ok": true })).into_response()
    } else {
        json_error(StatusCode::METHOD_NOT_ALLOWED, "method not allowed")
    }
}

async fn ping(State(state): State<BridgeState>) -> Json<Value> {
    Json(json!({
        "ok": true,
        "app": "MCDownloadManager",
        "version": env!("CARGO_PKG_VERSION"),
        "ytdlp": false,
        "active": state.manager.active_count().await,
        "captureExtensions": default_capture_extensions(),
    }))
}

async fn downloads(State(state): State<BridgeState>) -> Json<Value> {
    Json(json!({ "ok": true, "items": state.manager.list().await }))
}

async fn download(
    State(state): State<BridgeState>,
    Json(request): Json<DownloadRequest>,
) -> Response {
    match state.manager.add(request).await {
        Ok(id) => Json(json!({ "ok": true, "id": id.to_string() })).into_response(),
        Err(error) => json_error(StatusCode::BAD_REQUEST, &error.to_string()),
    }
}

async fn action(State(state): State<BridgeState>, Json(request): Json<ActionRequest>) -> Response {
    let Ok(id) = Uuid::parse_str(&request.id) else {
        return json_error(StatusCode::BAD_REQUEST, "id and action required");
    };
    match state.manager.action(id, request.action).await {
        Ok(()) => Json(json!({ "ok": true })).into_response(),
        Err(error) => json_error(StatusCode::BAD_REQUEST, &error.to_string()),
    }
}

async fn not_found() -> Response {
    json_error(StatusCode::NOT_FOUND, "not found")
}

fn json_error(status: StatusCode, message: &str) -> Response {
    (status, Json(json!({ "ok": false, "error": message }))).into_response()
}

fn default_capture_extensions() -> &'static [&'static str] {
    &[
        "7z", "aac", "apk", "avi", "bin", "bz2", "csv", "deb", "dmg", "doc", "docx", "epub", "exe",
        "flac", "gz", "iso", "jar", "m4a", "mkv", "mobi", "mov", "mp3", "mp4", "msi", "pdf", "pkg",
        "ppt", "pptx", "rar", "rpm", "tar", "tgz", "wav", "webm", "xls", "xlsx", "xz", "zip",
    ]
}

#[cfg(test)]
mod tests {
    use axum::http::{HeaderMap, HeaderValue, header};

    use super::{extension_request, host_allowed, origin_allowed};

    #[test]
    fn accepts_only_extension_origins() {
        assert!(origin_allowed("chrome-extension://abc"));
        assert!(origin_allowed("moz-extension://abc"));
        assert!(!origin_allowed("https://example.com"));
        assert!(!origin_allowed("null"));
    }

    #[test]
    fn missing_origin_requires_marker() {
        let mut headers = HeaderMap::new();
        assert!(!extension_request(&headers));
        headers.insert("x-mcdm-extension", HeaderValue::from_static("chrome"));
        assert!(extension_request(&headers));
        headers.insert(
            header::ORIGIN,
            HeaderValue::from_static("https://example.com"),
        );
        assert!(!extension_request(&headers));
    }

    #[test]
    fn host_must_match_loopback_and_active_port() {
        let mut headers = HeaderMap::new();
        headers.insert(header::HOST, HeaderValue::from_static("127.0.0.1:48213"));
        assert!(host_allowed(&headers, 48213));
        assert!(!host_allowed(&headers, 9999));
    }
}
