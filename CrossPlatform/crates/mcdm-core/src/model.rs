use std::collections::HashMap;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadKind {
    #[default]
    File,
    Video,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub enum VideoQuality {
    #[serde(rename = "best")]
    Best,
    #[serde(rename = "2160p")]
    P2160,
    #[serde(rename = "1440p")]
    P1440,
    #[default]
    #[serde(rename = "1080p")]
    P1080,
    #[serde(rename = "720p")]
    P720,
    #[serde(rename = "480p")]
    P480,
    #[serde(rename = "360p")]
    P360,
}

impl VideoQuality {
    pub fn max_height(self) -> Option<u16> {
        match self {
            Self::Best => None,
            Self::P2160 => Some(2160),
            Self::P1440 => Some(1440),
            Self::P1080 => Some(1080),
            Self::P720 => Some(720),
            Self::P480 => Some(480),
            Self::P360 => Some(360),
        }
    }
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
    pub video_quality: Option<VideoQuality>,
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
