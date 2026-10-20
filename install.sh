#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="io.github.zhaohang1205.horae-tasks"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
LEGACY_DIR="$HOME/.config/omarchy/plugins/horae_for_omarchy_shell"

echo "==> Installing Horae for Omarchy Shell..."

# Check if horae is installed
if ! command -v horae >/dev/null 2>&1 && [[ ! -f "$HOME/.cargo/bin/horae" ]]; then
  echo "⚠️  Horae CLI not found. Please install it first:"
  echo "    cargo install --git https://github.com/zhaohang1205/horae.git --rev 87b70c7a6b179fca940ecc47e4baecce11c2f836"
fi

# Ensure private data and configuration directory with restricted permissions (0700)
mkdir -p -m 700 "$HOME/.config/horae"
chmod 700 "$HOME/.config/horae" 2>/dev/null || true
if [[ -f "$HOME/.config/horae/config.json" ]]; then
  chmod 600 "$HOME/.config/horae/config.json" 2>/dev/null || true
fi
if [[ -f "$HOME/.config/horae/horae.db" ]]; then
  chmod 600 "$HOME/.config/horae/horae.db"* 2>/dev/null || true
fi

mkdir -p "$HOME/.config/omarchy/plugins"

# Clean up legacy link if present
if [[ -L "$LEGACY_DIR" || -d "$LEGACY_DIR" ]]; then
  rm -rf "$LEGACY_DIR"
fi

# Link to plugins folder matching canonical plugin ID
if [[ "$SCRIPT_DIR" != "$TARGET_DIR" ]]; then
  rm -rf "$TARGET_DIR"
  ln -s "$SCRIPT_DIR" "$TARGET_DIR"
  echo "==> Linked plugin into $TARGET_DIR"
fi

# Rescan plugins in running shell
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

# Enable plugin on the bar
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable "$PLUGIN_ID" --section center 2>/dev/null || true
fi

# Set recommended defaults into shell.json
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell setBarWidget "$PLUGIN_ID" "maxWidth" "420" "{}" >/dev/null 2>&1 || true
  omarchy-shell shell setBarWidget "$PLUGIN_ID" "autoDismiss" "15" "{}" >/dev/null 2>&1 || true
fi

echo "✅ Horae plugin installed and configured successfully (autoDismiss: 15s, maxWidth: 420)!"
