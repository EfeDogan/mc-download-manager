use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Arc,
    time::Instant,
};

use futures_util::StreamExt;
use reqwest::{StatusCode, Url, header};
use thiserror::Error;
use tokio::{
    fs::{self, OpenOptions},
    io::AsyncWriteExt,
    sync::{Mutex, RwLock},
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    filename::{sanitize, unique_destination},
    model::{DownloadAction, DownloadKind, DownloadRequest, DownloadState, DownloadSummary},
};

#[derive(Debug, Error)]
pub enum DownloadError {
    #[error("invalid URL")]
    InvalidUrl,
    #[error("video downloads are not implemented in the first cross-platform slice")]
    VideoNotImplemented,
    #[error("download not found")]
    NotFound,
    #[error("action is not valid for the current download state")]
    InvalidAction,
    #[error("request failed: {0}")]
    Request(#[from] reqwest::Error),
    #[error("file operation failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("server returned HTTP {0}")]
    Http(StatusCode),
    #[error("download was interrupted")]
    Interrupted,
}

#[derive(Clone)]
pub struct DownloadManager {
    inner: Arc<Inner>,
}

struct Inner {
    directory: PathBuf,
    client: reqwest::Client,
    entries: RwLock<HashMap<Uuid, Entry>>,
    controls: Mutex<HashMap<Uuid, (u64, CancellationToken)>>,
}

#[derive(Clone)]
struct Entry {
    request: DownloadRequest,
    summary: DownloadSummary,
    part_path: PathBuf,
    final_path: Option<PathBuf>,
    generation: u64,
}

impl DownloadManager {
    pub fn new(directory: impl Into<PathBuf>) -> Result<Self, DownloadError> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::limited(10))
            .build()?;
        Ok(Self {
            inner: Arc::new(Inner {
                directory: directory.into(),
                client,
                entries: RwLock::new(HashMap::new()),
                controls: Mutex::new(HashMap::new()),
            }),
        })
    }

    pub fn directory(&self) -> &Path {
        &self.inner.directory
    }

    pub async fn add(&self, request: DownloadRequest) -> Result<Uuid, DownloadError> {
        let url = Url::parse(&request.url).map_err(|_| DownloadError::InvalidUrl)?;
        if !matches!(url.scheme(), "http" | "https") {
            return Err(DownloadError::InvalidUrl);
        }
        if request.kind == DownloadKind::Video {
            return Err(DownloadError::VideoNotImplemented);
        }

        fs::create_dir_all(&self.inner.directory).await?;
        let id = Uuid::new_v4();
        let inferred = url
            .path_segments()
            .and_then(|mut segments| segments.next_back())
            .filter(|value| !value.is_empty())
            .unwrap_or("download");
        let name = sanitize(if request.filename.trim().is_empty() {
            inferred
        } else {
            &request.filename
        });
        let entry = Entry {
            request,
            summary: DownloadSummary {
                id: id.to_string(),
                name,
                state: DownloadState::Queued,
                progress: 0.0,
                speed: 0.0,
                total: -1,
                received: 0,
                stage: String::new(),
                error: None,
            },
            part_path: self.inner.directory.join(format!(".mcdm-{id}.part")),
            final_path: None,
            generation: 0,
        };
        self.inner.entries.write().await.insert(id, entry);
        self.spawn(id).await;
        Ok(id)
    }

    pub async fn list(&self) -> Vec<DownloadSummary> {
        let mut items: Vec<_> = self
            .inner
            .entries
            .read()
            .await
            .values()
            .map(|entry| entry.summary.clone())
            .collect();
        items.sort_by(|left, right| right.id.cmp(&left.id));
        items
    }

    pub async fn active_count(&self) -> usize {
        self.inner
            .entries
            .read()
            .await
            .values()
            .filter(|entry| entry.summary.state.is_active())
            .count()
    }

    pub async fn action(&self, id: Uuid, action: DownloadAction) -> Result<(), DownloadError> {
        match action {
            DownloadAction::Pause => {
                let mut entries = self.inner.entries.write().await;
                let entry = entries.get_mut(&id).ok_or(DownloadError::NotFound)?;
                if !matches!(
                    entry.summary.state,
                    DownloadState::Queued | DownloadState::Probing | DownloadState::Downloading
                ) {
                    return Err(DownloadError::InvalidAction);
                }
                entry.summary.state = DownloadState::Paused;
                entry.summary.speed = 0.0;
                drop(entries);
                self.cancel_running(id).await;
            }
            DownloadAction::Resume => {
                let mut entries = self.inner.entries.write().await;
                let entry = entries.get_mut(&id).ok_or(DownloadError::NotFound)?;
                if !matches!(
                    entry.summary.state,
                    DownloadState::Paused | DownloadState::Failed | DownloadState::Cancelled
                ) {
                    return Err(DownloadError::InvalidAction);
                }
                entry.summary.state = DownloadState::Queued;
                entry.summary.error = None;
                drop(entries);
                self.spawn(id).await;
            }
            DownloadAction::Cancel => {
                let mut entries = self.inner.entries.write().await;
                let entry = entries.get_mut(&id).ok_or(DownloadError::NotFound)?;
                if entry.summary.state == DownloadState::Completed {
                    return Err(DownloadError::InvalidAction);
                }
                entry.summary.state = DownloadState::Cancelled;
                entry.summary.speed = 0.0;
                drop(entries);
                self.cancel_running(id).await;
            }
            DownloadAction::Remove => {
                self.cancel_running(id).await;
                let entry = self
                    .inner
                    .entries
                    .write()
                    .await
                    .remove(&id)
                    .ok_or(DownloadError::NotFound)?;
                if entry.final_path.is_none() {
                    for _ in 0..20 {
                        match fs::remove_file(&entry.part_path).await {
                            Ok(()) => break,
                            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
                            Err(_) => {
                                tokio::time::sleep(std::time::Duration::from_millis(10)).await
                            }
                        }
                    }
                }
            }
        }
        Ok(())
    }

    async fn cancel_running(&self, id: Uuid) {
        if let Some((_, token)) = self.inner.controls.lock().await.get(&id) {
            token.cancel();
        }
    }

    async fn spawn(&self, id: Uuid) {
        let generation = {
            let mut entries = self.inner.entries.write().await;
            let Some(entry) = entries.get_mut(&id) else {
                return;
            };
            entry.generation += 1;
            entry.generation
        };
        let token = CancellationToken::new();
        self.inner
            .controls
            .lock()
            .await
            .insert(id, (generation, token.clone()));
        let manager = self.clone();
        tokio::spawn(async move {
            let result = manager.transfer(id, generation, token).await;
            manager.finish(id, generation, result).await;
        });
    }

    async fn transfer(
        &self,
        id: Uuid,
        generation: u64,
        token: CancellationToken,
    ) -> Result<PathBuf, DownloadError> {
        let (request, part_path, name) = {
            let mut entries = self.inner.entries.write().await;
            let entry = entries.get_mut(&id).ok_or(DownloadError::NotFound)?;
            if entry.generation != generation {
                return Err(DownloadError::Interrupted);
            }
            entry.summary.state = DownloadState::Probing;
            entry.summary.stage = "Connecting".to_owned();
            (
                entry.request.clone(),
                entry.part_path.clone(),
                entry.summary.name.clone(),
            )
        };

        let url = Url::parse(&request.url).map_err(|_| DownloadError::InvalidUrl)?;
        let existing = fs::metadata(&part_path)
            .await
            .map(|metadata| metadata.len())
            .unwrap_or(0);
        let mut builder = self.inner.client.get(url);
        for (name, value) in &request.headers {
            builder = builder.header(name, value);
        }
        if !request.referer.is_empty() {
            builder = builder.header(header::REFERER, &request.referer);
        }
        if !request.user_agent.is_empty() {
            builder = builder.header(header::USER_AGENT, &request.user_agent);
        }
        if !request.cookie_header.is_empty() {
            builder = builder.header(header::COOKIE, &request.cookie_header);
        }
        if existing > 0 {
            builder = builder.header(header::RANGE, format!("bytes={existing}-"));
        }

        let response = tokio::select! {
            _ = token.cancelled() => return Err(DownloadError::Interrupted),
            response = builder.send() => response?,
        };
        if !response.status().is_success() {
            return Err(DownloadError::Http(response.status()));
        }

        let resumed = existing > 0 && response.status() == StatusCode::PARTIAL_CONTENT;
        let offset = if resumed { existing } else { 0 };
        let total = response.content_length().map(|length| length + offset);
        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .append(resumed)
            .truncate(!resumed)
            .open(&part_path)
            .await?;

        {
            let mut entries = self.inner.entries.write().await;
            let entry = entries.get_mut(&id).ok_or(DownloadError::NotFound)?;
            if entry.generation != generation {
                return Err(DownloadError::Interrupted);
            }
            entry.summary.state = DownloadState::Downloading;
            entry.summary.stage.clear();
            entry.summary.received = offset as i64;
            entry.summary.total = total.map(|value| value as i64).unwrap_or(-1);
        }

        let started = Instant::now();
        let mut received = offset;
        let mut stream = response.bytes_stream();
        loop {
            let chunk = tokio::select! {
                _ = token.cancelled() => return Err(DownloadError::Interrupted),
                chunk = stream.next() => chunk,
            };
            let Some(chunk) = chunk else { break };
            let chunk = chunk?;
            file.write_all(&chunk).await?;
            received += chunk.len() as u64;

            let elapsed = started.elapsed().as_secs_f64().max(0.001);
            let mut entries = self.inner.entries.write().await;
            let entry = entries.get_mut(&id).ok_or(DownloadError::NotFound)?;
            if entry.generation != generation {
                return Err(DownloadError::Interrupted);
            }
            entry.summary.received = received as i64;
            entry.summary.progress = total
                .map(|value| received as f64 / value as f64)
                .unwrap_or(0.0)
                .min(1.0);
            entry.summary.speed = (received - offset) as f64 / elapsed;
        }
        file.flush().await?;
        drop(file);

        let destination = unique_destination(&self.inner.directory, &name).await;
        fs::rename(&part_path, &destination).await?;
        Ok(destination)
    }

    async fn finish(&self, id: Uuid, generation: u64, result: Result<PathBuf, DownloadError>) {
        {
            let mut controls = self.inner.controls.lock().await;
            if controls
                .get(&id)
                .is_some_and(|(current, _)| *current == generation)
            {
                controls.remove(&id);
            }
        }
        let mut cleanup_part = None;
        let mut entries = self.inner.entries.write().await;
        let Some(entry) = entries.get_mut(&id) else {
            return;
        };
        if entry.generation != generation {
            return;
        }
        match result {
            Ok(path) => {
                entry.summary.state = DownloadState::Completed;
                entry.summary.progress = 1.0;
                entry.summary.speed = 0.0;
                entry.summary.stage.clear();
                entry.summary.error = None;
                if entry.summary.total <= 0 {
                    entry.summary.total = entry.summary.received;
                }
                entry.final_path = Some(path);
            }
            Err(DownloadError::Interrupted) => {
                entry.summary.speed = 0.0;
                if entry.summary.state == DownloadState::Cancelled {
                    entry.summary.received = 0;
                    entry.summary.progress = 0.0;
                    cleanup_part = Some(entry.part_path.clone());
                } else if entry.summary.state != DownloadState::Paused {
                    entry.summary.state = DownloadState::Paused;
                }
            }
            Err(error) => {
                entry.summary.state = DownloadState::Failed;
                entry.summary.speed = 0.0;
                entry.summary.error = Some(error.to_string());
            }
        }
        drop(entries);
        if let Some(path) = cleanup_part {
            let _ = fs::remove_file(path).await;
        }
    }
}
