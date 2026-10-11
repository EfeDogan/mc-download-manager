use std::{convert::Infallible, net::SocketAddr, time::Duration};

use axum::{
    Router,
    body::{Body, Bytes},
    extract::Request,
    http::{HeaderValue, Response, StatusCode, header},
    routing::get,
};
use futures_util::stream;
use mcdm_core::{DownloadManager, DownloadState, serve};
use serde_json::{Value, json};
use tempfile::tempdir;
use tokio::{net::TcpListener, time::sleep};

const CONTENT: &[u8] = b"MC Download Manager cross-platform vertical slice\n";
const SLOW_CONTENT_LENGTH: usize = 512 * 1024;

fn requested_offset(request: &Request) -> usize {
    request
        .headers()
        .get(header::RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("bytes="))
        .and_then(|value| value.strip_suffix('-'))
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(0)
}

async fn source(request: Request) -> Response<Body> {
    let offset = requested_offset(&request).min(CONTENT.len());
    let mut response = Response::new(Body::from(&CONTENT[offset..]));
    if offset > 0 {
        *response.status_mut() = StatusCode::PARTIAL_CONTENT;
        response.headers_mut().insert(
            header::CONTENT_RANGE,
            HeaderValue::from_str(&format!(
                "bytes {offset}-{}/{}",
                CONTENT.len() - 1,
                CONTENT.len()
            ))
            .unwrap(),
        );
    }
    response.headers_mut().insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&(CONTENT.len() - offset).to_string()).unwrap(),
    );
    response
}

async fn slow_source(request: Request) -> Response<Body> {
    let offset = requested_offset(&request).min(SLOW_CONTENT_LENGTH);
    let body = Body::from_stream(stream::unfold(offset, |position| async move {
        if position >= SLOW_CONTENT_LENGTH {
            return None;
        }
        sleep(Duration::from_millis(5)).await;
        let length = (SLOW_CONTENT_LENGTH - position).min(8192);
        Some((
            Ok::<Bytes, Infallible>(Bytes::from(vec![b'x'; length])),
            position + length,
        ))
    }));
    let mut response = Response::new(body);
    if offset > 0 {
        *response.status_mut() = StatusCode::PARTIAL_CONTENT;
        response.headers_mut().insert(
            header::CONTENT_RANGE,
            HeaderValue::from_str(&format!(
                "bytes {offset}-{}/{}",
                SLOW_CONTENT_LENGTH - 1,
                SLOW_CONTENT_LENGTH
            ))
            .unwrap(),
        );
    }
    response.headers_mut().insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&(SLOW_CONTENT_LENGTH - offset).to_string()).unwrap(),
    );
    response
}

async fn start_source() -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(
            listener,
            Router::new()
                .route("/fixture.bin", get(source))
                .route("/slow.bin", get(slow_source)),
        )
        .await
        .unwrap();
    });
    address
}

async fn find_download(client: &reqwest::Client, base: &str, id: &str) -> Value {
    let response = extension_request(
        client,
        reqwest::Method::GET,
        format!("{base}/downloads"),
        None,
    )
    .await;
    let body = response.json::<Value>().await.unwrap();
    body["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["id"] == id)
        .cloned()
        .unwrap()
}

async fn send_action(client: &reqwest::Client, base: &str, id: &str, action: &str) {
    let response = extension_request(
        client,
        reqwest::Method::POST,
        format!("{base}/action"),
        Some(json!({ "id": id, "action": action })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
}

async fn extension_request(
    client: &reqwest::Client,
    method: reqwest::Method,
    url: String,
    body: Option<Value>,
) -> reqwest::Response {
    let mut request = client
        .request(method, url)
        .header("Origin", "chrome-extension://contract-fixture")
        .header("X-MCDM-Extension", "chrome");
    if let Some(body) = body {
        request = request.json(&body);
    }
    request.send().await.unwrap()
}

#[tokio::test]
async fn extension_handoff_downloads_a_file_end_to_end() {
    let source_address = start_source().await;
    let directory = tempdir().unwrap();
    let manager = DownloadManager::new(directory.path()).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let bridge_address = listener.local_addr().unwrap();
    tokio::spawn(async move { serve(listener, manager).await.unwrap() });

    let client = reqwest::Client::new();
    let base = format!("http://{bridge_address}");
    let response =
        extension_request(&client, reqwest::Method::GET, format!("{base}/ping"), None).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.json::<Value>().await.unwrap()["ok"], true);

    let response = extension_request(
        &client,
        reqwest::Method::POST,
        format!("{base}/download"),
        Some(json!({
            "url": format!("http://{source_address}/fixture.bin"),
            "filename": "CON?.bin",
            "kind": "file"
        })),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    let id = response.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_owned();

    let mut completed = false;
    for _ in 0..100 {
        let item = find_download(&client, &base, &id).await;
        if item["state"] == serde_json::to_value(DownloadState::Completed).unwrap() {
            completed = true;
            break;
        }
        sleep(Duration::from_millis(20)).await;
    }
    assert!(completed, "download did not complete in time");
    assert_eq!(
        tokio::fs::read(directory.path().join("CON_.bin"))
            .await
            .unwrap(),
        CONTENT
    );
}

#[tokio::test]
async fn pause_then_immediate_resume_keeps_the_new_transfer_alive() {
    let source_address = start_source().await;
    let directory = tempdir().unwrap();
    let manager = DownloadManager::new(directory.path()).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let bridge_address = listener.local_addr().unwrap();
    tokio::spawn(async move { serve(listener, manager).await.unwrap() });

    let client = reqwest::Client::new();
    let base = format!("http://{bridge_address}");
    let response = extension_request(
        &client,
        reqwest::Method::POST,
        format!("{base}/download"),
        Some(json!({
            "url": format!("http://{source_address}/slow.bin"),
            "filename": "resume.bin",
            "kind": "file"
        })),
    )
    .await;
    let id = response.json::<Value>().await.unwrap()["id"]
        .as_str()
        .unwrap()
        .to_owned();

    for _ in 0..100 {
        let item = find_download(&client, &base, &id).await;
        if item["received"].as_i64().unwrap_or(0) > 0 {
            break;
        }
        sleep(Duration::from_millis(10)).await;
    }
    send_action(&client, &base, &id, "pause").await;
    send_action(&client, &base, &id, "resume").await;

    let mut completed = false;
    for _ in 0..200 {
        let item = find_download(&client, &base, &id).await;
        if item["state"] == serde_json::to_value(DownloadState::Completed).unwrap() {
            completed = true;
            break;
        }
        sleep(Duration::from_millis(10)).await;
    }
    assert!(completed, "resumed download did not complete in time");
    let bytes = tokio::fs::read(directory.path().join("resume.bin"))
        .await
        .unwrap();
    assert_eq!(bytes.len(), SLOW_CONTENT_LENGTH);
    assert!(bytes.iter().all(|byte| *byte == b'x'));
}

#[tokio::test]
async fn ordinary_web_origins_cannot_drive_the_bridge() {
    let directory = tempdir().unwrap();
    let manager = DownloadManager::new(directory.path()).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let bridge_address = listener.local_addr().unwrap();
    tokio::spawn(async move { serve(listener, manager).await.unwrap() });

    let response = reqwest::Client::new()
        .get(format!("http://{bridge_address}/ping"))
        .header("Origin", "https://example.com")
        .header("X-MCDM-Extension", "chrome")
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}
