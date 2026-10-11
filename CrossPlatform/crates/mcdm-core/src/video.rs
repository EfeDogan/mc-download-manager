use std::{env, path::PathBuf, process::Stdio};

use thiserror::Error;
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    process::{Child, Command},
    sync::mpsc::{UnboundedSender, unbounded_channel},
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::model::DownloadRequest;

#[derive(Debug)]
pub enum VideoEvent {
    Progress {
        received: i64,
        total: i64,
        speed: f64,
    },
    Stage(String),
}

#[derive(Debug, Error)]
pub enum VideoError {
    #[error("could not start yt-dlp: {0}")]
    Spawn(#[source] std::io::Error),
    #[error("yt-dlp was interrupted")]
    Interrupted,
    #[error("yt-dlp exited unsuccessfully: {0}")]
    Failed(String),
    #[error("yt-dlp finished without reporting an output file")]
    MissingOutput,
    #[error("could not prepare browser cookies: {0}")]
    Cookies(#[source] std::io::Error),
}

pub async fn download(
    executable: PathBuf,
    request: DownloadRequest,
    output_directory: PathBuf,
    token: CancellationToken,
    events: UnboundedSender<VideoEvent>,
) -> Result<PathBuf, VideoError> {
    let cookie_file = write_cookie_file(&output_directory, &request.cookies).await?;
    let ffmpeg = discover_ffmpeg();
    let mut command = Command::new(executable);
    command
        .arg("--newline")
        .arg("--no-playlist")
        .arg("--no-colors")
        .arg("--progress")
        .arg("--no-simulate")
        .arg("--no-mtime")
        .arg("--no-quiet")
        .arg("-N")
        .arg("4")
        .arg("-P")
        .arg(&output_directory)
        .arg("-o")
        .arg("%(title).150B [%(id)s].%(ext)s")
        .arg("-f")
        .arg(if ffmpeg.is_some() {
            "bv*[height<=1080]+ba/b[height<=1080]/b"
        } else {
            "b[height<=1080]/b"
        })
        .arg("--progress-template")
        .arg("download:MCDM_PROGRESS:%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s")
        .arg("--print")
        .arg("after_move:MCDM_FILE:%(filepath)s");
    if let Some(path) = ffmpeg {
        command
            .arg("--ffmpeg-location")
            .arg(path)
            .arg("--merge-output-format")
            .arg("mp4")
            .arg("--remux-video")
            .arg("mp4");
    }

    add_header(&mut command, "User-Agent", &request.user_agent);
    add_header(&mut command, "Referer", &request.referer);
    if let Some(path) = &cookie_file {
        command.arg("--cookies").arg(path);
    } else {
        add_header(&mut command, "Cookie", &request.cookie_header);
    }
    for (name, value) in request.headers {
        add_header(&mut command, &name, &value);
    }
    command
        .arg(&request.url)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            if let Some(path) = cookie_file {
                let _ = tokio::fs::remove_file(path).await;
            }
            return Err(VideoError::Spawn(error));
        }
    };
    let result = tokio::select! {
        _ = token.cancelled() => Err(VideoError::Interrupted),
        result = consume(child, events) => result,
    };
    if let Some(path) = cookie_file {
        let _ = tokio::fs::remove_file(path).await;
    }
    result
}

fn discover_ffmpeg() -> Option<PathBuf> {
    let executable_name = if cfg!(windows) {
        "ffmpeg.exe"
    } else {
        "ffmpeg"
    };
    let mut candidates = Vec::new();
    if let Some(path) = env::var_os("MCDM_FFMPEG") {
        candidates.push(PathBuf::from(path));
    }
    if let Ok(current) = env::current_exe()
        && let Some(directory) = current.parent()
    {
        candidates.push(directory.join(executable_name));
        candidates.push(directory.join("tools").join(executable_name));
    }
    if let Some(path) = env::var_os("PATH") {
        candidates.extend(env::split_paths(&path).map(|directory| directory.join(executable_name)));
    }
    candidates.into_iter().find(|path| path.is_file())
}

async fn write_cookie_file(
    output_directory: &std::path::Path,
    cookies: &[serde_json::Value],
) -> Result<Option<PathBuf>, VideoError> {
    if cookies.is_empty() {
        return Ok(None);
    }
    let path = output_directory.join(format!(".mcdm-cookies-{}.txt", Uuid::new_v4()));
    let mut body = String::from("# Netscape HTTP Cookie File\n");
    for cookie in cookies {
        let Some(name) = cookie.get("name").and_then(|value| value.as_str()) else {
            continue;
        };
        let Some(value) = cookie.get("value").and_then(|value| value.as_str()) else {
            continue;
        };
        let Some(domain) = cookie.get("domain").and_then(|value| value.as_str()) else {
            continue;
        };
        if [name, value, domain]
            .iter()
            .any(|field| field.contains(['\t', '\r', '\n']))
        {
            continue;
        }
        let cookie_path = cookie
            .get("path")
            .and_then(|value| value.as_str())
            .filter(|path| !path.contains(['\t', '\r', '\n']))
            .unwrap_or("/");
        let include_subdomains = if domain.starts_with('.') {
            "TRUE"
        } else {
            "FALSE"
        };
        let secure = if cookie
            .get("secure")
            .and_then(|value| value.as_bool())
            .unwrap_or(false)
        {
            "TRUE"
        } else {
            "FALSE"
        };
        let expires = cookie
            .get("expirationDate")
            .and_then(|value| value.as_f64())
            .map(|value| value as i64)
            .unwrap_or(0);
        body.push_str(&format!(
            "{domain}\t{include_subdomains}\t{cookie_path}\t{secure}\t{expires}\t{name}\t{value}\n"
        ));
    }
    tokio::fs::write(&path, body)
        .await
        .map_err(VideoError::Cookies)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        tokio::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
            .await
            .map_err(VideoError::Cookies)?;
    }
    Ok(Some(path))
}

fn add_header(command: &mut Command, name: &str, value: &str) {
    if !name.is_empty()
        && !value.is_empty()
        && !name.contains(['\r', '\n', ':'])
        && !value.contains(['\r', '\n'])
    {
        command.arg("--add-header").arg(format!("{name}:{value}"));
    }
}

async fn consume(
    mut child: Child,
    events: UnboundedSender<VideoEvent>,
) -> Result<PathBuf, VideoError> {
    let stdout = child.stdout.take().ok_or(VideoError::MissingOutput)?;
    let stderr = child.stderr.take().ok_or(VideoError::MissingOutput)?;
    let (lines_tx, mut lines_rx) = unbounded_channel();
    tokio::spawn(read_lines(stdout, lines_tx.clone()));
    tokio::spawn(read_lines(stderr, lines_tx));

    let mut final_path = None;
    let mut last_error = None;
    let mut exit_status = None;
    let status = child.wait();
    tokio::pin!(status);
    loop {
        tokio::select! {
            result = &mut status, if exit_status.is_none() => {
                exit_status = Some(result.map_err(VideoError::Spawn)?);
            }
            line = lines_rx.recv() => {
                let Some(line) = line else {
                    let status = match exit_status {
                        Some(status) => status,
                        None => status.await.map_err(VideoError::Spawn)?,
                    };
                    if status.success() {
                        return final_path.ok_or(VideoError::MissingOutput);
                    }
                    return Err(VideoError::Failed(
                        last_error.unwrap_or_else(|| format!("exit code {}", status.code().unwrap_or(-1)))
                    ));
                };
                if let Some(path) = line.strip_prefix("MCDM_FILE:") {
                    final_path = Some(PathBuf::from(path.trim()));
                } else if let Some(event) = parse_progress(&line) {
                    let _ = events.send(event);
                } else if let Some(stage) = stage_for(&line) {
                    let _ = events.send(VideoEvent::Stage(stage));
                }
                if line.trim_start().starts_with("ERROR:") {
                    last_error = Some(line.trim().to_owned());
                }
            }
        }
    }
}

async fn read_lines<R>(reader: R, sender: UnboundedSender<String>)
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut lines = BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        if sender.send(line).is_err() {
            break;
        }
    }
}

fn parse_progress(line: &str) -> Option<VideoEvent> {
    let values: Vec<_> = line.strip_prefix("MCDM_PROGRESS:")?.split('|').collect();
    if values.len() < 4 {
        return None;
    }
    let received = parse_number(values[0]).max(0);
    let mut total = parse_number(values[1]);
    if total <= 0 {
        total = parse_number(values[2]);
    }
    let speed = values[3].parse::<f64>().unwrap_or(0.0).max(0.0);
    Some(VideoEvent::Progress {
        received,
        total,
        speed,
    })
}

fn parse_number(value: &str) -> i64 {
    value
        .parse::<f64>()
        .map(|number| number as i64)
        .unwrap_or(-1)
}

fn stage_for(line: &str) -> Option<String> {
    if line.starts_with("[download] Destination:") {
        return Some("Downloading media".to_owned());
    }
    if line.starts_with("[Merger]") {
        return Some("Merging video and audio".to_owned());
    }
    if line.starts_with("[VideoRemuxer]") || line.starts_with("[VideoConvertor]") {
        return Some("Converting video container".to_owned());
    }
    if line.contains("has already been downloaded") {
        return Some("File already downloaded".to_owned());
    }
    None
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use tempfile::tempdir;

    use super::{VideoEvent, parse_progress, stage_for, write_cookie_file};

    #[test]
    fn parses_ytdlp_progress_template() {
        let event = parse_progress("MCDM_PROGRESS:1024|4096|NA|512.5").unwrap();
        assert!(matches!(
            event,
            VideoEvent::Progress {
                received: 1024,
                total: 4096,
                speed
            } if speed == 512.5
        ));
    }

    #[test]
    fn recognizes_merge_stage() {
        assert_eq!(
            stage_for("[Merger] Merging formats into video.mp4"),
            Some("Merging video and audio".to_owned())
        );
    }

    #[tokio::test]
    async fn writes_browser_cookies_in_netscape_format() {
        let directory = tempdir().unwrap();
        let path = write_cookie_file(
            directory.path(),
            &[json!({
                "name": "session",
                "value": "secret",
                "domain": ".example.com",
                "path": "/",
                "secure": true,
                "expirationDate": 2_000_000_000
            })],
        )
        .await
        .unwrap()
        .unwrap();
        let body = tokio::fs::read_to_string(&path).await.unwrap();
        assert!(body.contains(".example.com\tTRUE\t/\tTRUE\t2000000000\tsession\tsecret"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
    }
}
