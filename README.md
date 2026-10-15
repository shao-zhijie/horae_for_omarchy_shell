# Horae Tasks & Pomodoro

English | [简体中文](README.zh-CN.md)

![Horae Tasks & Pomodoro](preview.png)

An [Omarchy](https://omarchy.org/) Quattro shell bar widget that brings upcoming and overdue [Horae](https://github.com/zhaohang1205/horae) GTD tasks and Pomodoro controls directly onto your status bar. Click to act without leaving your workflow or opening a terminal.

## Features

- **Quick Flash Capture (`+`)**: Click the `+` icon on the bar to launch Horae's native flash capture mode (`horae --flash`) in a floating terminal. Enjoy full terminal syntax highlighting, dynamic slot hints (`[*rrule] [~time] [!priority] [@tag]`), and tag completion. Type your task and press Enter to save and exit immediately!
- **Live GTD Task Stream**: Shows your upcoming and overdue tasks calculated directly by Horae.
- **Active Focus Indicator**: When a Pomodoro is running, the active task is pinned to the front with 🍅 and a live pulse/countdown.
- **Quick Action Popup**: Click any task on the status bar to inspect details and perform one-click actions:
  - 🍅 **Start Pomodoro**: Focus on this task immediately.
  - ⏱️ **+1h Delay**: Push the schedule back by one hour.
  - ✅ **Done**: Mark task completed (stops active Pomodoro automatically).
  - 📦 **Archive**: Soft-delete the task into archive.
  - ⚡ **+ Flash Capture**: Quick button inside the card to trigger `horae --flash`.
  - 🖥️ **Open TUI**: Open the full Horae TUI dashboard.
- **Smooth Marquee Scroll**: Long titles neatly fit the bar and scroll smoothly on hover.
- **TUI Integration**: Right-click the Pomodoro indicator to summon or focus the Horae TUI (`omarchy-launch-or-focus-tui horae`); double-click to stop Pomodoro.
- **Bilingual Interface**: Automatically detects system locale for Chinese / English UI, or configurable via settings.
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
| `alwaysShow` | boolean | `true` | Keep bar widget visible with `+` capture button even when idle |
| `textColor` | string | `""` | Custom text color (falls back to bar foreground) |
| `lang` | string | `""` | Language override (`"en"` or `"zh"`, defaults to system locale) |

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
