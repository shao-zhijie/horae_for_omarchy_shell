#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="io.github.zhaohang1205.horae-tasks"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
TARGET_DIR="$PLUGINS_DIR/$PLUGIN_ID"
LEGACY_DIR="$PLUGINS_DIR/horae_for_omarchy_shell"

echo "==> Uninstalling Horae for Omarchy Shell..."

# 1. Disable plugin and remove widget from bar layout in shell.json
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
elif command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false >/dev/null 2>&1 || true
fi

# 2. Remove plugin directory or symlink from Omarchy plugins directory
if [[ -L "$TARGET_DIR" || -d "$TARGET_DIR" ]]; then
  rm -rf "$TARGET_DIR"
  echo "==> Removed $TARGET_DIR"
fi

if [[ -L "$LEGACY_DIR" || -d "$LEGACY_DIR" ]]; then
  rm -rf "$LEGACY_DIR"
fi

# 3. Request omarchy-shell to rescan and unload the plugin
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

echo "✅ Horae Omarchy shell plugin uninstalled successfully!"
echo "ℹ️  Note: Your personal Horae data (~/.config/horae) has been preserved."
