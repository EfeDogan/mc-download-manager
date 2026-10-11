import { invoke } from "@tauri-apps/api/core";

type DownloadState =
  | "queued"
  | "probing"
  | "downloading"
  | "paused"
  | "completed"
  | "failed"
  | "cancelled";

type DownloadAction = "pause" | "resume" | "cancel" | "remove";
type DownloadKind = "file" | "video";
type ThemeName = "ink-wash" | "lush-forest" | "stormy-morning";
type ColorMode = "light" | "dark";

interface DownloadSummary {
  id: string;
  name: string;
  state: DownloadState;
  progress: number;
  speed: number;
  total: number;
  received: number;
  stage: string;
  error?: string;
}

interface RuntimeInfo {
  bridgePort: number;
  bridgeStatus: string;
  downloadDirectory: string;
  videoAvailable: boolean;
}

const stateLabels: Record<DownloadState, string> = {
  queued: "Queued",
  probing: "Connecting",
  downloading: "Downloading",
  paused: "Paused",
  completed: "Completed",
  failed: "Failed",
  cancelled: "Cancelled",
};

const list = document.querySelector<HTMLElement>("#download-list")!;
const emptyState = document.querySelector<HTMLElement>("#empty-state")!;
const count = document.querySelector<HTMLElement>("#download-count")!;
const form = document.querySelector<HTMLFormElement>("#download-form")!;
const urlInput = document.querySelector<HTMLInputElement>("#url-input")!;
const filenameInput = document.querySelector<HTMLInputElement>("#filename-input")!;
const kindInput = document.querySelector<HTMLSelectElement>("#kind-input")!;
const submitButton = document.querySelector<HTMLButtonElement>("#download-button")!;
const formError = document.querySelector<HTMLElement>("#form-error")!;
const extensionButton = document.querySelector<HTMLButtonElement>("#extension-button")!;
const firefoxExtensionButton = document.querySelector<HTMLButtonElement>("#firefox-extension-button")!;
const extensionResult = document.querySelector<HTMLElement>("#extension-result")!;
const settingsButton = document.querySelector<HTMLButtonElement>("#settings-button")!;
const settingsDialog = document.querySelector<HTMLDialogElement>("#settings-dialog")!;
const settingsClose = document.querySelector<HTMLButtonElement>("#settings-close")!;
const themeInputs = Array.from(document.querySelectorAll<HTMLInputElement>('input[name="theme"]'));
const modeInputs = Array.from(document.querySelectorAll<HTMLInputElement>('input[name="color-mode"]'));
const openDownloadFolderButton = document.querySelector<HTMLButtonElement>("#open-download-folder")!;
const folderResult = document.querySelector<HTMLElement>("#folder-result")!;
let kindWasChosenManually = false;

const themeLabels: Record<ThemeName, string> = {
  "ink-wash": "Ink wash",
  "lush-forest": "Lush forest",
  "stormy-morning": "Stormy morning",
};

const modeLabels: Record<ColorMode, string> = {
  light: "Light",
  dark: "Dark",
};

const isTauriRuntime = "__TAURI_INTERNALS__" in window;

async function appInvoke<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  if (isTauriRuntime) return invoke<T>(command, args);

  // Keep the browser-based design preview representative without weakening the
  // desktop runtime path, which always delegates to Tauri above.
  if (command === "runtime_info") {
    return {
      bridgePort: 48213,
      bridgeStatus: "running",
      downloadDirectory: "~/Downloads/MC Download Manager",
      videoAvailable: true,
    } as T;
  }
  if (command === "list_downloads") return [] as T;
  if (command === "download_action") return undefined as T;
  if (command === "open_download_directory") return undefined as T;

  throw new Error("This action is available in the desktop app.");
}

function storedTheme(): ThemeName {
  try {
    const value = window.localStorage.getItem("mcdm-theme");
    if (value && Object.prototype.hasOwnProperty.call(themeLabels, value)) return value as ThemeName;
  } catch {}
  return "ink-wash";
}

function storedMode(): ColorMode {
  try {
    const value = window.localStorage.getItem("mcdm-color-mode");
    if (value && Object.prototype.hasOwnProperty.call(modeLabels, value)) return value as ColorMode;
  } catch {}
  return "light";
}

function applyAppearance(theme: ThemeName, mode: ColorMode): void {
  document.documentElement.dataset.theme = theme;
  document.documentElement.dataset.mode = mode;
  settingsButton.textContent = `Settings · ${themeLabels[theme]} · ${modeLabels[mode]}`;
  for (const input of themeInputs) input.checked = input.value === theme;
  for (const input of modeInputs) input.checked = input.value === mode;
  try {
    window.localStorage.setItem("mcdm-theme", theme);
    window.localStorage.setItem("mcdm-color-mode", mode);
  } catch {}
}

applyAppearance(storedTheme(), storedMode());

const videoHosts = [
  "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitter.com", "x.com",
  "instagram.com", "tiktok.com", "twitch.tv", "facebook.com", "reddit.com", "bilibili.com",
];

function looksLikeVideoPage(value: string): boolean {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    return videoHosts.some((candidate) => host === candidate || host.endsWith(`.${candidate}`));
  } catch {
    return false;
  }
}

function syncKindUi(): void {
  const video = kindInput.value === "video";
  filenameInput.disabled = video;
  filenameInput.placeholder = video ? "Chosen by yt-dlp" : "archive.zip";
  if (video) filenameInput.value = "";
}

function formatBytes(value: number): string {
  if (value < 0 || !Number.isFinite(value)) return "Unknown";
  if (value === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const unit = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
  const amount = value / 1024 ** unit;
  return `${amount >= 10 || unit === 0 ? amount.toFixed(0) : amount.toFixed(1)} ${units[unit]}`;
}

function actionButton(label: string, action: DownloadAction, item: DownloadSummary): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = action === "remove" ? "icon-button danger" : "icon-button";
  button.textContent = label;
  button.title = `${label} ${item.name}`;
  button.addEventListener("click", async () => {
    button.disabled = true;
    try {
      await appInvoke("download_action", { id: item.id, action });
      await refreshDownloads();
    } catch (error) {
      formError.textContent = String(error);
    } finally {
      button.disabled = false;
    }
  });
  return button;
}

function renderDownload(item: DownloadSummary): HTMLElement {
  const card = document.createElement("article");
  card.className = "download-card";

  const titleRow = document.createElement("div");
  titleRow.className = "download-title-row";
  const text = document.createElement("div");
  const title = document.createElement("h3");
  title.textContent = item.name;
  const detail = document.createElement("p");
  const received = formatBytes(item.received);
  const total = item.total >= 0 ? ` of ${formatBytes(item.total)}` : "";
  const speed = item.speed > 0 ? ` · ${formatBytes(item.speed)}/s` : "";
  detail.textContent = item.error || item.stage || `${received}${total}${speed}`;
  text.append(title, detail);

  const badge = document.createElement("span");
  badge.className = `state-badge ${item.state}`;
  badge.textContent = stateLabels[item.state];
  titleRow.append(text, badge);

  const progress = document.createElement("div");
  progress.className = "progress-track";
  progress.setAttribute("role", "progressbar");
  progress.setAttribute("aria-label", `${item.name} progress`);
  progress.setAttribute("aria-valuemin", "0");
  progress.setAttribute("aria-valuemax", "100");
  progress.setAttribute("aria-valuenow", String(Math.round(item.progress * 100)));
  const bar = document.createElement("div");
  bar.className = `progress-bar ${item.state}`;
  bar.style.width = `${Math.max(0, Math.min(100, item.progress * 100))}%`;
  progress.append(bar);

  const actions = document.createElement("div");
  actions.className = "download-actions";
  if (["queued", "probing", "downloading"].includes(item.state)) {
    actions.append(actionButton("Pause", "pause", item), actionButton("Cancel", "cancel", item));
  } else if (["paused", "failed", "cancelled"].includes(item.state)) {
    actions.append(actionButton("Resume", "resume", item));
  }
  actions.append(actionButton("Remove", "remove", item));

  card.append(titleRow, progress, actions);
  return card;
}

async function refreshDownloads(): Promise<void> {
  try {
    const items = await appInvoke<DownloadSummary[]>("list_downloads");
    list.replaceChildren(...items.map(renderDownload));
    emptyState.hidden = items.length > 0;
    count.textContent = `${items.length} ${items.length === 1 ? "item" : "items"}`;
  } catch (error) {
    formError.textContent = `Could not read downloads: ${String(error)}`;
  }
}

async function refreshRuntime(): Promise<void> {
  const status = document.querySelector<HTMLElement>("#bridge-status")!;
  const copy = document.querySelector<HTMLElement>("#runtime-copy")!;
  const directory = document.querySelector<HTMLElement>("#download-directory")!;
  try {
    const info = await appInvoke<RuntimeInfo>("runtime_info");
    const running = info.bridgeStatus === "running";
    status.textContent = running ? "Bridge online" : info.bridgeStatus;
    status.className = `status-pill ${running ? "online" : "error"}`;
    copy.textContent = running
      ? `Listening on port ${info.bridgePort} · ${info.videoAvailable ? "yt-dlp ready" : "yt-dlp missing"}`
      : "Browser bridge is unavailable";
    directory.textContent = `Saving to ${info.downloadDirectory}`;
    openDownloadFolderButton.disabled = false;
  } catch (error) {
    status.textContent = "Unavailable";
    status.className = "status-pill error";
    copy.textContent = String(error);
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  formError.textContent = "";
  submitButton.disabled = true;
  try {
    await appInvoke("add_download", {
      url: urlInput.value.trim(),
      filename: filenameInput.value.trim() || null,
      kind: kindInput.value as DownloadKind,
    });
    urlInput.value = "";
    filenameInput.value = "";
    kindInput.value = "file";
    kindWasChosenManually = false;
    syncKindUi();
    await refreshDownloads();
  } catch (error) {
    formError.textContent = String(error);
  } finally {
    submitButton.disabled = false;
  }
});

kindInput.addEventListener("change", () => {
  kindWasChosenManually = true;
  syncKindUi();
});

urlInput.addEventListener("input", () => {
  if (!kindWasChosenManually) {
    kindInput.value = looksLikeVideoPage(urlInput.value.trim()) ? "video" : "file";
    syncKindUi();
  }
});

extensionButton.addEventListener("click", async () => {
  extensionButton.disabled = true;
  extensionResult.textContent = "";
  try {
    const path = await appInvoke<string>("install_browser_extension");
    extensionResult.textContent = `Chromium extension updated at ${path}. If it is already loaded, open chrome://extensions and click Reload on MC Download Manager. Otherwise enable Developer mode and choose Load unpacked.`;
  } catch (error) {
    extensionResult.textContent = String(error);
  } finally {
    extensionButton.disabled = false;
  }
});

firefoxExtensionButton.addEventListener("click", async () => {
  firefoxExtensionButton.disabled = true;
  extensionResult.textContent = "";
  try {
    const manifestPath = await appInvoke<string>("install_firefox_extension");
    extensionResult.textContent = `Firefox extension prepared at ${manifestPath}. Open about:debugging#/runtime/this-firefox, choose Load Temporary Add-on, then select this manifest.json. Temporary add-ons are removed when Firefox restarts.`;
  } catch (error) {
    extensionResult.textContent = String(error);
  } finally {
    firefoxExtensionButton.disabled = false;
  }
});

settingsButton.addEventListener("click", () => settingsDialog.showModal());
settingsClose.addEventListener("click", () => settingsDialog.close());
settingsDialog.addEventListener("click", (event) => {
  if (event.target === settingsDialog) settingsDialog.close();
});
for (const input of themeInputs) {
  input.addEventListener("change", () => applyAppearance(input.value as ThemeName, storedMode()));
}
for (const input of modeInputs) {
  input.addEventListener("change", () => applyAppearance(storedTheme(), input.value as ColorMode));
}

openDownloadFolderButton.addEventListener("click", async () => {
  openDownloadFolderButton.disabled = true;
  folderResult.textContent = "";
  try {
    await appInvoke("open_download_directory");
    folderResult.textContent = "Download folder opened.";
  } catch (error) {
    folderResult.textContent = `Could not open the download folder: ${String(error)}`;
    formError.textContent = folderResult.textContent;
  } finally {
    openDownloadFolderButton.disabled = false;
  }
});

void refreshRuntime();
void refreshDownloads();
syncKindUi();
window.setInterval(refreshDownloads, 750);
window.setInterval(refreshRuntime, 5000);
