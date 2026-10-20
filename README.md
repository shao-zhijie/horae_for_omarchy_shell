# Horae Tasks & Pomodoro

English | [简体中文](README.zh-CN.md)

![Horae Tasks & Pomodoro](preview.png)

An elegant, lightweight, and blazingly fast [Omarchy](https://omarchy.org/) Quattro shell bar widget powered by the [Horae](https://github.com/zhaohang1205/horae) Rust engine. Glance at upcoming GTD tasks, capture thoughts instantly in a floating modal, and master your focus with smart Pomodoro timers right on your status bar—zero context switching, zero bloat.

## Features

- **🍅 Pomodoro Session Instrument**: The popup leads with a live focus gauge — a depleting progress ring with a large `mm:ss` countdown (focus pulses in red, breaks breathe in green), a phase-tinted stats line (Focus / Short break / Long break + today / streak / total), and round progress dots toward the next long rest (e.g. `●●○`) while a session runs. One tap starts or stops the session right from the gauge. On the status bar, the miniature depleting gauge and live countdown are integrated directly inside the active task item itself, avoiding separate redundant widgets on the bar.
- **🔒 Privacy Mode**: Quick toggle for privacy masking on the bar (revealed on hover on the far left of the bar; only affects the status bar, while popout cards remain in plaintext). When enabled, task titles and running Pomodoros on the bar **hide their titles completely and only reveal the scheduled time or countdown** (e.g., tasks show `⏰ 15:30` and running Pomodoros show `🍅 24:50`), preventing bystanders from catching sensitive tasks at a glance. When you hover your mouse over the item, the tooltip automatically reveals the full title and schedule details, perfectly balancing top-tier privacy with effortless peeking.
- **Quick Flash Capture**: Left-click the Pomodoro icon on the bar (revealed on hover alongside `│`, or always visible when running/empty) to launch Horae's native flash capture mode (`horae --flash`) in a floating terminal. Enjoy full terminal syntax highlighting, dynamic slot hints (`[*rrule] [~time] [!priority] [@tag]`), and tag completion. Type your task and press Enter to save and exit immediately!
- **🍅 Pomodoro Parameter Config**: Configure your Pomodoro timer directly without entering the terminal. Click `⚙` to open a tidy 2×2 number-field grid:
  - Spinner & direct parameter inputs: Adjust focus work (1-180 mins), short break (1-60 mins), long break (1-90 mins), and cycles (1-12) via arrows or direct input.
  - One-click reset to default: Includes a "Reset Default (25/5/15/4)" button to restore classic Pomodoro settings instantly.
  - Changes instantly update and sync to `~/.config/horae/pomo.json` across CLI, daemon, and TUI.
- **Live GTD Task Stream**: Shows your upcoming and planned tasks calculated directly by Horae, with hover-highlighted rows and colored status pills.
- **Task-Native Focus Gauge**: When a Pomodoro is running, the active task is pinned to the front, its icon seamlessly turns into a miniature depleting progress ring (`PomoRing`), its time switches to a live countdown, and double-clicking the item stops the timer.
- **Quick Action Popup**: Click any task on the status bar to inspect details and perform one-click actions:
  - 🍅 **Unified Focus Console**: Header action bar houses 【Start / Stop Focus】, 【Flash Capture】, and 【TUI】; starts Pomodoro directly for selected task.
  - ✅ **Done**: Mark task completed (automatically stops and settles active Pomodoro).
  - ⏱️ **+1h Delay**: Push the schedule back by one hour.
  - 📦 **Archive**: Soft-delete the task into archive.
- **Smooth Marquee Scroll**: Long titles neatly fit the bar and scroll smoothly on hover.
- **Pomodoro & TUI Integration**: Left-click the Pomodoro icon for flash capture; right-click to summon or focus the Horae TUI (`omarchy-launch-or-focus-tui horae`); double-click to stop Pomodoro.
- **Bilingual Interface**: Seamless one-click sliding toggle for Chinese / English UI in the settings header (`⚙`, top-right).
- **Event-Driven & Light**: Watches `horae.db` and `pomo.json` for zero-polling instant updates; the countdown is rendered locally from the session timestamps — no per-second process spawns.

## Prerequisites

- Omarchy Quattro shell
- Private configuration directory with restricted permissions (`0700`):
  ```bash
  mkdir -p -m 700 ~/.config/horae
  ```
- [Horae](https://github.com/zhaohang1205/horae) CLI installed:

  ```bash
  cargo install --git https://github.com/zhaohang1205/horae.git --rev 5774a24d3395539dff43a4e0dbd48e59d050e76f
  ```

## Installation & Setup

### Method 1: Automated Setup Script (Recommended)

Clone the repository and run the included `install.sh` script to automatically link the plugin, enable it in the center section, and inject recommended defaults (`maxWidth: 420`, `autoDismiss: 15`):

```bash
git clone https://github.com/zhaohang1205/horae_for_omarchy_shell.git
cd horae_for_omarchy_shell
./install.sh
```

### Method 2: Standard Omarchy Plugin Add

```bash
omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable
```

> **Note**: An auto-dismiss timeout of 15 seconds (`autoDismiss: 15`) is built-in by default upon installation. To explicitly persist configuration options into `~/.config/omarchy/shell.json`, run:
>
> ```bash
> omarchy-shell shell setBarWidget "io.github.zhaohang1205.horae-tasks" "autoDismiss" "15" "{}"
> omarchy-shell shell setBarWidget "io.github.zhaohang1205.horae-tasks" "maxWidth" "420" "{}"
> ```

## Bar Placement

To place the widget in the center or right section of your bar:

```bash
omarchy bar move io.github.zhaohang1205.horae-tasks --section center
```

Or configure it in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.zhaohang1205.horae-tasks",
  "maxWidth": 420,
  "autoDismiss": 15
}
```

## Safe Uninstallation

You can cleanly and safely uninstall the plugin using either method below (automatically removes the widget from your bar and unloads it, preserving your personal Horae task database):

### Method 1: Via Omarchy CLI (Recommended)

```bash
omarchy plugin remove io.github.zhaohang1205.horae-tasks
```

### Method 2: Via Included Uninstall Script

```bash
./uninstall.sh
```

## Settings

Settings can be specified in `~/.config/omarchy/shell.json` under the widget entry:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `horaeBin` | string | `"~/.cargo/bin/horae"` | Path to the `horae` executable |
| `dataDir` | string | `"~/.config/horae"` | Directory containing `pomo.json` and `horae.db` |
| `profile` | string | `""` | Optional Horae profile name |
| `limit` | number | `10` | Task query candidate limit |
| `displayMax` | number | `2` | Number of simultaneous tasks displayed on bar |
| `maxWidth` | number | `420` | Maximum width in logical pixels |
| `alwaysShow` | boolean | `true` | Keep bar widget visible even when idle |
| `textColor` | string | `""` | Custom text color (falls back to bar foreground) |
| `privacyMode` | boolean | `false` | Privacy mode (only reveal first character or word on bar) |
| `autoDismiss` | number | `15` | Auto-dismiss timeout for the popout card in seconds (`0` to disable) |
| `lang` | string | `""` | Language override (`"en"` or `"zh"`, defaults to system locale) |

## Recommended Window Rules (Hyprland Floating Modal)

To have the flash capture window (`horae --flash`) launch as a sleek, centered floating modal dialog, add the following to `~/.config/hypr/hyprland.lua`:

```lua
-- Compact centered floating dialog for Horae flash capture
o.window("^org\\.omarchy\\.horae-flash$", {
 float = true,
 center = true,
 size = { 760, 360 },
})
```

## Shell Commands

Summon or hide the task popup via Quattro shell IPC:

```bash
omarchy-shell shell summon io.github.zhaohang1205.horae-tasks '{}'
omarchy-shell shell hide io.github.zhaohang1205.horae-tasks
```

## Removal

```bash
omarchy plugin remove io.github.zhaohang1205.horae-tasks
```

## License

[MIT](LICENSE) © 2026 alex zhao
