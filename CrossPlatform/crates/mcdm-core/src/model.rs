use std::collections::HashMap;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadKind {
    #[default]
    File,
    Video,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadState {
    Queued,
    Probing,
    Downloading,
    Paused,
    Completed,
    Failed,
    Cancelled,
}

impl DownloadState {
    pub fn is_active(self) -> bool {
        matches!(self, Self::Probing | Self::Downloading)
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadRequest {
    pub url: String,
    #[serde(default)]
    pub filename: String,
    #[serde(default)]
    pub referer: String,
    #[serde(default)]
    pub user_agent: String,
    #[serde(default)]
    pub cookie_header: String,
    #[serde(default)]
    pub cookies: Vec<serde_json::Value>,
    #[serde(default)]
    pub kind: DownloadKind,
    #[serde(default)]
    pub headers: HashMap<String, String>,
    pub segments: Option<u16>,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadAction {
    Pause,
    Resume,
    Cancel,
    Remove,
}

#[derive(Clone, Debug, Serialize)]
pub struct DownloadSummary {
    pub id: String,
    pub name: String,
    pub state: DownloadState,
    pub progress: f64,
    pub speed: f64,
    pub total: i64,
    pub received: i64,
    pub stage: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}
