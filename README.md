# Horae Tasks & Pomodoro

English | [简体中文](README.zh-CN.md)

![Horae Tasks & Pomodoro](preview.png)

An [Omarchy](https://omarchy.org/) Quattro shell bar widget that brings upcoming and overdue [Horae](https://github.com/zhaohang1205/horae) GTD tasks and Pomodoro controls directly onto your status bar. Click to act without leaving your workflow or opening a terminal.

## Features

- **🔒 Privacy Mode**: Quick toggle for privacy masking on the bar (revealed on hover on the far left, or inside the panel / settings). When enabled, task titles and running Pomodoros on the bar only reveal their **first character** (for CJK, e.g. `铲…`) or **first word** (for English, e.g. `meeting…`), preventing sensitive tasks from being leaked during presentations, meetings, screen shares, or in public spaces.
- **Quick Flash Capture**: Left-click the `🍅` Pomodoro icon on the bar (revealed on hover alongside `│`, or always visible when running/empty) to launch Horae's native flash capture mode (`horae --flash`) in a floating terminal. Enjoy full terminal syntax highlighting, dynamic slot hints (`[*rrule] [~time] [!priority] [@tag]`), and tag completion. Type your task and press Enter to save and exit immediately!
- **🍅 Pomodoro Parameter Config**: Configure your Pomodoro timer directly without entering the terminal. Click `⚙` on the panel or settings button to adjust:
  - Focus work duration (default 25 mins, with 15m / 25m / 45m / 50m presets or custom stepper)
  - Short break duration (default 5 mins, with 3m / 5m / 10m / 15m presets)
  - Long break duration (default 15 mins, with 10m / 15m / 20m / 30m presets)
  - Long break cycle interval (default 4 cycles, with 2 / 3 / 4 / 5 presets)
  - Changes instantly update and sync to `~/.config/horae/pomo.json` across CLI, daemon, and TUI.
- **Live GTD Task Stream**: Shows your upcoming and planned tasks calculated directly by Horae.
- **Active Focus Indicator**: When a Pomodoro is running, the active task is pinned to the front with 🍅 and a live pulse/countdown.
- **Quick Action Popup**: Click any task on the status bar to inspect details and perform one-click actions:
  - 🍅 **Start Pomodoro**: Focus on this task immediately.
  - ⏱️ **+1h Delay**: Push the schedule back by one hour.
  - ✅ **Done**: Mark task completed (stops active Pomodoro automatically).
  - 📦 **Archive**: Soft-delete the task into archive.
  - ⚡ **+ Flash Capture**: Quick button inside the card to trigger `horae --flash`.
  - ⚙️ **Pomo Settings**: Switch directly to Pomodoro & widget settings.
  - 🖥️ **Open TUI**: Open the full Horae TUI dashboard.
- **Smooth Marquee Scroll**: Long titles neatly fit the bar and scroll smoothly on hover.
- **Pomodoro & TUI Integration**: Left-click the Pomodoro icon for flash capture; right-click to summon or focus the Horae TUI (`omarchy-launch-or-focus-tui horae`); double-click to stop Pomodoro.
- **Bilingual Interface**: Seamless one-click sliding toggle for Chinese / English UI on the top-right corner.
- **Event-Driven & Light**: Watches `horae.db` and `pomo.json` for zero-polling instant updates.

## Prerequisites

- Omarchy Quattro shell
- [Horae](https://github.com/zhaohang1205/horae) CLI installed:
  ```bash
  cargo install --git https://github.com/zhaohang1205/horae.git
  ```

## Installation

```bash
omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable
```

## Bar Placement

To place the widget in the center or right section of your bar:

```bash
omarchy bar move io.github.zhaohang1205.horae-tasks --section center
```

Or configure it in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.zhaohang1205.horae-tasks",
  "maxWidth": 420
}
```

## Settings

Settings can be specified in `~/.config/omarchy/shell.json` under the widget entry:

| Setting | Type | Default | Description |
|---|---|---|---|
| `horaeBin` | string | `"~/.cargo/bin/horae"` | Path to the `horae` executable |
| `dataDir` | string | `"~/.config/horae"` | Directory containing `pomo.json` and `horae.db` |
| `profile` | string | `""` | Optional Horae profile name |
| `limit` | number | `10` | Task query candidate limit |
| `displayMax` | number | `2` | Number of simultaneous tasks displayed on bar |
| `maxWidth` | number | `420` | Maximum width in logical pixels |
| `alwaysShow` | boolean | `true` | Keep bar widget visible even when idle |
| `textColor` | string | `""` | Custom text color (falls back to bar foreground) |
| `privacyMode` | boolean | `false` | Privacy mode (only reveal first character or word on bar) |
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
