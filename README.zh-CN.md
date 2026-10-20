# Horae Tasks & Pomodoro

[English](README.md) | 简体中文

![Horae Tasks & Pomodoro](preview.png)

优雅简洁、快速轻巧的 [Omarchy](https://omarchy.org/) Quattro 状态栏组件，由高性能 [Horae](https://github.com/zhaohang1205/horae) Rust 核心引擎强力驱动。在状态栏一眼掌握即将到期的 GTD 任务流，秒级弹窗录入闪念灵感，一键开启番茄专注流——零上下文切换，保持心流，告别臃肿。

## 功能特性

- **🍅 番茄钟会话仪表盘**：弹窗顶部以精致仪表呈现专注状态——递减进度环 + 大字 `mm:ss` 倒计时（工作阶段红色脉冲，休息阶段绿色呼吸）、阶段着色的统计行（专注中 / 短休 / 长休 + 今日 / 连续 / 累计），运行时附带朝向长休的轮次进度点（如 `●●○`）。下方一键即可开启或停止专注。状态栏深度一体化：会话运行时，动态递减进度环与秒级倒计时直接内嵌融合在当前专注的任务项上，无需在右侧占用多余空间。
- **🔒 状态栏隐私模式**：状态栏支持一键切换隐私模式（鼠标悬停组件时在最左侧呼出 `󰈈` / `󰈉` 图标，平时自动隐身不占空间；隐私模式仅作用于状态栏，弹出的操作小窗口中始终保持明文呈现）。开启后，状态栏上的待办任务与正在专注的番茄钟任务**完全隐藏任务标题，仅提示时间**（如待办任务显示 `⏰ 15:30`、正在专注显示 `🍅 24:50`），防止旁人一瞥窥见敏感日程；当您本人将鼠标悬浮于条目上时，浮窗（Tooltip）会自动提示任务完整标题与具体排程，兼顾极致隐私与便捷查看。
- **闪念快速录入**：左击状态栏番茄钟入口（平时随分隔符隐身，鼠标悬停时在最右侧呼出，运行中/无任务时常驻），立即在浮动终端中唤出 Horae 原生闪念录入窗口（`horae --flash`）。享受终端内完整的语法高亮、动态卡槽提示（`[*周期] [~时间] [!优先级] [@标签]`）与标签补全，敲击回车即可自动保存至收件箱并秒级退出！
- **🍅 番茄钟参数配置**：无需进入终端命令行，点击 `⚙` 即可展开 2×2 数字微调网格：
  - 参数式微调与填入：支持方向步进或直接输入数字，快速调整专注时长（1-180 分钟）、短休时长（1-60 分钟）、长休时长（1-90 分钟）及长休轮数（1-12 轮）。
  - 一键恢复默认：提供“恢复默认 (25/5/15/4)”按钮，可随时一键重置为标准经典番茄钟设置。
  - 修改即时同步并保存至 `~/.config/horae/pomo.json`，与 Horae 核心引擎无缝互通。
- **即时任务流**：直接呈现由 Horae 引擎计算的即将到期与计划任务窗口，悬停高亮、状态彩色徽章一目了然。
- **任务原生番茄钟仪表**：正在番茄钟专注的任务会自动固定到最前，任务图标由静态字符无缝替换为微型动态进度圆环（`PomoRing`），原排程时间自动切换为实时秒级倒计时，右击直达 TUI，双击快捷停止。
- **一键快捷操作面板**：点击状态栏任务项展开操作面板：
  - 🍅 **全局专注控制台**：主控制栏集成【开始专注 / 停止】、【闪念录入】与【TUI 终端】；选定任务时一键对该任务启动专注。
  - ✅ **标记完成**：标记任务已完成（正在专注时自动结算停用番茄钟）。
  - ⏱️ **延迟 1h**：将任务日程顺延 1 小时。
  - 📦 **归档任务**：将任务软删除归档。
- **悬停跑马灯**：标题超出宽度时，悬停鼠标自动平滑横向滚动，平时保持沉浸简洁。
- **番茄钟与 TUI 深度联动**：左击番茄钟入口打开快速录入（`horae --flash`），右击直接唤出或聚焦 Horae TUI 终端窗口（`omarchy-launch-or-focus-tui horae`）；双击停止番茄钟。
- **原生双语支持**：设置页（`⚙`）右上角配备滑动开关，支持中/英一键即时无缝切换。
- **事件驱动极低开销**：通过文件监听 `horae.db` 与 `pomo.json`，实现毫秒级即时同步与无轮询低能耗；倒计时基于会话时间戳本地推算，不再每秒调用外部进程。

## 前置依赖

- Omarchy Quattro shell
- 已安装 [Horae](https://github.com/zhaohang1205/horae) CLI 工具：

  ```bash
  cargo install --git https://github.com/zhaohang1205/horae.git --rev ef187817ec29411907aed5366a26b1167aaf417e
  ```

## 安装与配置

### 方法 1：一键自动化安装（推荐）

直接克隆或在本地仓库运行自带的安装脚本，将自动完成插件链接、居中启用以及推荐参数（`maxWidth: 420`, `autoDismiss: 15`）注入：

```bash
git clone https://github.com/zhaohang1205/horae_for_omarchy_shell.git
cd horae_for_omarchy_shell
./install.sh
```

### 方法 2：使用 Omarchy CLI 安装

```bash
omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable
```

> **提示**：插件代码内已默认开启 15 秒自动消失（`autoDismiss: 15`），安装即生效。若需要将参数显式写入 `~/.config/omarchy/shell.json`，可执行：
>
> ```bash
> omarchy-shell shell setBarWidget "io.github.zhaohang1205.horae-tasks" "autoDismiss" "15" "{}"
> omarchy-shell shell setBarWidget "io.github.zhaohang1205.horae-tasks" "maxWidth" "420" "{}"
> ```

## 状态栏位置调整

将组件移动到状态栏的中部或右侧：

```bash
omarchy bar move io.github.zhaohang1205.horae-tasks --section center
```

或者在 `~/.config/omarchy/shell.json` 的 `bar.layout` 中进行配置：

```json
{
  "id": "io.github.zhaohang1205.horae-tasks",
  "maxWidth": 420,
  "autoDismiss": 15
}
```

## 安全卸载

无论通过哪种方式安装，都可以通过以下方式之一完成**干净、安全**的卸载（自动从状态栏下线、清理插件目录并重新加载 Shell，绝不破坏您的个人 Horae 任务数据）：

### 方法 1：使用官方 Omarchy CLI（推荐）

```bash
omarchy plugin remove io.github.zhaohang1205.horae-tasks
```

### 方法 2：使用项目自带卸载脚本

```bash
./uninstall.sh
```

## 设置选项

可以在 `~/.config/omarchy/shell.json` 针对该组件项配置以下参数：

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `horaeBin` | string | `"~/.cargo/bin/horae"` | `horae` 可执行文件路径 |
| `dataDir` | string | `"~/.config/horae"` | 存放 `pomo.json` 与 `horae.db` 的数据目录 |
| `profile` | string | `""` | 指定 Horae profile 数据集 |
| `limit` | number | `10` | 查询候选任务数上限 |
| `displayMax` | number | `2` | 状态栏同时展示的任务数量 |
| `maxWidth` | number | `420` | 组件在状态栏上的最大逻辑像素宽度 |
| `alwaysShow` | boolean | `true` | 无待办任务时是否常驻显示番茄钟驻留入口 |
| `textColor` | string | `""` | 自定义文本颜色（默认继承状态栏前景色） |
| `privacyMode` | boolean | `false` | 隐私模式（开启后仅暴露任务首字/单词） |
| `autoDismiss` | number | `15` | 小窗口无操作/移开鼠标后自动消失时间（秒，设为 `0` 禁用自动消失） |
| `lang` | string | `""` | 语言设置（`"zh"` 或 `"en"`，留空自动检测系统语言） |

## 推荐窗口规则（Hyprland 弹窗配置）

为了让闪念录入窗口（`horae --flash`）以精致、居中的浮动小弹窗尺寸呈现，推荐在 `~/.config/hypr/hyprland.lua` 中添加：

```lua
-- Horae 闪念快速录入居中紧凑小弹窗
o.window("^org\\.omarchy\\.horae-flash$", {
 float = true,
 center = true,
 size = { 760, 360 },
})
```

## Quattro Shell 指令

支持通过 Omarchy Quattro shell 命令行唤出或收起面板：

```bash
omarchy-shell shell summon io.github.zhaohang1205.horae-tasks '{}'
omarchy-shell shell hide io.github.zhaohang1205.horae-tasks
```

## 卸载

```bash
omarchy plugin remove io.github.zhaohang1205.horae-tasks
```

## 开源许可

[MIT](LICENSE) © 2026 alex zhao
