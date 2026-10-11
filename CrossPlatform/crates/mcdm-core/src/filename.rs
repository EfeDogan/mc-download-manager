use std::path::{Path, PathBuf};

const WINDOWS_RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
    "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

pub fn sanitize(input: &str) -> String {
    let mut value: String = input
        .chars()
        .filter_map(|character| {
            if character == '\0' || character.is_control() {
                None
            } else if matches!(
                character,
                '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*'
            ) {
                Some('_')
            } else {
                Some(character)
            }
        })
        .collect();

    value = value.trim().trim_end_matches(['.', ' ']).to_owned();
    if value.starts_with('.') {
        value.insert(0, '_');
    }

    let stem = value
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_uppercase();
    if WINDOWS_RESERVED.contains(&stem.as_str()) {
        value.insert(0, '_');
    }

    if value.chars().count() > 180 {
        value = value.chars().take(180).collect();
        value = value.trim_end_matches(['.', ' ']).to_owned();
    }

    if value.is_empty() {
        "download".to_owned()
    } else {
        value
    }
}

pub async fn unique_destination(directory: &Path, filename: &str) -> PathBuf {
    let initial = directory.join(filename);
    if !tokio::fs::try_exists(&initial).await.unwrap_or(false) {
        return initial;
    }

    let path = Path::new(filename);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("download");
    let extension = path.extension().and_then(|value| value.to_str());
    for number in 2_u32.. {
        let candidate = match extension {
            Some(extension) if !extension.is_empty() => {
                directory.join(format!("{stem} ({number}).{extension}"))
            }
            _ => directory.join(format!("{stem} ({number})")),
        };
        if !tokio::fs::try_exists(&candidate).await.unwrap_or(false) {
            return candidate;
        }
    }
    unreachable!("the destination suffix space is unbounded")
}

#[cfg(test)]
mod tests {
    use super::sanitize;

    #[test]
    fn sanitizes_cross_platform_invalid_characters() {
        assert_eq!(sanitize("report<2026>:part?.zip"), "report_2026__part_.zip");
        assert_eq!(sanitize("folder\\name/file.txt"), "folder_name_file.txt");
        assert_eq!(sanitize("trailing. "), "trailing");
    }

    #[test]
    fn protects_windows_device_names_and_hidden_parts() {
        assert_eq!(sanitize("CON"), "_CON");
        assert_eq!(sanitize("com1.txt"), "_com1.txt");
        assert_eq!(sanitize(".download"), "_.download");
        assert_eq!(sanitize("\0"), "download");
    }
}
