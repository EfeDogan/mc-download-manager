use std::{env, path::PathBuf};

use mcdm_core::{BridgeConfig, bridge};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let defaults = BridgeConfig::default();
    let port = env::var("MCDM_PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(defaults.port);
    let download_directory = env::var_os("MCDM_DOWNLOAD_DIR")
        .map(PathBuf::from)
        .unwrap_or(defaults.download_directory);
    let config = BridgeConfig {
        port,
        download_directory: download_directory.clone(),
    };

    println!("MC Download Manager bridge: http://127.0.0.1:{port}");
    println!("Downloads: {}", download_directory.display());
    bridge::run(config).await
}
