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
const submitButton = document.querySelector<HTMLButtonElement>("#download-button")!;
const formError = document.querySelector<HTMLElement>("#form-error")!;

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
      await invoke("download_action", { id: item.id, action });
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
    const items = await invoke<DownloadSummary[]>("list_downloads");
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
    const info = await invoke<RuntimeInfo>("runtime_info");
    const running = info.bridgeStatus === "running";
    status.textContent = running ? "Bridge online" : info.bridgeStatus;
    status.className = `status-pill ${running ? "online" : "error"}`;
    copy.textContent = running
      ? `Listening locally on port ${info.bridgePort}`
      : "Browser bridge is unavailable";
    directory.textContent = `Saving to ${info.downloadDirectory}`;
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
    await invoke("add_download", {
      url: urlInput.value.trim(),
      filename: filenameInput.value.trim() || null,
    });
    urlInput.value = "";
    filenameInput.value = "";
    await refreshDownloads();
  } catch (error) {
    formError.textContent = String(error);
  } finally {
    submitButton.disabled = false;
  }
});

void refreshRuntime();
void refreshDownloads();
window.setInterval(refreshDownloads, 750);
window.setInterval(refreshRuntime, 5000);
