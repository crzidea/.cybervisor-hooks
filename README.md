# Cybervisor Hooks

A collection of shell hook scripts for **Cybervisor** that handle automated stage lifecycle notifications and commit reports via Telegram.

## 📋 Overview

This repository provides lifecycle hook scripts designed to integrate Cybervisor workflow stages with Telegram notifications:

- **`send-stage-notification.sh`**: Main Cybervisor hook script. Tracks stage progress (start, success, failure), iteration counts, retry attempts, and automatically generates detailed commit summaries for Git repositories modified during a "Commit" stage.
- **`send-telegram-message.sh`**: Telegram notification utility that formats and sends messages via Telegram Bot API (`curl`) using HTML formatting.

---

## 🚀 Features

- **Lifecycle Stage Tracking**: Reports when workflow stages start, succeed, or fail with status badges (🚀 Starting, ✅ Completed, ❌ Failed).
- **Commit Summary Reporting**: Automatically detects root and nested Git repositories in the workspace and appends commit hashes, commit subjects, and diff stats (`--shortstat`) to the Telegram notification.
- **State Baseline Persistence**: Tracks Git `HEAD` commits before stage execution to measure accurate diffs upon completion.
- **HTML Message Formatting**: Properly escapes special characters (`&`, `<`, `>`) and produces cleanly formatted HTML notifications.

---

## ⚙️ Configuration & Requirements

### 1. Telegram Credentials

Create a environment configuration file at `~/.cybervisor/telegram.env` (or pass a custom path via `CYBERVISOR_TELEGRAM_ENV_FILE`):

```bash
CYBERVISOR_TELEGRAM_BOT_TOKEN="your_bot_token_here"
CYBERVISOR_TELEGRAM_CHAT_ID="your_chat_id_here"
```

### 2. Environment Variables

The scripts accept the following environment variables (automatically set by Cybervisor or configured manually):

| Environment Variable | Default Value | Description |
| :--- | :--- | :--- |
| `CYBERVISOR_HOOK_PHASE` | `""` | Set to `before_stage` to record baseline commit states |
| `CYBERVISOR_STAGE_NAME` | `Unknown` | Name of current Cybervisor workflow stage |
| `CYBERVISOR_STAGE_SUCCESS` | `""` | `true`, `false`, or empty depending on stage status |
| `CYBERVISOR_STAGE_ITERATION` | `1` | Current iteration index |
| `CYBERVISOR_STAGE_MAX_ITERATIONS` | `1` | Total iterations for current stage |
| `CYBERVISOR_STAGE_ATTEMPT` | `1` | Current attempt index |
| `CYBERVISOR_STAGE_MAX_RETRIES` | `1` | Total maximum retries |
| `CYBERVISOR_TELEGRAM_ENV_FILE` | `~/.cybervisor/telegram.env` | Path to Telegram credentials file |

---

## 🛠️ Usage

### Direct Telegram Message

Send a custom text/HTML message via STDIN:

```bash
echo "<b>Notification:</b> Deployment complete!" | ./send-telegram-message.sh
```

### Stage Notification Hook

Execute at the start or end of a Cybervisor stage:

```bash
# Before stage starts (records Git HEAD baseline)
CYBERVISOR_HOOK_PHASE="before_stage" CYBERVISOR_STAGE_NAME="Build" ./send-stage-notification.sh

# After stage completes
CYBERVISOR_STAGE_NAME="Commit" CYBERVISOR_STAGE_SUCCESS="true" ./send-stage-notification.sh
```

---

## 📁 Repository Structure

```
.
├── .gitignore                  # Ignore state directory
├── send-stage-notification.sh  # Cybervisor stage notification hook
├── send-telegram-message.sh    # Telegram API client script
└── README.md                   # Repository documentation
```
